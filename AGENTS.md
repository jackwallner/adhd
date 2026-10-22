# Next Cue, Project Guide

An ADHD routine companion that helps people plan daily steps and see what to do next. XcodeGen project and scheme: `NextCue`. Simulator pool owner: `adhd`.

## Targets and identifiers

- iOS 17+, Swift 6, SwiftUI, XcodeGen (`project.yml`).
- App: `com.jackwallner.adhd`; Live Activity widget: `com.jackwallner.adhd.widget`; unit tests: `com.jackwallner.adhd.tests`; UI tests: `com.jackwallner.adhd.uitests`.
- App Store Connect app: `6815023447`, listing title `Next Cue: ADHD Routine Planner`.
- RevenueCat project: `proj202c8445`, app `appa1f2af1602`, entitlement `pro`, offering `default`.
- Subscription products use `com.jackwallner.adhd.monthly`, `.yearly`, and `.lifetime`.

## Build and product notes

- Run `xcodegen generate` after adding or removing Swift files or editing `project.yml`.
- `NextCue.storekit` is attached to the app scheme for local purchase testing. Simulator builds must return before configuring RevenueCat with the production key.
- Next Cue is an organization and routine planning tool. Do not claim that it diagnoses, treats, or manages ADHD or other medical conditions.
- Keep the privacy policy aligned with the app's actual storage and SDK behavior.
- Ratings: no in-app rating question (App Review 5.6.1). Finishing a routine in full (Done on the finish screen, no paywall opened from it) records a positive moment; when the run closes (cover or unfolded pane), `NextCueRootView` calls the system `requestReview()` about 3s later if nothing is presented (from the 2nd launch, 30-day cooldown; `ReviewPromptTracker`). A blocked ask stays pending. Settings has separate "Rate Next Cue" and "Send feedback" rows.

## Rules index

- `.claude/rules/run-experience.md`: product lane, run mechanics, notifications, Live Activity.
- `.claude/rules/store-and-release.md`: ASC setup scripts, metadata rules, subscription defaults, and release steps.
- `.claude/rules/iphone-duo.md`: unfolded two-pane layout (Home beside the run), pane closing, Duo capture routes.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC credentials, signing, and review funnel) are in the global agent rules and the `ios-dev` skill.
