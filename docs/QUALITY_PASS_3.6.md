# 3.6 quality pass: baseline, root causes, fixes

This records what was wrong before the 3.6 pass and how it was found, so each fix
can be checked against the original behaviour.

## Phase A: baseline

Engine: Godot 4.3 (GDScript), `gl_compatibility` renderer. The canvas is
1920×1080 with `canvas_items` stretch and `keep` aspect. Screens are rebuilt
from scratch on every `UIManager.go_to`, and nothing is cached. State lives in
autoload managers saved through `SaveManager.SAVEABLE_SYSTEMS`. Tests are run
by `tests/run_tests.sh`:
- compile check
- balance sim
- stability soak
- unit + E2E
- display / living / city / UI / UX probes

### Problem 2: menus, scaling, implant purchasing

Reproduced with the new `tests/ui_stability_probe.tscn` (real mouse events,
rendered) in `--report` mode. The probe runs at 4 resolutions plus borderless
and fullscreen. Baseline result: **22 of 74 checks failed**.

| Symptom (player report) | Reproduction | Root cause |
|---|---|---|
| "Clicking is unreliable / a button isn't where it looks" | Hover a different shop card on the way to a BUY button: **the BUY button moves** (2 of 8 at every resolution) | `mouse_entered` on every card rebuilds the detail panel. The panel only has a minimum width, so its width follows the compare table of the hovered item, and the 2-column card grid reflows under the cursor (`shop_screen.gd`) |
| "Bought something else / lost my place" | After a purchase the detail panel shows a different item (9 of 10) | `money_changed`, `inventory_changed` and `resources_changed` each rebuild the whole list, and the rebuild selects `items[0]` |
| Duplicate purchases | A fast double-click on BUY buys **two** | No purchase lock. The rebuilt, enabled button appears under the cursor at once. In the black market the BUY button captures a **list index** (`_buy(i)`), so the second click buys the *next* offer |
| "Menus behave incorrectly" | A second navigation click during a screen fade is **dropped** (ends on the first screen) | `UIManager.go_to` returns early while `_transitioning` is set. The black market's redirect to the clinic is dropped the same way, which leaves an empty screen |
| Invisible click blocker | Clicking any stat caption or "?" opens the field guide. Its transparent full-screen catcher swallows the next click and survives screen changes | `Glossary._catcher` is `MOUSE_FILTER_STOP`, and `go_to` never closes the guide |
| "UI scale changes unexpectedly" | TEXT SCALE 1.4, LARGE TEXT or UI SCALE 1.1 push buttons off-screen on 10 of 12 screens (MENU, SEE CUSTOMER, tabs, INSTALL…) | Fixed-width layouts overflow a smaller logical canvas. The TEXT SCALE slider re-applies the theme on every drag tick. Settings writes (even showing a first-time hint) re-run `Accessibility.apply` + `apply_runtime` mid-screen. Display choices reset the window size. |
| Dialog buttons misplaced for a moment | Dialogs grow from the wrong corner | `game_dialog.gd` sets `pivot_offset` before layout |

Fine (verified): 40 rapid screen switches leave no scaled or offset screen, no
stacked signal handlers (65 → 65 connections), and no leftover full-screen
blockers. Every BUY button bought exactly its own implant when clicked without
hovering others.

### Problem 3: economy (read-only audit with numbers, `docs` below)

1. **Bought implants are reimbursed at 45 %** of their price
   (`IMPLANT_PRICE_MARKUP`). A tier-2 job nets about 0 and tier-3 nets −250 to −490
   when the implant is bought.
2. **Patient budgets** cap payment. About 55 % of Undercity patients pay only about
   60 % of the estimate, and the shortfall becomes a debt that is never
   collected automatically.
3. **A poor starting district** (pay multiplier about 0.75), so cheap jobs lose
   money when the implant has to be bought.
4. **Every clinic you ever owned is billed every night.** The back-alley room
   can't hold staff and sells for 0.
