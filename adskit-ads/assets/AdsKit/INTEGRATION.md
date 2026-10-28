# AdsKit — Tài liệu tích hợp

AdsKit gói 3 việc liên quan tới quảng cáo, chạy theo đúng thứ tự Google và Apple yêu cầu:

| Thành phần | Việc | Khi nào chạy |
|---|---|---|
| `AdsConsentManager` | Consent Google UMP (GDPR, luật bang Mỹ) | Splash, mỗi lần mở app |
| `AdsConsentManager` | Hỏi ATT (App Tracking Transparency) | Ngay sau UMP, chỉ khi chưa hỏi bao giờ |
| `AdsConsentGate` | Hiện splash trong lúc chạy 2 bước trên | Khởi động app |
| `AppOpenAdManager` | Load và hiện quảng cáo App Open | Quay lại từ background (≥ 5 s); lần mở đầu chỉ khi bật `showsOnColdStart` |

Hiện tại **chỉ có App Open**. Banner, interstitial, rewarded chưa có.

---

## 1. Yêu cầu

- iOS 15 trở lên, Swift 5.9 (Xcode 15+).
- Phụ thuộc (tự kéo về khi thêm package):
  - `swift-package-manager-google-mobile-ads` ≥ 13.0.0
  - `swift-package-manager-google-user-messaging-platform` ≥ 3.0.0
- App **không** cần thêm trực tiếp `GoogleMobileAds` hay `GoogleUserMessagingPlatform`, và cũng
  không nên import 2 module này; mọi thứ đi qua AdsKit.

## 2. Thêm package vào project

**Package local (như FileX):**
1. Xcode → File → Add Package Dependencies… → Add Local… → chọn thư mục `Packages/AdsKit`.
2. Target app → General → Frameworks, Libraries → thêm `AdsKit`.

**Dùng cho app khác:** đẩy thư mục `AdsKit` lên một git repo riêng, rồi thêm bằng URL repo đó
(Add Package Dependencies… → nhập URL, chọn tag).

## 3. Info.plist

| Key | Giá trị | Ghi chú |
|---|---|---|
| `GADApplicationIdentifier` | `ca-app-pub-xxxxxxxx~yyyyyyyy` | Bắt buộc. Thiếu là SDK crash; AdsKit tự tắt quảng cáo nếu key trống. |
| `NSUserTrackingUsageDescription` | Câu giải thích cho popup ATT | Bắt buộc nếu hỏi ATT. Thiếu là app crash khi gọi ATT. Nên dịch trong `InfoPlist.xcstrings`. |
| `SKAdNetworkItems` | Danh sách ID SKAdNetwork của Google và đối tác | Lấy danh sách mới nhất từ tài liệu AdMob. |

FileX đặt `NSUserTrackingUsageDescription` trong build setting
`INFOPLIST_KEY_NSUserTrackingUsageDescription`; các key còn lại nằm trong `FileX-Info.plist`.

## 4. Cấu hình trên AdMob console

1. **Privacy & messaging → GDPR:** tạo message cho app và publish. Không có message thì form
   consent không bao giờ hiện, kể cả ở châu Âu.
2. **Privacy & messaging → US states:** tạo message nếu phát hành ở Mỹ.
3. (Tuỳ chọn) **IDFA explainer:** một màn giải thích hiện trước popup ATT. Nếu bật, UMP tự hỏi
   ATT; AdsKit thấy ATT đã có câu trả lời thì bỏ qua bước hỏi của mình.
4. Tạo **ad unit App Open** và lấy ID dạng `ca-app-pub-xxx/yyy`.

## 5. Cấu hình lúc khởi động

Gọi một lần, sớm nhất có thể (trong `init()` của `App`), trước khi hiện giao diện:

