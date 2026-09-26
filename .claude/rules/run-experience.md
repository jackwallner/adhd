---
paths:
  - "Shared/**/*"
  - "NextCue/Views/**/*"
  - "NextCueWidget/**/*"
---

# Run experience and product rationale

Next Cue's lane is task initiation and getting back on track, not time
pressure. The sibling app Shoes On (`~/time`) owns leave-by deadlines, backward
planning, and learned step timing; do not copy those into Next Cue.

## Principles

- Lead with the literal first step (Today card, reminder body). Starting one
  small action is easier than starting a routine.
- Time is information, never a countdown. The step timer counts up beside the
  estimate and says running long is fine. Settings can hide it.
- No streaks or guilt. A run left from an earlier day is closed as a partial
  record on launch (`RoutineStore.recoverActiveRun`) so it never blocks today's
  reminders.
- Every step action is undoable: toast Undo after Done, Skip, or Do it later;
  "Back a step" in the run menu; "Undo the last step" on the finish screen.

## Mechanics

- `RoutineRun.history` records each done, skipped, or later step in order;
  `RoutineEngine.moveBack` pops it. "Do it later" moves the step to the end of
  `run.steps`, so undoing it must pop in LIFO order.
- Short version: `RoutineStep.isOptional` steps are dropped by
  `RoutineEngine.makeRun(shortVersion:)`. It only exists when it keeps at least
  one step and drops at least one (`Routine.hasShortVersion`). A finished short
  run counts as done for the day.
- `TodayPlan` picks "up next": the latest open routine due within the window
  (30 min early to 4 h late), else the next upcoming, else an anytime routine.
- Notifications (`ReminderPlan`, `ReminderService`): routine reminders with
  Start now and a 10-minute snooze; one drift check-in per step at estimate
  plus grace (2 to 10 min) with Done and Pause actions. Check-ins are hidden
  while the app is in the foreground and never scheduled for paused runs.
- Live Activity: `LiveActivityService` mirrors the active run after every
  store commit. `CompleteStepIntent` / `ResumeRunIntent` compile into the
  widget with empty bodies (`WIDGET_EXTENSION`) and run in the app process.
  A run finished by its last step shows "All done" for two minutes; a cancel
  ends it immediately.
- Persisted models decode new fields with `decodeIfPresent` defaults. Keep
  doing that for every added field; TestFlight users have older state files.