5. A **failure** costs the whole fee plus the implant.
6. Your own debt **compounds at 8 %/day**.
7. The balance sim **bypassed the patient budget / debt step**, so its
   milestones were optimistic.

### Problem 4: surgery (read-only audit)

- The tool selection is cleared at every stage (5–7 re-selections per operation).
- Many silent no-ops: near misses, a wire dropped off a terminal, SEAT during
  PLACE, quick actions on cooldown, a fast incision stall.
- One-shot timing stages (anesthesia window of about 0.45 s, the drill
  auto-cracks), and dropping the implant counts as a major mistake.
- Keyboard rotation steps are 15°, but the tolerance can be below 7.5°.
- Waits can't be skipped (0.6 s per stage, 1.8 s at the end, the results
  count-up, and the ESC skip that does nothing).
- The cautery ring is drawn at half its real reach.
- The results screen doesn't show implant cost, supplies, the patience cut or
  net profit.

### Problem 5: reputation (read-only audit)

There are nine separate standing values:
- street REP
- five reputation dimensions
- six factions
- heat
- suppliers
- cast and patient relationships
- staff loyalty
- story paths

**No change function receives a reason.** ChangeLog merges separate causes.
Heat thresholds disagree between places (25/50/75 in security, 35/60 in the UI,
60/85 elsewhere). REP −1 already reads "Butcher".

### Problem 1: information overload (read-only audit)

- The side bar listed 12 equal sections with no grouping.
- WHAT MATTERS NOW, CLINIC STATUS, RECENT CHANGES, the NEXT line and first-time
  cards all showed at full detail for everyone, with no way to turn it down.
- First-time cards could open over an operation or a conversation.
- The same toast could stack on screen several times.

## Phases B–F: what changed

### Problem 2: menus, scaling, implant purchasing

- **Shop:** the detail panel has a fixed width (540, clipped, scrolls
  sideways), so hover can't reflow the grid. `_shown` keeps the displayed
  item across rebuilds, and rebuilds are deferred and keep the scroll
  position. Card icons ignore the mouse.
- **Purchases:** `UIKit.debounce(key)` on every BUY. The black market captures
  the offer's `uid`, and `BlackMarketManager.index_of(uid)` resolves it at click
  time. Supplier offers are found by their dictionary at click time.
- **Navigation:** `UIManager.go_to` queues the last request made during a fade
  (`_pending_nav`). Modals, toasts and the field guide close before the fade.
  The field guide closes on an outside click without consuming it
  (`ClickOutsideCloser`).
- **Scaling:** the window is the only scale authority. `content_scale_factor`
  is always 1. INTEGER falls back to FIT below 1920×1080. `ui_scale` is folded
  into `text_scale`. TEXT SCALE commits on release. `main.gd` re-themes only
  when theme keys change. `apply_display` leaves the window alone unless the
  display settings changed. Dialogs fade instead of scaling from a corner.
- **Big text:** the status bar's stats scroll with MENU pinned. The clinic room,
  overlay labels and status rows clip. Facility, inventory, map and database
  compare scroll or wrap.

### Problem 4: surgery

- **Tools:** the stage's instrument is auto-selected (`ToolTray.select_category`),
  and a held tool survives only when nothing else is pressed.
- **Feedback:** rate-limited hints (`SurgeryStage._hint_limited`) for:
  - near misses on incision, expose, closing, the anchor drill, cautery and
    the implant drop;
  - out-of-order sutures;
  - a wire dropped off its terminal;
  - SEAT before PLACE;
  - a quick action on cooldown (toast).
- **Feel:** rotation steps are `clamp(tolerance × 0.8, 3°, 15°)` and dragging
  rotates 1:1. A near-miss drop is a hint, not a mistake. Anesthesia allows 3
  top-ups at −0.08 quality each. The cautery ring is drawn at its real reach.