```swift
import AdsKit

enum AdsSetup {
    static func configure() {
        #if DEBUG
        let adUnitID = AppOpenAdManager.Configuration.testAdUnitID   // unit test của Google
        #else
        let adUnitID = AppConfig.adMobAppOpenUnitID ?? ""            // trống = không có quảng cáo
        #endif

        // Tuỳ chọn cho consent (đều có giá trị mặc định):
        // AdsConsentManager.shared.configuration = .init(
        //     tagForUnderAgeOfConsent: false,
        //     requestsTrackingAuthorization: true,
        //     consentInfoTimeout: 8)

        AppOpenAdManager.shared.configuration = .init(
            adUnitID: adUnitID,
            cooldown: 0,                     // giây tối thiểu giữa 2 lần hiện quảng cáo
            minimumBackgroundDuration: 5,    // phải ở background ≥ 5 s thì quay lại mới hiện
            showsOnColdStart: false)         // lần mở app đầu tiên không hiện quảng cáo
    }
}

@main
struct MyApp: App {
    init() { AdsSetup.configure() }
    var body: some Scene { WindowGroup { RootView() } }
}
```

Bản FileX nằm ở `FileX/App/AdsSetup.swift`.

## 6. Splash: consent + ATT

Bọc giao diện gốc bằng `AdsConsentGate`. Splash phủ lên app cho tới khi UMP và ATT xong; form
UMP và popup ATT hiện đè lên splash.

```swift
AdsConsentGate(
    isEnabled: !security.isLocked,          // false = chưa chạy, splash vẫn đứng (vd. đang khoá)
    onFinish: { consent in
        // Chạy 1 lần sau khi xong cả UMP và ATT.
        AnalyticsService.updateAdConsent(granted: consent.canRequestAds && consent.isTrackingAuthorized)
    }
) {
    SplashView()                            // giao diện splash của app
} content: {
    MainTabView()
}
```

Không muốn dùng `AdsConsentGate` thì tự gọi:

```swift
await AdsConsentManager.shared.requestOnLaunch()
```

Luồng chạy:

1. Gọi Google để cập nhật trạng thái consent, chờ tối đa `consentInfoTimeout` (mặc định 8 s).
   Quá thời gian hoặc lỗi mạng thì dùng lựa chọn đã lưu lần trước; splash không bị treo.
2. Chỉ hiện form UMP khi Google bắt buộc (lần đầu ở vùng có luật, hoặc consent đã hết hạn).
3. Hỏi ATT khi trạng thái còn `.notDetermined`. AdsKit chờ app active rồi đợi 0,5 s cho form UMP
   đóng hẳn (iOS bỏ qua yêu cầu ATT nếu gọi quá sớm), và thử lại 1 lần nếu iOS chưa hiện popup.
4. `phase` chuyển sang `.finished`, splash mờ dần.

Luồng chỉ chạy **1 lần mỗi lần mở app**; gọi thêm chỉ chờ kết quả của lần đang chạy.

**Thứ tự với màn khoá / onboarding (cách FileX làm):** có passcode thì màn khoá hiện trước, mở khoá
xong mới hỏi consent (`isEnabled: !security.isLocked`). Onboarding nằm dưới splash, nên consent
được hỏi trước onboarding.

## 7. Quảng cáo App Open

### 7.1 Báo mỗi lần app được mở

```swift
@Environment(\.scenePhase) private var scenePhase
@State private var wasInBackground = false

.task {
    AppOpenAdManager.shared.appDidOpen()          // mở app lần đầu
    await runAds()
}
.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .background:
        wasInBackground = true
    case .active where wasInBackground:           // chỉ tính khi quay lại từ background thật sự,
        wasInBackground = false                   // không tính share sheet / picker / mua hàng
        AppOpenAdManager.shared.appDidOpen()
        Task { await runAds() }
    default:
        break
    }
}
```

AdsKit tự ghi lại lúc app xuống background (`didEnterBackgroundNotification`). Nếu quay lại sau
chưa đủ `minimumBackgroundDuration`, `appDidOpen()` bỏ qua lần mở đó. Lần mở app đầu tiên (cold
start) cũng bị bỏ qua, trừ khi `showsOnColdStart = true`. Vẫn nên gọi `appDidOpen()` lúc khởi động
để AdsKit phân biệt được cold start.

### 7.2 Start và hiện quảng cáo theo luật của app

AdsKit không biết user có Pro không, có đang onboarding không… nên app truyền các điều kiện đó
vào `canPresent`:

