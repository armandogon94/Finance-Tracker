# RELEASE — Finance Tracker iOS

The runbook for shipping the iOS app to TestFlight and (eventually) the
App Store. Written at the end of slice 10. Updated whenever the
release pipeline changes.

---

## Pre-flight checklist (every upload)

Before you archive:

- [ ] Local backend is up: `curl -s http://localhost:8040/health`
- [ ] Full test suite green: `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,id=B6DAB738-9430-4692-8580-A99CBC4FC8E0' -configuration Debug test`
- [ ] Bumped `CURRENT_PROJECT_VERSION` in `ios/project.yml` (Apple rejects re-uploads at the same build number — increment by 1 per upload, no exceptions)
- [ ] If a feature shipped: bumped `MARKETING_VERSION` (e.g. `1.0.0` → `1.1.0` for new features, `1.0.0` → `1.0.1` for bug fixes)
- [ ] `xcodegen generate` to sync project.pbxproj
- [ ] `DEVELOPMENT_TEAM` is set in `ios/project.yml` `settings.base` (look it up at https://developer.apple.com/account/#/membership/ — the 10-character "Team ID" string). Without this, archive builds in the *real* signed pipeline will fail on code-sign.

## TestFlight upload — first time

1. **Apple Developer Program enrollment** — $99/year. https://developer.apple.com/programs/. Takes 24–48 hrs to activate the first time. Required before any of this works.
2. **App Store Connect record** — at https://appstoreconnect.apple.com/, create a new app:
   - Bundle ID: `com.armandointeligencia.FinanceTracker` (must match `PRODUCT_BUNDLE_IDENTIFIER` in project.yml exactly — it's set globally on first creation and you cannot rename it later)
   - SKU: anything unique, e.g. `finance-tracker-ios`
   - Primary language: English (U.S.)
3. **Archive in Xcode** (one-time GUI step for the first signed upload):
   - Open `ios/FinanceTracker.xcodeproj` in Xcode
   - Top-bar destination dropdown → "Any iOS Device (arm64)"
   - Product menu → Archive
   - When done, the Organizer opens. Click "Distribute App" → "App Store Connect" → "Upload" → follow prompts. Xcode handles signing automatically against your Apple ID.
4. **Wait for processing** (5–20 min). You'll get an email when the build is ready in TestFlight.
5. **Add yourself as an internal tester** in App Store Connect → TestFlight → Internal Testing → add your Apple ID.
6. **Install via TestFlight app** on your iPhone 17 Pro Max — your build now appears in the TestFlight app's "Available Builds" list.

## TestFlight upload — subsequent (CLI-friendly)

Once the first upload has gone through Xcode GUI, future uploads can be done from the terminal:

```bash
cd ios
xcodegen generate
xcodebuild -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  archive \
  -archivePath /tmp/FinanceTracker.xcarchive

# Export signed .ipa from the archive (requires ExportOptions.plist):
xcodebuild -exportArchive \
  -archivePath /tmp/FinanceTracker.xcarchive \
  -exportPath /tmp/FinanceTracker-export \
  -exportOptionsPlist ExportOptions.plist

# Upload to App Store Connect:
xcrun altool --upload-app --type ios \
  -f /tmp/FinanceTracker-export/FinanceTracker.ipa \
  -u <your-apple-id-email> \
  --password "$ASC_APP_PASSWORD"
```

`ASC_APP_PASSWORD` is an app-specific password generated at https://appleid.apple.com (Sign-In and Security → App-Specific Passwords). Don't use your real Apple ID password — Apple deprecated that path.

`ExportOptions.plist` is a one-time file describing how to sign and export. A minimal version for App Store distribution:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID_HERE</string>
</dict>
</plist>
```

Drop it next to `project.yml` and gitignore it (it has your Team ID).

## App Store Connect metadata (one-time, before public release)

These fields are required before TestFlight or App Store review — fill in App Store Connect before submitting:

- **App description** (max 4000 chars). Pitch: track money, scan receipts with Claude Vision, get AI insights.
- **Promotional text** (170 chars; visible in App Store search).
- **Keywords** (100 chars total, comma-separated, no spaces). Suggested: `expense,budget,receipt,scan,finance,money,tracker,debt,claude,ai`
- **Support URL**: `https://armandointeligencia.com/support` (page must exist before review).
- **Privacy Policy URL**: `https://armandointeligencia.com/privacy` (page must exist).
- **Marketing URL** (optional): `https://armandointeligencia.com`.
- **Screenshots** — required sizes per Apple guidelines:
  - 6.9" iPhone display (1320×2868) — iPhone 17 Pro Max
  - 6.5" iPhone display (1242×2688) — older Pro Max devices
  - 13" iPad display (2048×2732) — only if you ship an iPad-optimized build (we don't yet)
  - **These are NOT the dev-verification screenshots in `docs/ios-screenshots/`** — those were dev shots with status bars. App Store screenshots typically have marketing copy overlays and are 3–5 per device size. Generate them separately when you're ready to submit.
- **Privacy "nutrition label"** — declare what data the app collects:
  - Email (account creation) — linked to identity, used for app functionality
  - Photos (receipt scanning, NOT linked to identity, used only for app functionality, not used for tracking)
  - Financial transaction data (expenses, balances) — linked to identity, used for app functionality
  - All declarations live under App Privacy in App Store Connect.
- **Age rating**: 4+ (no objectionable content, no in-app purchases yet).

## Known gotchas

- **Bundle ID is permanent.** Once you create the App Store Connect record at `com.armandointeligencia.FinanceTracker`, you cannot rename it. If you want a different ID, you have to delete the record (which kills your TestFlight history) and start over.
- **Build numbers must monotonically increase.** Even rejected builds count. If you upload build 5 and Apple rejects it, your next upload must be build 6+.
- **First TestFlight build always goes through Beta App Review** (24–48 hrs). Subsequent builds usually skip review unless you change permissions, data collection, or the description.
- **The shell `ANTHROPIC_API_KEY=""` shadows .env when launching the local backend** (slices 7 + 9 hit this). Not relevant to TestFlight builds — the iOS app calls the production API URL — but worth a note here so future-you remembers.
- **iOS 26.0 deployment target matches both Armando's iPhone 17 Pro Max and Mom's iPhone 17 Pro.** Don't lower this without checking those devices' OS versions.

## After this slice (slice 11 candidates)

Things that didn't make the v1 cut, ordered by likelihood-of-mattering-once-Mom-uses-it:

1. **Real app icon design** — current "$" placeholder is fine for TestFlight beta but amateur for the public App Store. Commission an illustrator (Fiverr, 99designs).
2. **Spanish localization** — Armando + Mom are bilingual. String extraction → `Localizable.xcstrings` → DeepL or LanguageMcp the Spanish copy.
3. **Crash reporting** — Sentry SDK or Firebase Crashlytics. Free tiers are fine.
4. **Push notifications** — payment reminders, "your receipt scan finished" follow-ups. Requires APNs cert + a backend job.
5. **Biometric / Face ID lock** — was out of scope across slices 5 + 10. Real users tend to want it for finance apps.
6. **Friend-debt tracker** — feature flag's been there since slice 0 but iOS UI was deferred. Backend has `/api/v1/friend-debt/*`.
