# Skill `adskit-ads`

Skill cho Claude Code: tích hợp quảng cáo AdMob vào app iOS qua package **AdsKit** (consent UMP,
ATT, App Open), và viết thêm loại quảng cáo mới (banner, interstitial, rewarded) vào AdsKit.

Khi được gọi, Claude sẽ:
1. Copy AdsKit vào project (`Packages/AdsKit`) và nối nó vào app target trong `.xcodeproj`.
2. Thêm key Info.plist, `AdsSetup`, splash `AdsConsentGate`, App Open theo `scenePhase`,
   mục "Privacy Choices" trong Settings, cờ debug.
3. Build thử, rồi liệt kê những việc bạn phải tự làm (AdMob console, ID thật, App Privacy).

## Cài đặt

**Cho mọi project trên máy** (khuyên dùng):

```sh
git clone https://github.com/padit69/ads_th_skill.git
cd ads_th_skill
mkdir -p ~/.claude/skills
ln -s "$(pwd)/adskit-ads" ~/.claude/skills/adskit-ads
```

Dùng symlink thì sửa skill ở đây là có hiệu lực ngay. Muốn bản độc lập thì dùng
`cp -R adskit-ads ~/.claude/skills/` thay cho `ln -s`.

**Chỉ cho một project:** copy vào `<project>/.claude/skills/adskit-ads` (có thể commit vào git
để cả team dùng).

Mở phiên Claude Code mới để skill được nạp.

**Skill chỉ chạy khi bạn gọi** bằng `/adskit-ads` (frontmatter có `disable-model-invocation: true`).
Claude không tự dùng skill hay tự sửa project chỉ vì bạn nhắc tới quảng cáo.

### Yêu cầu

- macOS có Xcode 15+.
- Ruby gem `xcodeproj` (để sửa `.xcodeproj`): `gem install xcodeproj`.

## Cách dùng

Mở Claude Code trong thư mục app, gõ `/adskit-ads` kèm yêu cầu, chẳng hạn:

- `/adskit-ads tích hợp ads cho app này, unit App Open là ca-app-pub-xxx/yyy`
- `/adskit-ads thêm interstitial vào AdsKit, hiện sau mỗi 3 lần export`
- `/adskit-ads sao form GDPR không hiện?`

Có thể chạy riêng bước copy + nối package:

```sh
~/.claude/skills/adskit-ads/scripts/install_adskit.sh path/to/App.xcodeproj [--target App]
```

## Cấu trúc

```
adskit-ads/
├── SKILL.md                     # hướng dẫn cho Claude
├── references/extending.md      # quy ước khi viết thêm loại quảng cáo
├── scripts/
│   ├── install_adskit.sh        # copy AdsKit vào project + nối vào target
│   └── link_local_package.rb    # thêm local Swift package vào .xcodeproj
└── assets/AdsKit/               # bản AdsKit đi kèm skill (+ INTEGRATION.md)
```

## Sửa / mở rộng AdsKit

Repo gốc: <https://github.com/padit69/ads_th_skill>. Bản AdsKit gốc duy nhất là
`adskit-ads/assets/AdsKit/`.

Khi cần sửa SDK (thêm banner, interstitial, sửa lỗi…), Claude sửa ở **cả 2 chỗ**, nội dung giống hệt:

1. `Packages/AdsKit` trong app đang làm — app dùng được ngay.
2. `adskit-ads/assets/AdsKit/` trong repo → mở **pull request** cho owner review (Claude không tự
   merge). Merge xong thì các app cài sau nhận bản mới.

Build cả package lẫn app trước khi mở PR.