```swift
private func runAds() async {
    guard !entitlements.isProActive else { return }               // Pro không có quảng cáo
    let ads = AppOpenAdManager.shared
    ads.configuration?.cooldown = TimeInterval(remoteConfig.appOpenAdCooldownMinutes * 60)
    await ads.start()       // chờ consent xong; không làm gì nếu consent không cho phép quảng cáo
    await ads.showIfEligible(canPresent: remoteConfig.appOpenAdEnabled
                             && settings.onboardingCompleted
                             && router.sheet == nil
                             && !security.isLocked)
}
```

`showIfEligible` chỉ hiện quảng cáo khi tất cả điều kiện sau đều đúng:

- Có một lần mở app đang chờ (`appDidOpen()`) mà chưa dùng.
- `canPresent == true`, SDK đã start, chưa có quảng cáo nào đang hiện.
- Đã qua `cooldown` kể từ lần hiện trước.
- Đã có quảng cáo còn hạn (dưới 4 giờ), hoặc quảng cáo load xong trong `openWindow` (5 s) kể từ
  lúc mở app. Load chậm hơn thì bỏ qua lần mở này, để quảng cáo không bật lên giữa chừng.

Hiện xong (hoặc hiện lỗi), AdsKit gọi `onDismiss` rồi load sẵn quảng cáo tiếp theo.

## 8. Settings: Privacy Choices

Ở vùng có luật, Google yêu cầu app có chỗ cho user đổi lựa chọn consent:

```swift
@ObservedObject private var consent = AdsConsentManager.shared

if consent.isPrivacyOptionsRequired {
    Button("Privacy Choices") {
        Task { try? await consent.presentPrivacyOptions() }
    }
}
```

## 9. Firebase / Google consent mode (tuỳ chọn)

Nếu dùng Firebase Analytics, đặt consent mặc định là denied lúc khởi động, rồi cập nhật trong
`onFinish` của `AdsConsentGate`:

```swift
Analytics.setConsent([
    .analyticsStorage: .granted,
    .adStorage: granted ? .granted : .denied,
    .adUserData: granted ? .granted : .denied,
    .adPersonalization: granted ? .granted : .denied,
])
```

với `granted = consent.canRequestAds && consent.isTrackingAuthorized`.

## 10. Test

| Mục đích | Cách làm |
|---|---|
| Xem form GDPR trên simulator | `AdsConsentManager.shared.configuration.debugGeography = .eea` (FileX: tham số `-adsDebugEEA`) |
| Xem form trên máy thật | Thêm `testDeviceIdentifiers: ["<ID>"]`; ID được UMP in ra console lần chạy đầu |
| Cho form hiện lại | `AdsConsentManager.shared.resetConsent()` — chỉ dùng ở DEBUG (FileX: `-adsResetConsent`) |
| Hỏi lại ATT | Xoá app, hoặc `xcrun simctl privacy <UDID> reset all <bundle id>` |
| Quảng cáo test | `AppOpenAdManager.Configuration.testAdUnitID` (FileX dùng sẵn ở DEBUG) |
| Thử luật background 5 s | Mở app (không có quảng cáo) → về Home < 5 s → quay lại: không có quảng cáo. Về Home ≥ 5 s → quay lại: có quảng cáo |

Ví dụ chạy FileX trên simulator với form GDPR:

```sh
xcrun simctl launch <UDID> com.pnt.file.ezmanager -adsDebugEEA -adsResetConsent
```

Không dùng ad unit thật khi test: Google có thể khoá tài khoản vì click không hợp lệ.

## 11. Tra cứu API

### `AdsConsentManager` (`@MainActor`, `ObservableObject`, `.shared`)

