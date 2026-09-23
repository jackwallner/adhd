---
paths:
  - "scripts/**/*"
  - "fastlane/**/*"
  - "NextCue.storekit"
  - "NextCue/PrivacyInfo.xcprivacy"
---

# Next Cue store setup and release

## Store identity

- Bundle ID: `com.jackwallner.adhd`.
- App Store Connect app ID: `6815023447`.
- Store title: `Next Cue: ADHD Routine Coach`.
- Privacy, support, and marketing URLs use `https://jackwallner.github.io/adhd/`.
- The app has a RevenueCat project with `pro` entitlement and `default` offering. The public SDK key lives in `Shared/Services/StoreService.swift`; no RevenueCat secret key belongs in this repository.

## Products and pricing

The local StoreKit configuration and setup scripts use:

- Monthly: `com.jackwallner.adhd.monthly`, USD $1.99, one-week free trial.
- Yearly: `com.jackwallner.adhd.yearly`, USD $14.99, one-week free trial.
- Lifetime: `com.jackwallner.adhd.lifetime`, USD $29.99, one-time purchase.
- RevenueCat entitlement: `pro`; offering: `default`.

`scripts/asc-setup-subscriptions.py` creates the subscription group, both subscriptions, availability, introductory offers in each territory, USA base prices, and the Vitals PPP subscription prices. PPP points are initial prices for this prelaunch app. Do not run this setup script after subscriptions are live; later price changes must preserve existing subscribers' prices. `scripts/asc-setup-lifetime-iap.py` creates the non-consumable, its availability, localization, and USA price schedule. It leaves existing schedules unchanged. Review ASC products and prices before running either script.

The API does not equalize subscription prices, so run `scripts/asc-fill-subscription-prices.py` after setup. It adds Apple's equalized price for every territory still missing one and keeps the USA and PPP rows. `scripts/asc-complete-listing.py` sets the age rating, categories, copyright, content rights, manual release, and App Review contact (pass `ASC_REVIEW_PHONE`; the number never lives in the repo). `scripts/asc-upload-review-screenshots.py` attaches `app-store/iap-review/paywall-<plan>.png` to each product; regenerate those renders with `PaywallSnapshotUITests` whenever the paywall or a price changes.

Both scripts verify that bundle ID `com.jackwallner.adhd` resolves to app `6815023447`. They load the shared ASC key from environment variables or `~/.baseball_credentials`.

## Metadata and legal pages

- English listing source: `fastlane/metadata/en-US/`.
- Run `python3 scripts/validate-metadata.py` after editing title, subtitle, keywords, promotional text, or description.
- Pull current ASC metadata with `scripts/pull-appstore-metadata.sh` before editing it.
- Upload listing metadata with `scripts/upload-appstore-metadata.sh`. Screenshots upload separately when `UPLOAD_SCREENSHOTS=true`.
- The privacy policy assumes routine data stays on device and purchase entitlement checks go through Apple and RevenueCat. Update it if runtime storage, analytics, or SDK behavior changes.
- Keep the medical disclaimer in the listing and legal copy. The app is for organization and routine planning, not medical advice.

## First submission checklist

- App Store screenshots come from `app-store/asc/nextcue.json` via the fleet `shotflow` renderer; the approved set is copied to `fastlane/screenshots/en-US/` and synced with `~/ios/appstore-screenshots/bin/asc-sync-screenshots`.
- Complete App Privacy, age rating, and review contact in ASC.
- Attach each in-app purchase to the app version in ASC and provide its review screenshot.
- Confirm product prices, trial territories, offer eligibility, and PPP price schedules in ASC before uploading metadata or submitting.

## TestFlight

`./scripts/testflight.sh` increments the build number, regenerates XcodeGen, archives Release, and uploads through the signed-in Xcode account. The script does not push a git branch. The ASC app record already exists.
