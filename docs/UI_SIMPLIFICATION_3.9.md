# 3.9 — Radical UI simplification, progressive features, tutorial redesign

Rule for this pass: every element on screen has to justify itself; when in
doubt, hide it until it matters. Presentation only: generation, surgery,
odds, difficulty, implant stats, economy, reputation, hidden complications,
progression rules and the save format are unchanged.

## 1. Measured: before and after

`tests/audit_probe.tscn` walks a fresh save through the core loop with real
clicks and counts what is visible on screen (panels, non-empty labels,
buttons). Same script, same flow, before (3.8.0) and after.

| Screen | Panels | Labels | Buttons |
|---|---|---|---|
| Clinic (first patient at the door) | 8 → 5 | 46 → 18 | 12 → 6 |
| Patient (one click) | 14 → 6 | 126 → 23 | 23 → 10 |
| Patient + DETAILS (new level 2) | – → 6 | – → 32 | – → 12 |
| Full file (level 3) | 10 → 9 | 76 → 71 | 20 → 20 |
| Scan | 10 → 10 | 39 → 22 | 16 → 16 |
| Plan | 6 → 7 | 71 → 29 | 13 → 11 |
| Surgery | 10 → 8 | 40 → 24 | 12 → 10 |
| Clinic after job 1 | 7 → 5 | 39 → 19 | 19 → 8 |
| Supply | 14 → 10 | 105 → 42 | 23 → 16 |
| **Total (8 screens)** | **79 → 60 (−24%)** | **542 → 248 (−54%)** | **138 → 97 (−30%)** |

The plan gained one panel: the DETAILS fold that now holds what used to be
always open. The full file is the deliberate "everything" level and was left
as is.