| Thành viên | Mô tả |
|---|---|
| `configuration: AdsConsentConfiguration` | `debugGeography`, `testDeviceIdentifiers`, `tagForUnderAgeOfConsent`, `requestsTrackingAuthorization` (mặc định `true`), `consentInfoTimeout` (mặc định 8 s) |
| `phase: Phase` | `.idle` → `.gathering` → `.finished` |
| `canRequestAds: Bool` | UMP cho phép request quảng cáo |
| `isPrivacyOptionsRequired: Bool` | Phải hiện mục "Privacy Choices" |
| `trackingStatus`, `isTrackingAuthorized` | Trạng thái ATT |
| `lastError: Error?` | Lỗi UMP gần nhất (luồng vẫn kết thúc bình thường) |
| `requestOnLaunch() async` | UMP rồi ATT, 1 lần mỗi lần mở app |
| `waitUntilFinished() async` | Chờ luồng khởi động xong |
| `gatherConsent() async` | Chỉ chạy bước UMP |
| `requestTrackingAuthorizationIfNeeded() async` | Chỉ hỏi ATT |
| `presentPrivacyOptions() async throws` | Mở lại form lựa chọn |
| `resetConsent()` | Xoá consent đã lưu (chỉ dùng DEBUG) |

### `AdsConsentGate<Splash, Content>` (SwiftUI)

`init(manager: = .shared, isEnabled: = true, onFinish: = nil, splash:, content:)`

### `AppOpenAdManager` (`@MainActor`, `ObservableObject`, `.shared`)

| Thành viên | Mô tả |
|---|---|
| `configuration: Configuration?` | `adUnitID`, `cooldown` (0), `adLifetime` (4 h), `openWindow` (5 s), `minimumBackgroundDuration` (5 s), `showsOnColdStart` (`false`). `nil` hoặc `adUnitID` trống = không có quảng cáo |
| `Configuration.testAdUnitID` | Unit App Open test của Google |
| `start() async` | Chờ consent, start Mobile Ads SDK, load sẵn quảng cáo. Gọi nhiều lần vẫn an toàn |
| `appDidOpen()` | Báo app vừa được mở |
| `showIfEligible(canPresent:) async -> Bool` | Hiện quảng cáo nếu đủ điều kiện; trả về `true` khi đã hiện |
| `isAdReady`, `isShowing`, `isStarted` | Trạng thái |
| `onDismiss` | Callback sau khi quảng cáo đóng |
| `hasAppID` (static) | Info.plist có `GADApplicationIdentifier` thật không |

## 12. Lỗi thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| Form consent không bao giờ hiện | Chưa publish message GDPR trên AdMob; hoặc thiết bị không ở vùng có luật — dùng `debugGeography = .eea` để test |
| Popup ATT không hiện | Đã hỏi rồi (iOS chỉ hỏi 1 lần); hoặc Settings → Privacy → Tracking đang tắt "Allow Apps to Request to Track" |
| App crash khi tới bước ATT | Thiếu `NSUserTrackingUsageDescription` |
| App crash khi start SDK | Thiếu hoặc sai `GADApplicationIdentifier` |
| Không có quảng cáo dù đã consent | `adUnitID` trống ở Release; user là Pro; `canPresent` false; hoặc quảng cáo load quá `openWindow` |
| Mới mở app chưa có quảng cáo | Đúng thiết kế: cold start không hiện, trừ khi `showsOnColdStart = true` |
| Quay lại app không có quảng cáo | Chưa ở background đủ `minimumBackgroundDuration`, hoặc còn trong `cooldown` |
| Splash đứng lâu | Đang chờ user bấm trên form UMP hoặc popup ATT; khi offline thì tối đa `consentInfoTimeout` |

## 13. Checklist trước khi phát hành

- [ ] `GADApplicationIdentifier` thật trong Info.plist.
- [ ] Ad unit App Open thật cho bản Release (FileX: `AdMobAppOpenUnitID` trong `AppConfig.plist`).
- [ ] Message GDPR (và US states nếu cần) đã publish trên AdMob.
- [ ] `NSUserTrackingUsageDescription` có bản dịch cho mọi ngôn ngữ của app.
- [ ] `SKAdNetworkItems` đã cập nhật.
- [ ] Settings có mục "Privacy Choices" khi `isPrivacyOptionsRequired`.
- [ ] Không còn `debugGeography`, `testDeviceIdentifiers` hay `resetConsent()` trong bản Release.
- [ ] App Store Connect: phần App Privacy khai báo dữ liệu dùng cho quảng cáo và tracking.