- **Identity:** per-category instructions and parameters in
  `data/surgeries.json`:
  - eyes: precise;
  - dermal: forgiving;
  - limbs: heavy;
  - spine: careful drill;
  - neural: more calibration;
  - internal: a narrow anesthesia window;
  - respiratory: slow fill.

  `SurgeryData.for_diagnosis` drops the duplicate debridement after a correct
  clean-site diagnosis.
- **Pacing:** the stage-clear delay is 0.35 s (was 0.6 s) and the results delay
  1.1 s (was 1.8 s). The results count-up skips on click or ESC.
- **Summary:** the results screen adds THE MONEY:
  - fee and patience cut;
  - paid now and owed (an automatic plan);
  - the implant and where it came from;
  - supplies;
  - net.

  It comes from `SurgeryResult.finance`.

### Problem 3: economy

- **Pricing:**
  - fee = service (base pay × district pay × (0.5 + score)) + the part
    (implant price × 0.9 × min(pay multiplier, 1));
  - a black-market part pays 80 % of that, since it has no paperwork. Before
    this, units bought at 55–100 % of list price were paid back at 90 % of
    list.
- **Rules:**
  - any shortfall becomes an instalment plan;
  - staff jobs consume the implant and supplies (and are refused with a reason
    when they can't);
  - mothballed clinics pay half rent and no running costs;
  - debt interest is 4 %/day.
- **Before and after:** `JobEstimate` feeds PAYMENT / USES UP / YOU KEEP
  (file, plan, door card). `BusinessManager.outlook()` feeds the OUTLOOK card
  and the clinic's money advice.
- **Simulator:** `tests/economy_sim.tscn` runs 5 strategies on the real systems.
  - Runs are now fully repeatable: the global RNG and every manager's RNG are
    seeded from the run seed.
  - The black-market strategy now stocks cheap chrome. It never did before,
    because the sim skipped the market's restock hook.

### Problem 5: standing

- **Causes:** every standing change goes through `ChangeLog.record_standing`
  with the cause that was active (`push_cause` / `pop_cause` around about 40
  entry points). Repeats are batched, the history holds at most 200 entries,
  and it is saved.
- **Journal:** the STANDING tab (aliased from FACTIONS) has YOUR STANDING
  cards (reputation, heat, the factions that matter, with ALL FACTIONS), the
  five reputation sides, people (relationship and trust), suppliers and a
  HISTORY card. Each value shows its category, trend, current effect, next
  threshold and recent causes.
- **Previews:** event choices show "Standing: …" with the exact deltas, or
  "Risky (x%)".
- **Thresholds:**
  - heat uses the security levels everywhere: 25, 50, 75;
  - the reputation ladder gains "Distrusted" (−19 to −1) before "Butcher";
  - the clinic's REPUTATION row shows the tier, the trend and the next
    threshold.

### Problem 6: closing the clinic

- **Controls:** CLOSE DOORS / OPEN DOORS in the TODAY card, backed by
  `BusinessManager.doors_open`, which is saved and reopens every morning.
- **While closed:**
  - `CustomerManager` neither requests nor times arrivals;
  - `ClinicLifeManager` puts no walk-ins on the bench;
  - whoever is already in the chair stays;
  - the clock and bills keep running.
- **Reminder:** WHAT MATTERS shows a reminder line that reopens the doors on
  click.

### Problem 1: information

- **Side bar:** grouped into four places: CLINIC, BUSINESS, CITY, MESSAGES &
  JOURNAL.
- **GUIDANCE** (Settings > Gameplay), presentation only:

  | Level | What it shows |
  |---|---|
  | MINIMAL | Critical and important lines (at most 3) and only the status rows that aren't fine; no first-time cards |
  | STANDARD | The default (4 lines) |
  | DETAILED | 6 lines, the numbers under each status row, and a notice for important changes |

- **Notices:**
  - first-time cards wait while operating or talking;
  - DETAILED notices never show during surgery or dialogue;
  - only critical changes interrupt;
  - an identical live toast is never stacked twice.
- **Field guide:** new entries for doors, standing, outlook, the money and
  guidance.

## Phase G: results

### Economy simulation (`tests/economy_sim.tscn -- --days=20 --seeds=3`)

Median money after 20 days. Seeds are 1000, 1017 and 1034.

| Strategy | Baseline (3.5 rules) | 3.6 | Clinic tier reached (3.6) |
|---|---|---|---|
| Conservative | 7,300 | 10,869 | 5 |
| Specialist | 800 | 5,710 | 4–5 |
| Black market | 2,600 | 2,245 | 4–5 (13–20 market buys, heat 6–25) |
| Investment | 1,600 | 1,052 | 3–4 (2–3 staff) |
| Mixed | 2,100 | 2,292 | 2–4 (2–3 staff) |

Caveats on the comparison:
- The baseline ran on the old simulator, so the numbers are not directly
  comparable:
  - its runs were not repeatable;
  - its black-market strategy never reached the market, so it was simply
    "take every job".
- Investment and mixed end with less cash because they spend it on staff and
  facilities.

Every 3.6 target passes:
- every strategy ends ahead in all runs;
- no run spends 3+ nights deep in debt;
- every run affords a first upgrade or clinic;
- every run recovers from a mid-run loss of 400 cr;
- money stays between 1,000 and 40,000 cr;
- the top clinic is still a goal after 20 days.

Investment passes by the smallest margin (median 1,052 cr).

### Test suite (`tests/run_tests.sh`, rendered under Xvfb)

| Step | Result |
|---|---|
| Compile check | 209 files, 0 failed |
| Balance simulation (4 profiles) | BALANCE OK |
| Economy simulation | ECONOMY OK |
| Stability (soak, monkey, save fuzz, leaks) | OK (530 checks) |
| Unit + end-to-end, mouse and keyboard (includes `quality_tests.gd`) | 1,501 checks passed (an earlier run on the same features also graded the E2E surgeries S clean and B sloppy) |
| Display probe | 96 passed |
| Living-world probe | 274 passed |
| Living-city probe | 203 passed |
| UI probe | 132 passed |
| UI stability probe | 86 passed (baseline: 22 of 74 failed) |
| UX probe | 129 passed |

Check counts vary a little between runs because the soak and the generated
patients are random. The final run (commit `2f94c8c`) passed every suite with
no `SCRIPT ERROR`.

**Clean launch:** the main scene was run for 300 frames under Xvfb and exited
with code 0. Its output has no script errors, only the container's lack of a
sound card and of VSync support.

Failures found and fixed during Phase G:
- The UI stability probe failed at TEXT 1.4 with LARGE TEXT: the grouped side
  bar grew taller than the window and pushed SEE CUSTOMER off-screen. The side
  bar now scrolls.
- The living probe acted on the first open debt, which could already be on a
  plan. It now uses the debt it created.
- The early-game screenshots showed the TODAY card cutting off "CLOSE DOORS"
  and "SECURITY". They now wrap onto their own line.
- The economy sim was not repeatable, and its black-market strategy never
  restocked the market. Both are fixed.

### Remaining limitations and unverified behaviour

- **Economy:** balance is checked by simulation of 5 scripted strategies over
  20 days, not by human playtests.
  - Surgery skill in the sim is modelled, not played.
  - Story events, raids and world events are switched off in the sim.
- **Surgery feel:** the per-procedure tuning is verified by the E2E bot and
  the unit tests, not by players.
- **Standing history:** causes are recorded at about 40 entry points. A change
  from a path that isn't wrapped shows "No recorded cause" rather than a guess.
- **GUIDANCE:** changes presentation only. RECENT CHANGES and the journal
  always show everything.
- **Display:** window modes are checked under Xvfb on Linux. The Windows export
  isn't re-tested on real hardware in this pass.
