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

## Phases B–H: what was built

### Patient summary (B)

`PatientSummary` (modal) is built from `PatientBrief.build(c)`. Opened by SEE PATIENT,
clicking the patient in the room, the customer key and WHAT MATTERS links.

| Block | Shows | Source |
|---|---|---|
| REQUEST | implant (tier, category), what it does, procedure, known conditions | `CyberwareData`, `SurgeryData`, `revealed_conditions` |
| OPERATION | difficulty in words (EASY … EXTREME, 1–5) and time; **your odds ≈ x% (estimate)** with what it's based on; what can go wrong; missing requirements with a fix button | `install_difficulty`, `TimeManager.procedure_minutes`, `Recommend.self_estimate`, `Recommend.possible_complications`, `JobVerdict.checks` (only `BLOCKING`: request, tools, supplies, accepts) |
| FINANCES | patient pays (now / in instalments), implant (source), supplies, **direct margin** (labelled "before rent and wages"), cash in hand when the unit is from stock | `JobEstimate.for_customer` |
| DECISION | one neutral line from the numbers above; ACCEPT JOB (disabled while blocked); DECLINE with its real cost; MORE DETAILS | `PatientBrief.recommendation`, `GameConfig.DECLINE_*` |

Difficulty and odds are kept apart. The odds are always labelled an estimate:
they assume a correct diagnosis, and hidden conditions are unknown. The
patient's statement is styled as flavor (`UIKit.flavor`).

### Clinic status dashboard (C)

`ClinicStatus.dashboard()` gives one headline, the first that applies:

1. OPERATION IN PROGRESS
2. ACTION REQUIRED (an incident or a conversation waiting)
3. CAN'T OPERATE: NO SUPPLIES
4. PATIENT WAITING: MISSING … (from the door patient's blocking checks)
5. FINANCIAL CONCERN (once BUSINESS is introduced)
6. DOORS CLOSED
7. DAY'S WORK DONE
8. READY FOR PATIENTS

After the headline come up to three issues: the non-fine `ClinicStatus.rows()`.
- Staff and black-market issues show only once their section is introduced.
- A new name (rep 0) isn't an issue.
- On the first patient, only the headline shows.

Every line is clickable through `Nav`. WHAT MATTERS drops what the dashboard
shows (`DASHBOARD_IDS`, staff stress and raises) and lines that point into
sections not introduced yet. The NEXT line adds why it matters and marks
optional steps.

### Consequence previews (D)

`DecisionPreview.facts / summary / build` covers cost, cash now → after,
tonight's bill and any recurring cost, with "can't afford" and "leaves less
than tonight's bill" warnings. It never projects income.

| Decision | Preview |
|---|---|
| Accepting a patient | the summary (money, odds, missing, risks) |
| SUPPLY implant / tool | BEFORE YOU PAY box: cost, cash, stock now → after, purpose, limits, uncertainty |
| Supply pack | button tooltip |
| FACILITY upgrade | BEFORE YOU PAY with the new nightly upkeep |
| Buying a clinic | a dialog when confirmations are on (cost, cash after, rent + running before → after, jobs/day) |
| Hiring | cash after and the nightly wage under HIRE |
| Black market / suppliers | tooltip: cost, cash after, heat and standing (`BUY_HEAT`, `BUY_STANDING`) |
| Conversation choices | "Known: …" for faction, rep, heat and money. Relationship and fear stay hidden; checks say "if it works" |
| Events | (existing) `Standing.preview` per choice |
| Surgery | (existing) SURGERY PREVIEW in the plan |

Routine purchases don't ask for confirmation. Buying a clinic and declining
a patient go through `UIManager.guard`, so the CONFIRM DANGEROUS ACTIONS
setting is respected.

### Simplification (E)

- **Door card:** now a teaser: who, what, about what they pay, and one advice line.
  The neural meter, risk line and verdict rows moved to the summary.
- **Dossier:** keeps what's unique to it (statement, history, payment terms,
  staff, defer). Its money sentence became one reference line.
- **Progressive TODAY card:**
  - the HEAT meter appears once there is heat or the black market is open;
  - SECURITY appears with FACILITY, an open case or rising heat.
- **One word per action:** SEE PATIENT, ACCEPT JOB, DECLINE, MORE DETAILS.
- **Flavor text:** quoted, slanted and dim in the summary and the dossier.

### Progressive onboarding (F)

| Stage | When | Sections |
|---|---|---|
| 1–2 | new game | CLINIC, SETTINGS, FIELD GUIDE (+ the first-operation tutorial) |
| 3 | 1 job (journal also on a message) | SKILLS, SUPPLY, INVENTORY, BUSINESS, JOURNAL |
| 3+ | 2 jobs | CYBERWARE DB |
| 4 | 3 jobs (or staff hired, a better clinic) | STAFF, FACILITY |
| 5 | 4 jobs, being out, or a lead into the city | CITY MAP |
| — | its own rule (street rep or a contact) | BLACK MARKET |