Run it: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/audit_probe.tscn -- --shots=/abs/dir`

## 2. Three information levels (same everywhere)

1. **Essential**: what you need to decide or act, on screen by default.
2. **Details**: one click (DETAILS / a fold), same window.
3. **Advanced**: the full document or section (intake form, full file,
   cyberware database, field guide).

## 3. What was removed or merged

**Clinic**
- **WHAT MATTERS NOW** panel removed. It duplicated the NEXT objective and the
  status rows. NEXT (one objective, one reason) and SEE PATIENT remain.
- The **CLINIC STATUS** card and its rows were merged into one clickable line
  in the TODAY bar. It shows the most serious issue (with its link), or
  "Jobs n / cap today · time left" when nothing needs you.
- The TODAY bar's separate JOBS / NIGHT LEFT / SUPPLIES / HEAT / SECURITY
  captions were folded into that line and the status bar.
- The arrival toast was removed (the door and SEE PATIENT already say it).

**Status bar**
- LEVEL appears with SKILLS. REP and JOBS appear after the first job. HEAT
  appears once there is heat. PARTS and TOKENS appear with the black market.
  CREDITS is always shown.

**Patient**
- The four always-open blocks (REQUEST / OPERATION / FINANCES / DECISION)
  and the inline intake form were replaced by:
  - **Level 1:** name, WANTS (implant + procedure), one risk sentence
    (what's missing, else `IntakeRecord.key_risk`: the most serious factor
    the doctor can see), MONEY (pays ≈ X, you keep ≈ ±Y before rent), and
    ACCEPT JOB / DETAILS / DECLINE.
  - **Level 2 (DETAILS):** difficulty and time, your odds with what they're
    based on, what can go wrong, the costs, instalments, cash today, the
    advice and every risk factor.
  - **Level 3:** INTAKE FORM (the 3.8 document, unchanged) and FULL FILE.

**Plan (diagnosis screen)**
- The surgery preview shows your odds and what you keep. Everything else
  (risk list, money lines, neural load when it doesn't matter) moved into a
  DETAILS fold.
- Duplicate chips removed.
- Empty scan slots stay empty until scanned; one instruction covers how.

**Surgery**
- The header names procedure, patient and implant. The patient card and
  implant spec card are gone during the operation.
- The key-hint line was cut to RMB / wheel / pause, since tools and the
  emergency buttons show their own keys.
- Tool tray: each tool shows its name, and its wear only when worn. Tier,
  precision and speed are in the tooltip.

**Supply**
- Rows show the name, one benefit line, "n in stock", and a ★ when the
  patient at the door needs it (implant or missing instrument).
- Tier, category, load and difficulty are in the detail panel's fold.
- The duplicate balance label was removed (cash is in the status bar and in
  BEFORE YOU PAY).

**Results**
- AFTERMATH shows at most two "NEW" items, one sentence each, plus "+n more".
  An unbounded list could push CONTINUE off-screen; the E2E layout check
  caught this once.
- VIEW PATIENT appears only once the journal is introduced.

**Duplicate hint triggers removed** (each repeated a coach step or the
section's own introduction): clinic priorities, journal, black market, plan
preview, map, staff.

## 4. Tutorial redesign

There is one coach step at a time. Each step points at the real control and
advances when you do the action.

| Stage | Steps (title · target) |
|---|---|
| 1 Clinic | THE CLINIC · SEE PATIENT |
| 2 Inspect patient | THE PATIENT · ACCEPT JOB |
| 3 Prepare | 1 · SCAN · scan view → 2 · PLAN · BEGIN |
| 4 Operate | 3 · SEDATE → 4 · CUT → 5 · INSTALL → 6 · CLOSE (one per surgery stage) |
| 5 Outcome | 7 · RESULT · CONTINUE → NEW · SKILLS · side-bar button |

Feature introductions (stage 6+) use the same coach mark on the new
side-bar button, titled "NEW · <SECTION>". Each has one sentence and GOT IT,
with no counter. Opening the section also completes it. The old
four-paragraph intro card (what / why / how / cost) is gone. Its text stays
in the field guide, and TUTORIALS → SHOW AGAIN replays the coach step.

**Guidance setting:** one choice, TUTORIAL & GUIDANCE:
- **GUIDED:** tutorial, sections introduced as they matter.
- **BRIEF:** no tutorial; new sections still appear gradually, with a toast
  instead of a coach step.
- **OFF:** no tutorial, every section visible.

It maps onto the existing `tutorial_hints`, `progressive_features` and
`guidance_level` keys, so old settings files keep working.

## 5. Features by stage (when they appear)

| Section | Becomes relevant |
|---|---|
| SKILLS | after the first job (you have a point to spend) |
| SUPPLY | second job, or supplies ≤ 2, or the patient at the door is missing a tool or supplies you can buy |
| INVENTORY | second job |
| JOURNAL | second job, or an unread message |
| BUSINESS | day 2, or a debt |
| CYBERWARE DB | third job |
| STAFF | third job, or you have staff |
| FACILITY | third job, or a clinic tier above 0 |
| CITY MAP | fourth job, or you are away; a lead's link introduces it on click |
| BLACK MARKET | its own existing unlock |

**Visibility control:** a section that isn't introduced is not drawn. That
covers the side bar, status-bar terms and screen controls (VIEW PATIENT,
customer-file shortcuts). Its hotkey shows a short "not yet" toast instead
of opening it. `GameManager.navigate`, `UIManager._route` and `Nav.open`
check the same `Features.is_on`, so nothing can open it early. A contextual
link introduces the section on the click.

**States:** not yet (not in `introduced`) → in progress (`intro_pending`,
coach step queued or showing) → introduced (`introduced[id] = day`).

## 6. Existing saves

The save format is unchanged. A save without `introduced` (from before 3.7)
gets every section, with no introductions queued. On every load,
`Features.refresh()` introduces anything already relevant from game state,
so a lost flag never hides something the player had. The rules only add
sections and never remove one.

## 7. Gameplay

No gameplay files changed. Managers touched: `settings_manager.gd` (the
guidance mode) and `tutorial_manager.gd` (step text, coach-based intros).
Both are UI state. The balance and economy simulations report the same OK
results.

## 8. Tests

- New: `tests/audit_probe` (counts and screenshots).
- New unit checks:
  - guidance mode round-trip and mapping;
  - `IntakeRecord.key_risk` (the most serious factor, one sentence);
  - feature stages: one introduction after job 1, SUPPLY on low supplies,
    stage 2 and day 2.
- Updated for the new UI: ux, onboarding, ui and living probes, and the E2E
  bot.
- `living_world_tests` "finance variety" now seeds the generator's RNG and
  restores its state afterwards. Over 120 random patients it sat at the
  threshold (5) in 7 of 22 logged runs and dipped to 4 once. The count still
  varies a little (6–7 in the two runs after the fix), because generation
  draws on other randomness too, but it now stays clear of the threshold.
  This is a test change only; generation is unchanged.
