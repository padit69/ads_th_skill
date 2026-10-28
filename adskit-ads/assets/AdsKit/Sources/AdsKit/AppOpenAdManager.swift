//
//  AppOpenAdManager.swift
//  AdsKit
//
//  AdMob App Open ad: shown when the user opens the app (cold start or return from background).
//  - Never requests an ad before AdsConsentManager finished and UMP allows ads.
//  - Cold start: no ad unless `showsOnColdStart` is on (then only one ready within `openWindow`).
//  - A return from background only counts when the app stayed in background at least
//    `minimumBackgroundDuration` (default 5 s), so a quick app switch doesn't trigger an ad.
//  - Loaded ads expire after `adLifetime` (Google: 4 hours); a new one preloads after each show.
//  The app decides *whether* an open may show (Pro, onboarding, lock screen, sheets, remote switch)
//  and passes that as `canPresent`.
//

import UIKit
import GoogleMobileAds

@MainActor
public final class AppOpenAdManager: NSObject, ObservableObject {
    public struct Configuration: Sendable {
        public var adUnitID: String
        /// Minimum time between two shown ads.
        public var cooldown: TimeInterval
        public var adLifetime: TimeInterval
        public var openWindow: TimeInterval
        /// Time the app must spend in background before returning to it can show an ad.
        public var minimumBackgroundDuration: TimeInterval
        /// Show an ad on the launch itself, not only when returning from background.
        public var showsOnColdStart: Bool

        public init(adUnitID: String, cooldown: TimeInterval = 0,
                    adLifetime: TimeInterval = 4 * 3600, openWindow: TimeInterval = 5,
                    minimumBackgroundDuration: TimeInterval = 5, showsOnColdStart: Bool = false) {
            self.showsOnColdStart = showsOnColdStart
            self.adUnitID = adUnitID
            self.cooldown = cooldown
            self.minimumBackgroundDuration = minimumBackgroundDuration
            self.adLifetime = adLifetime
            self.openWindow = openWindow
        }

        /// Google's App Open test unit, for DEBUG builds.
        public static let testAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    }

    public static let shared = AppOpenAdManager()

    /// Set before `start()`. Nil (or an empty unit ID) keeps ads off.
    public var configuration: Configuration?

    @Published public private(set) var isShowing = false
    @Published public private(set) var isStarted = false

    /// Called after an ad was dismissed (or failed to present).
    public var onDismiss: (() -> Void)?

    private let consent: AdsConsentManager
    private var appOpenAd: AppOpenAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var pendingOpenEvent = false
    private var openEventAt: Date?
    private var lastShownAt: Date?
    private var enteredBackgroundAt: Date?
    private var hasHandledColdStart = false
    private var backgroundObserver: NSObjectProtocol?

    public init(consent: AdsConsentManager = .shared) {
        self.consent = consent
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enteredBackgroundAt = Date() }
        }
    }

    /// Real AdMob app ID present in Info.plist (the SDK crashes without one).
    public static var hasAppID: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ?? ""
        return !id.isEmpty && !id.hasPrefix("$(")
    }

    private var adUnitID: String? {
        guard let id = configuration?.adUnitID, !id.isEmpty else { return nil }
        return id
    }

    // MARK: Lifecycle

    /// Marks an app open (cold start or return from background); consumed by the next eligible show.
    /// The launch itself is ignored unless `showsOnColdStart`; a return after less than
    /// `minimumBackgroundDuration` in background is ignored too.
    public func appDidOpen() {
        if !hasHandledColdStart {
            hasHandledColdStart = true
            if !(configuration?.showsOnColdStart ?? false), enteredBackgroundAt == nil {
                pendingOpenEvent = false
                return
            }
        }
        if let enteredBackgroundAt {
            self.enteredBackgroundAt = nil
            let minimum = configuration?.minimumBackgroundDuration ?? 5
            guard Date().timeIntervalSince(enteredBackgroundAt) >= minimum else {
                pendingOpenEvent = false
                return
            }
        }
        pendingOpenEvent = true
        openEventAt = Date()
    }

    /// Starts the Mobile Ads SDK and preloads an ad. Waits for the consent flow; does nothing when
    /// consent doesn't allow ads, the app ID or ad unit is missing. Safe to call repeatedly.
    public func start() async {
        guard !isStarted, Self.hasAppID, adUnitID != nil else { return }
        await consent.waitUntilFinished()
        guard consent.phase == .finished, consent.canRequestAds else { return }
        isStarted = true
        _ = await MobileAds.shared.start()
        await loadAd()
    }

    // MARK: Loading / showing

    public var isAdReady: Bool {
        guard appOpenAd != nil, let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < (configuration?.adLifetime ?? 4 * 3600)
    }

    private func loadAd() async {
        guard isStarted, !isLoading, !isAdReady, let adUnitID, consent.canRequestAds else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let ad = try await AppOpenAd.load(with: adUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            loadedAt = Date()
        } catch {
            appOpenAd = nil
        }
    }

    /// Shows the ad for a pending open when allowed. Returns true when an ad was presented.
    /// - Parameter canPresent: the app's own rules (not Pro, onboarding done, not locked, no sheet…).
    @discardableResult
    public func showIfEligible(canPresent: Bool) async -> Bool {
        guard pendingOpenEvent, canPresent, isStarted, !isShowing, let configuration else { return false }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < configuration.cooldown {
            pendingOpenEvent = false
            return false
        }
        if !isAdReady {
            await loadAd()
            // Don't surprise the user with an ad that arrived long after they opened the app.
            guard let openEventAt, Date().timeIntervalSince(openEventAt) < configuration.openWindow else {
                pendingOpenEvent = false
                return false
            }
        }
        guard let ad = appOpenAd, let root = Self.topViewController() else { return false }
        pendingOpenEvent = false
        isShowing = true
        lastShownAt = Date()
        ad.present(from: root)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private func finishShowing() {
        isShowing = false
        appOpenAd = nil
        loadedAt = nil
        onDismiss?()
        Task { await loadAd() }
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    nonisolated public func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in self.finishShowing() }
    }

    nonisolated public func ad(_ ad: any FullScreenPresentingAd,
                               didFailToPresentFullScreenContentWithError error: any Error) {
        Task { @MainActor in self.finishShowing() }
    }
}
