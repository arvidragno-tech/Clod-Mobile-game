# 3.7 UX overhaul: audit, plan and results

## Phase A: audit

Engine: Godot 4.3 (GDScript), 1920×1080 `canvas_items` canvas (the window is
the only scale authority since 3.6), autoload managers saved through
`SaveManager.SAVEABLE_SYSTEMS`. Input goes through `Controls` (rebindable
actions) and `InputContext` (who owns the keyboard). Screens are rebuilt on
every `UIManager.go_to`; overlays (field guide, hints, changes) live in the
help layer above screens.

### What already exists and is reused

| Need | Existing system | Used for |
|---|---|---|
| Job money | `JobEstimate.for_customer` | Patient summary FINANCES, the dossier, the plan |
| Your odds | `Recommend.self_estimate` (record on the procedure, difficulty vs level, `SurgeryManager` complication odds) | Patient summary OPERATION |
| Readiness | `GameManager.get_surgery_readiness`, `JobVerdict.checks/advice` | Missing prerequisites and the recommendation line |
| Priorities | `Guidance.items` (WHAT MATTERS), `ClinicStatus.rows` | The clinic dashboard |
| Standing effects | `Standing.preview` | Known reputation consequences |
| Explanations | `data/glossary.json` + `Glossary` (field guide) | The handbook |
| First-time cards | `Hints` | Feature introductions |
| Onboarding state | `TutorialManager` (saved; old saves count as finished) | Feature introductions, revisit list |
| Stages | `Difficulty.ops()` (Learning 0–2, Street 3–7, Undercity 8+) | When features become relevant |
| Navigation | `Nav.open(link)` | Every actionable line |

### Problems found

1. **Every system from minute one.** The side bar shows 12 sections on the
   first patient (staff, facility, database, black market as a padlock, the
   city map...). Nothing in the game decides when a feature is relevant.
2. **Clicking a patient opens a 3-column dossier** (statement, request,
   payment, risk, medical history, previous operations, neural load, at a
   glance, decision with 4–5 buttons). The decision needs about 6 of its
   ~40 lines.
3. **The door card repeats the dossier** (portrait, offer, risk, neural load
   meter, verdict rows) and the clinic shows a second copy of the same
   information in CLINIC STATUS and WHAT MATTERS (supplies, debt, heat each
   appear twice).
4. **CLINIC STATUS is six permanent rows**, five of them usually "fine"; it
   says nothing about whether you can take the patient at the door.
5. **No success estimate before the plan.** The dossier shows the
   recommended surgeon's odds but not difficulty in words, and payment, cost
   and margin are one dense sentence.
6. **Purchases show the price but not the cash after**, and upgrades or a new
   clinic don't say what they change before you pay.
7. **The field guide is flat**: every entry from the start (black market,
   staff, travel), no "new" marker, no way to revisit tutorial cards, no
   back step.
8. **Flavor and requirements look alike**: patient statements, rumours and
   advice all use the same body text.

### Plan (phases B–I)

- **B. Patient summary** (`PatientSummary` modal): REQUEST, OPERATION
  (difficulty in words, estimated success with its main factors, key risks,
  missing requirements with a fix button), FINANCES (payment / direct costs
  / estimated direct margin, labelled as such), DECISION (ACCEPT JOB,
  DECLINE with its real cost, MORE DETAILS → the dossier). Opened by the
  door card, clicking the patient in the room and the customer key.
- **C. Dashboard**: CLINIC STATUS becomes one headline state plus only the
  issues that need you, each clickable; WHAT MATTERS stops repeating them.
- **D. Previews**: one `DecisionPreview` component (cost, cash now → after,
  stock, purpose, limits, uncertainty) in SUPPLY, the black market,
  suppliers, FACILITY (upgrades and clinics) and STAFF (hiring).
- **E. Simplification**: a short door card, flavor text styled as flavor,
  consistent action words.
- **F. Onboarding**: feature introductions by stage, nav entries appear when
  relevant (no padlocks), an intro card when each appears, revisit list,
  save migration (old saves keep everything), a setting to show everything.
- **G. Handbook**: field-guide categories matching the game, entries for
  features not yet introduced held back, NEW marks, related entries and a
  back step, TUTORIALS (revisit) section.
- **H. Guidance**: the NEXT line says why; optional lines are marked.
- **I. Tests and probes.**
