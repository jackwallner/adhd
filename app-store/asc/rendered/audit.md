# Screenshot audit: nextcue

Status: **PASS**
Disposition: **RELEASE-READY**
Target: `iphone_69` at `1320x2868`
Capture status: `ok`

This report combines file-spec checks with an independent thumbnail and OCR pass. Open each `contact-sheet.png` and `search-grid.png` before approving a set.

## Warnings

- smaller-first-step: 04-give-every-step-a-tiny-first-move.png: thumbnail OCR missed header words ['give', 'every', 'tiny', 'first', 'move']
- smaller-first-step: 05-pick-a-routine-ready-to-go.png: thumbnail OCR missed header words ['pick', 'routine', 'ready']

## Market brief

- Category: ADHD routine starters
- Audience: Adults who know what their routine is but get stuck starting it, including people looking for ADHD-friendly structure
- Problem: Checklists and planners list what to do, but a step that feels too big still leaves the person frozen before it.
- Advantage: Next Cue shrinks any step to a tiny first move when the user taps I'm stuck, then brings the whole step back once they start. Templates ship with these smallest starts filled in. The first routine is free; Pro adds more routines.
- Competitive context: Routine apps range from full-day visual planners to timer-led habit trackers. Next Cue focuses on the moment of starting: one current step, a smaller version of it on demand, and no streaks or countdowns.

## Sets

| Set | Status | Frames |
| --- | --- | ---: |
| `smaller-first-step` | pass | 6 |

## Review contract

- Contract: `single-header-benefit-story-v3`.
- Every creative frame has exactly one large, period-free header capped at two lines. Eyebrows and subheaders are forbidden.
- Phone frames use at least 50% of the canvas for literal UI evidence.
- The selected submission set contains six to eight frames. Other sets and background variants are review alternatives, not additional ASC inventory.
- Every visible header pitches a concrete benefit backed by a per-frame problem, advantage, search term, and literal UI proof.
- The first three frames must communicate separate market value at search scale.
- Every frame declares source, source_evidence, capture_flow, device, and evidence_status. Validated-staged frames identify local preview evidence; canonical frames map one-to-one to capture-report records.
- The app screen must be real capture evidence from the referenced build.
- Health and wellness copy must stay complementary and non-diagnostic.
- Re-run the audit after every copy, source, or layout change.