How introduction works:
- **Rules:** `Features.relevant(id)` reads only existing state.
- **Links:** a contextual link (`Nav.open`) introduces its section.
- **Hidden sections:** a section that isn't introduced is hidden, not
  padlocked. Its key or room prop gives a one-line "opens up …" message.
- **Intro cards:** each introduction queues a card (WHAT / WHY / HOW / COST,
  OPEN, MORE, GOT IT). It is shown on the clinic when nothing else is open,
  and never during surgery, a conversation, the tutorial or a dialog.
- **NEW mark:** a section is marked NEW in the side bar for a day.

Persistence and fallbacks:
- **Saving:** state lives in `TutorialManager.introduced` and `intro_pending`.
- **Old saves:** saves without the key keep every section, with no cards.
- **Validation:** `refresh()` runs on load, so a lost flag never locks
  anything relevant.
- **Setting:** INTRODUCE FEATURES GRADUALLY (off = everything). It works with
  GUIDANCE (MINIMAL turns cards into one-line notices) and TUTORIAL HINTS.

### Handbook (G) and guidance (H)

- **Categories:** GETTING STARTED, PATIENTS & IMPLANTS, SURGERY, BUSINESS,
  REPUTATION & RELATIONSHIPS, CITY & LOCATIONS, CLINIC & STAFF, TUTORIALS,
  CONTROLS.
- **Entries:** an entry's `feature` holds it back until introduced, with a
  count ("3 more entries open up as your clinic grows"). NEW marks entries
  introduced in the last day. Core entries add WHY IT MATTERS and WHERE.
  SEE ALSO links related entries, and BACK returns. Search never reveals
  held-back entries.
- **TUTORIALS:** every introduced section and every first-time card seen,
  with SHOW AGAIN.
- **Help links:** the summary's `?` chips open "your odds", "direct margin",
  "difficulty" and "payment terms". Intro cards' MORE opens the matching
  entry.
- **The NEXT line:** says why the step matters. Optional steps read
  "WHEN YOU'RE READY >".

## Phase I: tests (final run, `tests/run_tests.sh`, rendered under Xvfb)

| Step | Result |
|---|---|
| Compile check | 216 files, 0 failed |
| Balance simulation (4 profiles) | BALANCE OK |
| Economy simulation | ECONOMY OK |
| Stability (soak, monkey, save fuzz, leaks) | OK (550 checks) |
| Unit + end-to-end, mouse and keyboard (now through the patient summary; includes `onboarding_tests.gd`) | 1,583 checks passed; E2E surgeries graded S (clean) and B (sloppy) |
| Display probe | 96 passed |
| Living-world probe | 274 passed |
| Living-city probe | 203 passed |
| UI probe (SEE PATIENT → summary → MORE DETAILS → file) | 144 passed |
| UI stability probe | 86 passed |
| UX probe | 131 passed |
| **Onboarding probe** (new): new game, sections by stage, summary numbers vs the game's, keys, intro cards, previews, handbook, old saves, the setting; summary and clinic at 4 resolutions × 3 window modes | 71 passed |

`tests/onboarding_tests.gd` covers:
- **Patient brief:** its money equals JobEstimate, its odds equal Recommend,
  and missing requirements block with a fix.
- **Dashboard:** headlines and issues.
- **Guidance:** deduplication with the dashboard.
- **Features:** stages, NEW, links, save round-trip, old saves, validation
  and the setting.
- **Previews:** the money facts.
- **Handbook:** gates, SEE ALSO validity, held-back entries.
- **Conversations:** known vs hidden consequences.

Found and fixed during Phase I:
- **First patient showed later sections.** At the very start the rules showed
  SKILLS (everyone starts with a point), the JOURNAL and the CITY (the main
  quests start at once). The rules now wait for real relevance.
- **WHAT MATTERS pointed into sections not yet introduced.** On the first
  patient it showed a city lead and skill points. Those lines now wait.
- **Old saves and resets marked every section NEW.** Fixed.
- **Alarming margin on the first job.** It used a unit from stock and showed
  a margin of −2 cr. The summary now also shows cash in hand, and the advice
  explains the gap.

**Clean launch:** the main scene was run for 300 frames under Xvfb and exited
with code 0. At exit Godot reports "ObjectDB instances leaked / 12 resources
still in use". The 3.6 build does the same when launched the same way, so it
isn't from this change. The stability suite's leak and orphan checks pass.

## Known limitations

- **Odds:** your odds are the game's existing estimate (`Recommend`). They come
  from your record, the difficulty against your level and complication odds.
  It isn't a simulation of your hands, so the summary calls it an estimate.
- **Stages:** stage thresholds (1 / 2 / 3 / 4 jobs) were checked by the probes
  and tests, not by first-time human players.
- **City lead:** a lead into the city introduces the CITY MAP when its line is
  clicked. Until then the lead waits off WHAT MATTERS on very early days.
- **Handbook:** WHY IT MATTERS / WHERE were written for the core entries (12).
  The others keep their single explanation.
- **Dossier:** the full file still uses the 3.5 three-column layout. It is now a
  secondary view (MORE DETAILS), with its money line reduced to a reference.
- **Localization:** the game has no localization system. New texts follow the
  existing English-in-code / JSON approach.
