//
//  AdsConsentGate.swift
//  AdsKit
//
//  Shows a splash while the launch consent flow (UMP → ATT) runs, then the app.
//

import SwiftUI

public struct AdsConsentGate<Splash: View, Content: View>: View {
    @ObservedObject private var manager: AdsConsentManager
    private let isEnabled: Bool
    private let onFinish: (@MainActor (AdsConsentManager) -> Void)?
    private let splash: Splash
    private let content: Content

    /// - Parameters:
    ///   - isEnabled: false skips the flow (for example while the app is locked); the splash stays up
    ///     until it becomes true.
    ///   - onFinish: runs once after consent and ATT were handled (start the ads SDK here).
    public init(manager: AdsConsentManager = .shared,
                isEnabled: Bool = true,
                onFinish: (@MainActor (AdsConsentManager) -> Void)? = nil,
                @ViewBuilder splash: () -> Splash,
                @ViewBuilder content: () -> Content) {
        self.manager = manager
        self.isEnabled = isEnabled
        self.onFinish = onFinish
        self.splash = splash()
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
            if manager.phase != .finished {
                splash
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: manager.phase)
        .task(id: isEnabled) {
            guard isEnabled, manager.phase != .finished else { return }
            await manager.requestOnLaunch()
            onFinish?(manager)
        }
    }
}
