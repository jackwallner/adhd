---
paths:
  - "NextCue/Views/HomeView.swift"
  - "NextCue/Views/UnfoldedSplit.swift"
  - "NextCue/Views/RoutineRunView.swift"
  - "NextCue/Views/NextCueDebugLaunch.swift"
---

# Next Cue: iPhone Duo (2026-10-22)

- Unfolded (regular width, at least 720 pt), `HomeView` keeps Home on the
  leading side of the fold. The trailing pane shows, in order: the active run
  (`router.showRun`), else the screen Home would have opened as a sheet
  (`HomeSheet`: editor, new routine, settings, paywall), else the editor of
  the routine up next. Portrait unfolded and every compact width keep the
  phone layout: the run is a full-screen cover and `HomeSheet` is a sheet.
- Pane edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split (`UnfoldedSplit`, unit
  tested). Each pane gets `horizontalSizeClass = .compact`.
- Folding only moves Home's frame, so its scroll survives. The run and pane
  screens are rebuilt when the pose changes; run state lives in
  `RoutineStore`, only the view-only stuck state and an open editor draft reset.
- Screens shown in the pane have nothing to dismiss: they call the
  `closePane` environment action when it is set, else `dismiss`. The run
  closes through `router.showRun = false` in both poses, and the rating ask
  hangs off that change in `NextCueRootView`.
- Captures: DEBUG `-CaptureTour` walks a fresh run through run, paused,
  finish and stuck (8 s each) and stays on stuck. `simctl openurl` prompts
  "Open in Next Cue?", so no URL routes. gh-sim shoots one state per pose per
  job; use `-Screen <name>` launches for the other PNGs.
