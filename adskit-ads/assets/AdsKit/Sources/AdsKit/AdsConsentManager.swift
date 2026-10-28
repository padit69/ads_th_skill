//
//  AdsConsentManager.swift
//  AdsKit
//
//  Gathers ad consent at launch: Google UMP first (it decides whether personalised ads may be
//  requested), then Apple's App Tracking Transparency prompt. Ads themselves live in AppOpenAdManager.
//

import Foundation
import UIKit
import AppTrackingTransparency
import UserMessagingPlatform

/// Options for the consent flow. Debug values only apply in builds that set them.
public struct AdsConsentConfiguration: Sendable {
    public enum DebugGeography: Sendable {
        case disabled, eea, regulatedUSState, other
    }

    /// Pretend the device is in a region (needs `testDeviceIdentifiers` on real devices).
    public var debugGeography: DebugGeography
    /// Hashed device IDs printed by UMP in the console.
    public var testDeviceIdentifiers: [String]
    /// Marks the user as under the age of consent (no personalised ads).
    public var tagForUnderAgeOfConsent: Bool
    /// Ask ATT after UMP. Turn off when the app doesn't use the IDFA.
    public var requestsTrackingAuthorization: Bool
    /// Upper bound for the consent info request so the splash never waits on a slow network.
    public var consentInfoTimeout: TimeInterval

    public init(debugGeography: DebugGeography = .disabled,
                testDeviceIdentifiers: [String] = [],
                tagForUnderAgeOfConsent: Bool = false,
                requestsTrackingAuthorization: Bool = true,
                consentInfoTimeout: TimeInterval = 8) {
        self.debugGeography = debugGeography
        self.testDeviceIdentifiers = testDeviceIdentifiers
        self.tagForUnderAgeOfConsent = tagForUnderAgeOfConsent
        self.requestsTrackingAuthorization = requestsTrackingAuthorization
        self.consentInfoTimeout = consentInfoTimeout
    }
}

@MainActor
public final class AdsConsentManager: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case gathering
        case finished
    }

    public static let shared = AdsConsentManager()

    public var configuration = AdsConsentConfiguration()

    @Published public private(set) var phase: Phase = .idle
    /// UMP's answer: ads (personalised or not, per the user's choice) may be requested.
    @Published public private(set) var canRequestAds: Bool
    /// Show a "Privacy choices" entry in Settings when true (required in regulated regions).
    @Published public private(set) var isPrivacyOptionsRequired: Bool
    @Published public private(set) var trackingStatus: ATTrackingManager.AuthorizationStatus
    /// Last UMP error (network, misconfigured app ID…). The flow still finishes with the stored consent.
    @Published public private(set) var lastError: Error?

    public var isTrackingAuthorized: Bool { trackingStatus == .authorized }

    private var launchTask: Task<Void, Never>?

    public init() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    }

    // MARK: Launch

    /// UMP, then ATT. Runs once per process; every caller awaits the same run.
    public func requestOnLaunch() async {
        if let launchTask { return await launchTask.value }
        phase = .gathering
        let task = Task { @MainActor in
            await gatherConsent()
            if configuration.requestsTrackingAuthorization {
                await requestTrackingAuthorizationIfNeeded()
            }
            phase = .finished
        }
        launchTask = task
        await task.value
    }

    /// Waits until the launch flow finished (returns at once if it never started).
    public func waitUntilFinished() async {
        await launchTask?.value
    }

    // MARK: UMP

    /// Refreshes consent info and shows the UMP form when Google requires it.
    public func gatherConsent() async {
        lastError = nil
        let parameters = makeRequestParameters()
        let timeout = configuration.consentInfoTimeout
        do {
            let updated = try await withTimeout(seconds: timeout) {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            }
            if updated {
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
            }
        } catch {
            // Falls back to the consent stored from an earlier launch; canRequestAds reflects it.
            lastError = error
        }
        refreshState()
    }

    /// Re-opens the consent choices (Settings → Privacy choices).
    public func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        refreshState()
    }

    /// DEBUG helper: forgets the stored UMP choice so the form shows again. Never call in production.
    public func resetConsent() {
        ConsentInformation.shared.reset()
        launchTask = nil
        phase = .idle
        refreshState()
    }

    // MARK: ATT

    /// Shows the ATT prompt when the status is still undetermined. Returns the resulting status.
    @discardableResult
    public func requestTrackingAuthorizationIfNeeded() async -> ATTrackingManager.AuthorizationStatus {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            trackingStatus = ATTrackingManager.trackingAuthorizationStatus
            return trackingStatus
        }
        // iOS drops the request unless the app is active, and right after another alert (the UMP
        // form) has just been dismissed — so wait for active, then give the UI a moment to settle.
        for attempt in 0..<2 {
            await waitUntilActive()
            try? await Task.sleep(nanoseconds: attempt == 0 ? 500_000_000 : 1_000_000_000)
            await waitUntilActive()
            let status = await ATTrackingManager.requestTrackingAuthorization()
            trackingStatus = status
            if status != .notDetermined { break }
        }
        return trackingStatus
    }

    // MARK: Helpers

    private func refreshState() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
    }

    private func makeRequestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = configuration.tagForUnderAgeOfConsent
        if configuration.debugGeography != .disabled || !configuration.testDeviceIdentifiers.isEmpty {
            let debug = DebugSettings()
            debug.testDeviceIdentifiers = configuration.testDeviceIdentifiers
            switch configuration.debugGeography {
            case .disabled: debug.geography = .disabled
            case .eea: debug.geography = .EEA
            case .regulatedUSState: debug.geography = .regulatedUSState
            case .other: debug.geography = .other
            }
            parameters.debugSettings = debug
        }
        return parameters
    }

    private func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Returns true when `operation` finished in time, false on timeout (the operation keeps running).
    private func withTimeout(seconds: TimeInterval,
                             _ operation: @escaping @MainActor () async throws -> Void) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                try await operation()
                return true
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
