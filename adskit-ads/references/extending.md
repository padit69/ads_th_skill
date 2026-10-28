# Extending or changing AdsKit

AdsKit is shared by several apps. Its source of truth is `adskit-ads/assets/AdsKit/` in the
GitHub repo **`padit69/ads_th_skill`** (the repo holds this skill; the package lives inside it).

Every AdsKit change lands in **both places**, with identical package contents:

| Where | Why |
|---|---|
| The app's `Packages/AdsKit` (the project being worked on) | The app uses the change right away, without waiting for the PR |
| The skill's `assets/AdsKit/` in the repo → pull request to the owner | Source of truth; future installs into other apps get it once the owner merges |

When you finish, `diff -rq -x .build -x .swiftpm -x .DS_Store` between the two must be empty.

## Workflow: change → sync → build → pull request

1. **Get the repo.** Use a local checkout if there is one (look for a folder whose
   `git remote -v` points at `padit69/ads_th_skill` — the installed skill is often a symlink into
   one: `readlink ~/.claude/skills/adskit-ads`); otherwise `gh repo clone padit69/ads_th_skill`
   into a scratch/work directory. Run `git pull` on the default branch first. If
   `gh repo view padit69/ads_th_skill --json viewerPermission` shows no write access,
   `gh repo fork --clone` and open the PR from the fork.
2. **Branch:** `git switch -c adskit/<short-change-name>` (e.g. `adskit/interstitial`).
3. **Edit `adskit-ads/assets/AdsKit/`** following the conventions below. If the change was
   started inside an app's `Packages/AdsKit`, bring it into the skill's copy first. If the app's
   copy already differs from the skill's for other reasons, show the user the diff and ask before
   overwriting either side. Update `adskit-ads/SKILL.md` / this file if the integration steps
   changed.
4. **Sync the app's copy:**
   `rsync -a --delete --exclude .build --exclude .swiftpm --exclude .DS_Store adskit-ads/assets/AdsKit/ <app>/Packages/AdsKit/`
   (or `install_adskit.sh <App.xcodeproj> --force` from the branch checkout), then update the
   app's code that uses the changed API. If the installed skill (`~/.claude/skills/adskit-ads`)
   is a separate copy rather than a symlink to this checkout, sync it as well.
5. **Build both** the package (see "After adding a format") and the app, and fix warnings you
   introduced.
6. **Commit and open the PR:**
   ```sh
   git add adskit-ads
   git commit -m "AdsKit: <what changed>"
   git push -u origin HEAD
   gh pr create --repo padit69/ads_th_skill --fill-first --body "<summary>"
   ```
   PR body: what changed and why, public API added/changed (with a usage snippet), behaviour
   changes for existing apps (anything that alters App Open/consent timing is a breaking change —
   call it out), how it was built/tested, and the docs updated. Follow the session's commit/PR
   attribution rules.
7. **Report** the PR URL and confirm the two copies match. Don't merge the PR yourself — the
   owner reviews and merges. The app's own repo gets its `Packages/AdsKit` change in the app's
   normal commit, not in this PR. If the owner asks for changes on the PR, apply them to both
   copies again.

Ask before pushing or opening the PR if the user hasn't asked for one in this conversation —
it publishes the code.

## Writing the change

Read the existing sources in `assets/AdsKit/Sources/AdsKit/` first. A new format should look like
`AppOpenAdManager` so apps learn one pattern.

## Conventions to keep

- **One manager per format**, `@MainActor public final class XxxAdManager: NSObject, ObservableObject`
  with `public static let shared`, `init(consent: AdsConsentManager = .shared)`.
- **`Configuration` struct** (`Sendable`), `adUnitID` first, sensible defaults, and a
  `public static let testAdUnitID`. `configuration == nil` or an empty ID means "no ads".
- **Consent first.** `start()` awaits `consent.waitUntilFinished()`, checks
  `consent.phase == .finished && consent.canRequestAds` and `AppOpenAdManager.hasAppID`, and only
  then starts the SDK (`MobileAds.shared.start()` is safe to call from several managers) and
  preloads. Every load re-checks `consent.canRequestAds`.
- **The app owns policy, AdsKit owns mechanics.** Show APIs take `canPresent: Bool`
  (Pro, onboarding, sheet up, locked, remote switch). Frequency caps, expiry, cooldown, preload
  after dismiss and "don't show a late ad" live in the manager and its `Configuration`.
- **Delegates:** conform with `nonisolated` methods that hop to `Task { @MainActor in … }`, as
  `AppOpenAdManager` does with `FullScreenContentDelegate`.
- **No SDK types in the public API.** Apps don't import `GoogleMobileAds`; expose AdsKit types
  (e.g. a reward as `AdsReward(amount: Int, type: String)`, a banner as a SwiftUI view).
- Present full-screen ads from the top-most presented view controller (reuse the
  `topViewController()` approach; move it to a shared internal helper rather than copying it).
- Comments: short header comment stating the rules, doc comments on public API — match the files.

## Format notes

| Format | Google test unit (iOS) | Notes |
|---|---|---|
| Banner (adaptive) | `ca-app-pub-3940256099942544/2435281174` | SwiftUI `AdsBannerView` wrapping `BannerView` in `UIViewRepresentable`; size with the anchored adaptive banner size for the container width; render nothing (zero height) until consent allows ads and an ad loaded |
| Interstitial | `ca-app-pub-3940256099942544/4411468910` | Show at natural breaks only; `cooldown` and optional "every N actions" in Configuration; preload after dismiss; ad expires after 1 h |
| Rewarded | `ca-app-pub-3940256099942544/1712485313` | `show(canPresent:) async -> AdsReward?`; grant only in the earn-reward handler, never on dismiss alone; expose `isAdReady` so the UI can disable the button |
| Rewarded interstitial | `ca-app-pub-3940256099942544/6978759866` | Needs an intro screen with opt-out before showing (Google policy) |
| Native | `ca-app-pub-3940256099942544/3986624511` | Usually app-specific layout; consider leaving the view to the app and only managing loading in AdsKit |

Google Mobile Ads 12+ uses Swift-native names (`BannerView`, `InterstitialAd.load(with:request:)`,
`RewardedAd`, `Request`, `FullScreenContentDelegate`). The package pins `from: "13.0.0"`; if a call
doesn't compile, check the resolved SDK headers in the SPM checkout rather than guessing old `GAD`
names.

## After adding a format

1. Build the package for iOS:
   `xcodebuild -scheme AdsKit -destination 'generic/platform=iOS Simulator' build` in the package dir.
2. Update `README.md` (short English usage) and `INTEGRATION.md` (Vietnamese guide: overview table,
   a new section with code, API table in §11, troubleshooting rows in §12, checklist items in §13).
   Remove "Banner, interstitial, rewarded chưa có" for formats that now exist.
3. Integrate it in the app the same way as App Open: config in `AdsSetup`, `start()` after consent,
   `canPresent` from the app's gates.
