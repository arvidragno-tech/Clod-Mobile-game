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
