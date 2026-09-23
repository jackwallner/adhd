# Next Cue, Project Guide

An ADHD routine companion that helps people plan daily steps and see what to do next. XcodeGen project and scheme: `NextCue`. Simulator pool owner: `adhd`.

## Targets and identifiers

- iOS 17+, Swift 6, SwiftUI, XcodeGen (`project.yml`).
- App: `com.jackwallner.adhd`; unit tests: `com.jackwallner.adhd.tests`; UI tests: `com.jackwallner.adhd.uitests`.
- App Store Connect app: `6815023447`, listing title `Next Cue: ADHD Routine Coach`.
- RevenueCat project: `proj202c8445`, app `appa1f2af1602`, entitlement `pro`, offering `default`.
- Subscription products use `com.jackwallner.adhd.monthly`, `.yearly`, and `.lifetime`.

## Build and product notes

- Run `xcodegen generate` after adding or removing Swift files or editing `project.yml`.
- `NextCue.storekit` is attached to the app scheme for local purchase testing. Simulator builds must return before configuring RevenueCat with the production key.
- Next Cue is an organization and routine planning tool. Do not claim that it diagnoses, treats, or manages ADHD or other medical conditions.
- Keep the privacy policy aligned with the app's actual storage and SDK behavior.

## App Store and release

See `.claude/rules/store-and-release.md` for ASC setup scripts, metadata rules, subscription defaults, and release steps.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC credentials, signing, and review funnel) are in the global `AGENTS.md` and `ios-dev` skill.
