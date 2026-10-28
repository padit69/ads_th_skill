# AdsKit

For now AdsKit covers three things only:
- **Consent** — Google UMP (GDPR / US state privacy messages), gathered on the launch splash.
- **ATT** — Apple's App Tracking Transparency prompt, right after UMP.
- **App Open ads** — AdMob App Open, shown when the user opens the app. No banners, interstitials or
  rewarded ads yet.

## Launch flow (splash)

```swift
AdsConsentGate {
    SplashView()            // shown while consent + ATT are gathered
} content: {
    RootView()
}
```

or drive it yourself:

```swift
await AdsConsentManager.shared.requestOnLaunch()
if AdsConsentManager.shared.canRequestAds { /* start the Mobile Ads SDK, load ads */ }
```

## App Open ads

```swift
let ads = AppOpenAdManager.shared
ads.configuration = .init(adUnitID: "<unit id>", cooldown: 10 * 60,
                          minimumBackgroundDuration: 5)   // seconds in background before an ad may show
await ads.start()                      // waits for consent; no-op when ads aren't allowed

// every time the app opens (launch, return from background):
ads.appDidOpen()
await ads.showIfEligible(canPresent: !isPro && !isLocked && noSheetIsUp)
```

The app keeps its own rules (Pro, onboarding, lock screen, remote switch) and passes them as
`canPresent`. AdsKit handles the 4-hour ad expiry, the cooldown, preloading the next ad, and never
shows an ad that finished loading more than `openWindow` seconds after the open.

Order on every launch:
1. `requestConsentInfoUpdate` (bounded by `configuration.consentInfoTimeout`, so a slow or offline
   network never holds the splash; the previous consent state is used instead).
2. The UMP form, only when Google says it's required (first launch in a regulated region, or
   consent expired).
3. ATT, only while its status is `.notDetermined`, and only once the app is active (iOS ignores
   the request otherwise). Skipped when `configuration.requestsTrackingAuthorization` is false.

The flow runs once per process; later calls await the same result.

## Settings

When `isPrivacyOptionsRequired` is true, show a "Privacy choices" row that calls
`presentPrivacyOptions()` — Google requires this entry point in regulated regions.

## App requirements

- `GADApplicationIdentifier` in Info.plist (UMP reads the app ID from it).
- `NSUserTrackingUsageDescription` in Info.plist (requesting ATT without it crashes).
- Configure the GDPR / US states messages in the AdMob console (Privacy & messaging).

## Testing

```swift
AdsConsentManager.shared.configuration = .init(debugGeography: .eea,
                                               testDeviceIdentifiers: ["<hashed id from the console log>"])
AdsConsentManager.shared.resetConsent()   // DEBUG only: forget the stored choice
```

Hướng dẫn tích hợp đầy đủ (tiếng Việt): [INTEGRATION.md](INTEGRATION.md)
