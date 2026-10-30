# Template changes from the Adhack ranking (2026-10-30)

Proposal only. Nothing here is in the app yet.

Source: adhack.vercel.app, a Japanese site ranking ADHD life hacks from a
survey (@awawa_adhd). On 2026-10-30 it listed 73 hacks. Below are the ones
that fit a routine planner, paraphrased, ranked by site rank and how well they
fit. Step tuples follow `RoutineStarterTemplate.steps` in
`NextCue/Views/RoutineTemplates.swift`:
(name, details, smallest start, minutes, optional).

Constraints checked: no leave-by deadlines, countdowns or learned timing (Shoes
On owns those, App Review 4.3); no health claims (1.4.1); every step keeps a
smallest start; every template keeps a short version (at least one optional
and one required step). The morning template's first three steps and step
count stay the same because `CoreFlowUITests` asserts them.

## Ranked changes

1. **Hang the trash bag on the front door handle so it leaves with you** (site #1).
   - Evening reset, new optional step: `("Hang the trash on the door handle", "", "Tie the bag", 1, true)`
   - Leave the house (new), optional step: `("Take the trash out", "", "Pick up the bag", 2, true)`

2. **Work alongside someone on a silent call** (site #4, body doubling).
   - Start a dreaded task, new optional step 2: `("Ask someone to work alongside", "A quiet call counts", "Text one person", 2, true)`

3. **Keep a pre-packed bag for each place you go** (site #72) and **keep keys at the door** (site #63).
   - New template **Leave the house**, symbol `door.left.hand.open`, weekdays at 8:30, reminder on:
     - `("Grab my bag", "Packed the night before", "Look by the door", 1, false)`
     - `("Phone, keys, wallet", "", "Pat your pockets", 1, false)`
     - `("Take the trash out", "", "Pick up the bag", 2, true)`
     - `("Pack an umbrella", "Every day, rain or not", "Open the closet", 1, true)`
     - `("Shoes on", "", "Put on one shoe", 2, false)`
     - `("Lock the door", "", "Pull the door shut", 1, false)`
   - Placed second in the list, after Morning start. It is a checklist with no deadline, which keeps it clear of Shoes On.

4. **Carry a folding umbrella every day instead of checking the forecast** (site #18).
   - Covered by the Leave the house umbrella step above.

5. **Wash dishes only while the microwave runs** (site #7).
   - Evening reset, new optional step 2: `("Wash the dishes", "Just while the microwave runs", "Rinse one plate", 5, true)`

6. **Eat by the clock because hunger signals are unreliable** (site #11).
   - Morning start, step 5 details only: `"Keep it simple"` becomes `"Hungry or not"`.

7. **Can't face a bath? Sit in the bathroom with your clothes on** (site #24, #56) and **a 3-minute shower counts** (site #55).
   - New template **Bedtime**, symbol `bed.double`, every day at 22:00, reminder on:
     - `("Charge my phone outside the bedroom", "", "Carry it to the hall", 1, false)`
     - `("Shower", "Three minutes counts", "Sit in the bathroom, clothes on", 5, true)`
     - `("Brush my teeth", "In the shower works", "Put toothpaste on the brush", 3, false)`
     - `("Lights out", "", "Turn off one light", 1, false)`

8. **Leave the phone outside the bedroom at night** (site #57).
   - Bedtime step 1 above. Evening reset drops its "Charge my phone" step, since Bedtime now owns it.

9. **Brush your teeth in the shower** (site #69).
   - Bedtime step 3 details above. Evening reset drops "Brush my teeth", which moves to Bedtime.

10. **Point at the first problem and wait until you start** (site #43).
    - Start a dreaded task, "Do the easiest part first" smallest start: `"Look at it for one minute"` becomes `"Point at where it starts"`.

11. **Leave the unfinished file open in the middle of the screen** (site #48).
    - Start a dreaded task, "Leave a note for next time" details: `""` becomes `"Leave it open where you’ll see it"`.

12. **Sweep everything off the desk before starting** (site #41).
    - Start work, "Clear the desk" smallest start: `"Move one thing"` becomes `"Push everything to one side"`.

13. **Start the day with the most trivial task** (site #47).
    - Start work, "Pick the one first task" details: `"Write it down"` becomes `"The easiest one is fine"`.

## Resulting Evening reset

With 1, 5, 8 and 9 applied, Evening reset moves from 21:00 to 20:00 so it sits
before Bedtime:

- `("Put tomorrow’s clothes out", "", "Pick a shirt", 4, false)`
- `("Wash the dishes", "Just while the microwave runs", "Rinse one plate", 5, true)`
- `("Tidy one surface", "", "Put away three things", 5, true)`
- `("Pack tomorrow’s bag", "Leave it by the door", "Put your bag by the door", 5, false)`
- `("Hang the trash on the door handle", "", "Tie the bag", 1, true)`

## Considered and left out

- Medication hacks (site #2, #33): reminders to take medication edge toward health claims.
- "Give up and get up when you can't sleep" (site #13): sleep advice, a 1.4.1 risk.
- Leave a party at a time you announce on arrival (site #6), wear your coat to leave work on time (site #26): leave-time tactics belong to Shoes On.
- Study-specific hacks (site #14, #17, #50, #67): good fits for a possible Study session template, not proposed here.

## If approved

- Apply the tuples to `RoutineTemplates.swift` (new cases `leaveHouse` and `bedtime`; `minute` returns 30 for `leaveHouse`; `weekdays` includes every day for `bedtime`).
- Add `NextCueTests/RoutineTemplateTests.swift` checking every template step has a name, smallest start and minutes, and every template has a short version. Run `xcodegen generate`.
- Screenshot the template list and the two new editors, then TestFlight.
