---
name: adskit-ads
description: Integrate AdMob ads into an iOS (SwiftUI) app through the in-house AdsKit Swift package — Google UMP consent (GDPR / US states), App Tracking Transparency, and App Open ads — and extend AdsKit with new formats (banner, interstitial, rewarded, native) via pull request. Run only when the user invokes /adskit-ads.
disable-model-invocation: true
---

# AdsKit ads integration

This skill runs only because the user invoked it; it changes their project (copies a package,
edits the `.xcodeproj`, adds code). Work on the project the user pointed at — if it's unclear which
app or target, ask before touching anything.

AdsKit is a small Swift package (iOS 15+, Swift 5.9) that wraps Google Mobile Ads + UMP so apps get
consent, ATT and ads in the order Google and Apple require. A copy of the package lives in
`assets/AdsKit/` next to this file, and `scripts/install_adskit.sh` copies it into an app project
and links it to the app target:

- `Sources/AdsKit/AdsConsentManager.swift` — UMP then ATT, once per process.
- `Sources/AdsKit/AdsConsentGate.swift` — SwiftUI splash shown while that flow runs.
- `Sources/AdsKit/AppOpenAdManager.swift` — App Open ad: load, expiry, cooldown, background rule.
- `INTEGRATION.md` — full Vietnamese integration guide (API tables, troubleshooting, release
  checklist). Read the sections you need instead of re-deriving behaviour from source.

The user and docs are often Vietnamese; answer in the user's language.

Decide which job this is:
- **Integrate** AdsKit into an app → follow "Integration workflow" below.
- **Extend or change** AdsKit (new format, bug fix, new option) → read `references/extending.md`.
  AdsKit is shared across apps, so every change goes to two places with identical contents:
  the app's `Packages/AdsKit` (usable now) and this skill's `assets/AdsKit/` in the owner's repo
  `padit69/ads_th_skill`, sent as a pull request (so future installs get it). This
  applies mid-integration too — if the app needs something AdsKit can't do, change AdsKit this
  way rather than working around it in the app.
- **Debug** (no form, no ATT, no ad, crash) → the "Lỗi thường gặp" table in
  `assets/AdsKit/INTEGRATION.md` §12, then verify against the source.

## Integration workflow

Look at the target project first: is it SwiftUI `App` or UIKit `AppDelegate/SceneDelegate`? Is
AdsKit already there (search for `import AdsKit`, a `Packages/AdsKit` folder, or a remote package
reference)? Where does the app keep config (an `AppConfig.plist`, xcconfig, remote config)? What
gates already exist — Pro/subscription, onboarding, passcode lock, a sheet router, a remote "ads
enabled" switch? Those gates become `canPresent`, so find them before writing code.

### 1. Copy the package into the project and link it

Do this yourself; don't hand the user Xcode click-steps. Run the bundled installer:

```sh
<skill dir>/scripts/install_adskit.sh <path/to/App.xcodeproj> [--target AppTarget]
```

It copies `assets/AdsKit/` to `Packages/AdsKit` beside the `.xcodeproj`, then (via
`scripts/link_local_package.rb`, Ruby `xcodeproj` gem) adds the local package reference, the
`AdsKit` product dependency and the Frameworks build file to the app target — the same entries
Xcode's "Add Local…" writes. It is idempotent, and it refuses to overwrite an existing
`Packages/AdsKit` that differs from the bundled copy (the user may have edited it); show them the
diff it prints and only pass `--force` if they agree. With several app targets it asks for
`--target`. If the gem is missing: `gem install xcodeproj`.

Other project setups:
- **XcodeGen** (`project.yml` present — the script warns): the `.xcodeproj` is generated, so edit
  `project.yml` instead — `packages: { AdsKit: { path: Packages/AdsKit } }` and
  `dependencies: [{ package: AdsKit }]` on the app target — copy the folder with the script's
  `--dest` or `rsync`, then run `xcodegen generate`.
- **Tuist / pure SPM app**: add `.package(path: "Packages/AdsKit")` and the `AdsKit` product in the
  manifest.

Then confirm it resolves: `xcodebuild -resolvePackageDependencies -project <App.xcodeproj>`.

The app must not import `GoogleMobileAds` or `UserMessagingPlatform` directly — everything goes
through AdsKit, so ad SDK types and versioning stay in one place. If the app already links those
SDKs or another ads/monetization SDK, say so before adding AdsKit: two layers starting the Mobile
Ads SDK or showing their own consent form will fight each other. Ask which one should own ads.

### 2. Info.plist

| Key | Why |
|---|---|
| `GADApplicationIdentifier` (`ca-app-pub-…~…`) | SDK crashes without it; AdsKit skips ads when empty |
| `NSUserTrackingUsageDescription` | Calling ATT without it crashes; localize it |
| `SKAdNetworkItems` | Attribution; take the current list from Google's AdMob docs |

Projects with generated Info.plists can set `INFOPLIST_KEY_NSUserTrackingUsageDescription` as a
build setting. Ask the user for real IDs; never invent production IDs.

### 3. Configure at launch

Create an `AdsSetup.configure()` called from the `App` `init()` (before any UI). Use
`AppOpenAdManager.Configuration.testAdUnitID` in DEBUG and the real unit in Release; an empty unit
ID means "no ads", which is a safe default when the ID is missing. See INTEGRATION.md §5 for the
template. Defaults: `cooldown: 0`, `minimumBackgroundDuration: 5`, `showsOnColdStart: false`.

### 4. Splash gate (UMP + ATT)

Wrap the root view in `AdsConsentGate { Splash } content: { Root }`. Things to get right:
- `isEnabled:` — pass `false` while something must come first (e.g. `!security.isLocked`); the
  splash stays until it flips to true.
- `onFinish:` — runs once after UMP + ATT; update analytics consent here (INTEGRATION.md §9).
- Reuse the app's existing splash/launch view if there is one.
- UIKit apps: call `await AdsConsentManager.shared.requestOnLaunch()` from the first screen and
  hold your own splash until it returns.

### 5. App Open ads

Two pieces, both in the root view (INTEGRATION.md §7 has the full code):
1. Call `AppOpenAdManager.shared.appDidOpen()` in `.task` on launch **and** on `scenePhase`
   `.active` only after a real `.background` (track `wasInBackground`). `.inactive → .active`
   happens for share sheets, pickers and purchase dialogs — counting those would show ads in
   the middle of a user action.
2. A `runAds()` that returns early for Pro, then `await ads.start()` and
   `await ads.showIfEligible(canPresent: …)` with every app-level gate ANDed together
   (remote switch, onboarding done, no sheet presented, not locked).

AdsKit owns the timing rules (cold-start skip, 5 s background minimum, cooldown, 4 h expiry,
5 s open window, preload after show). Don't re-implement them in the app; adjust `Configuration`
instead. Remote cooldown can be written to `ads.configuration?.cooldown` before `start()`.

### 6. Privacy Choices in Settings

Google requires an entry point in regulated regions. Add a row shown only when
`AdsConsentManager.shared.isPrivacyOptionsRequired` that calls
`try? await consent.presentPrivacyOptions()` (observe the manager with `@ObservedObject`).

### 7. Debug hooks and testing

Wire DEBUG-only launch arguments so the user can test the GDPR form on the simulator, e.g.
`-adsDebugEEA` → `configuration.debugGeography = .eea`, `-adsResetConsent` → `resetConsent()`.
Keep them inside `#if DEBUG`. Test steps are in INTEGRATION.md §10; remind the user never to test
with real ad units (invalid clicks can get the AdMob account banned).

### 8. Finish

Build if you can (`xcodebuild -scheme … -destination 'generic/platform=iOS Simulator' build`).
Then give the user:
- what you changed, file by file;
- what only they can do: AdMob console (publish GDPR and US-states messages — without a published
  message the form never appears; create the App Open unit), real IDs, App Store Connect App
  Privacy answers;
- the release checklist from INTEGRATION.md §13, ticking what is already done.

## Pitfalls worth checking every time

- ATT requested before the app is active, or right after the UMP form, is silently dropped —
  AdsKit already waits and retries; don't add an extra ATT call elsewhere in the app.
- Starting `MobileAds` before consent finishes violates UMP; only `AppOpenAdManager.start()` /
  other AdsKit managers should start the SDK, and they wait for consent.
- Debug geography, test device IDs and `resetConsent()` must never ship in Release.
- If the IDFA explainer is enabled in AdMob, UMP asks ATT itself; AdsKit sees the answer and skips.
