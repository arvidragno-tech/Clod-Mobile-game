# Patient intake form (3.8): audit, rules and results

Presentation only. No new patient attributes, conditions, rolls, checks,
mechanics or calculations. The form reads existing patient data through the
existing rules and keeps the game's existing information boundaries.

## Audit: patient data that affects play

| Data (CustomerData / systems) | Affects | Visible to the player before 3.8 | On the form |
|---|---|---|---|
| `requested_cyberware_id`, `requested_surgery_id` | the job itself | yes | 2 · REQUESTED PROCEDURE (REPORTED / ON FILE) |
| implant `install_difficulty`, `neural_load`, `failure_risk`, tool requirements | difficulty, odds, complications, whether you can begin | yes (file, plan) | 2 · and 3 · (failure risk) |
| `existing_cyberware` | neural load, diagnosis options | yes (file) | 4 · INSTALLED CHROME (ON FILE); same-slot chrome in 2 · |
| `revealed_conditions` (+ their `modifiers`) | bleeding, sedation, neural sync, health drain, complications, post-op, neural load | as names only | 3 · one CONFIRMED card each with its effect; 4 · FINDING |
| `hidden_conditions` (not yet revealed) | the same, once applied | **no** (found by the body scan) | **never named or counted**; 4 · HIDDEN CONDITIONS: UNKNOWN |
| `true_diagnosis_id`, `scan_findings` | the scan and diagnosis | **no** until the scan | **not shown**; 4 · DIAGNOSIS: UNKNOWN |
| `neural_stability` | the starting neural vital | yes (file) | 3 · when below the file's 70 % threshold (CONFIRMED) |
| projected neural load (doctor-visible) | complication chance, neural drain, consent | yes (file: NOW / AFTER) | 3 · by the existing bands (CONFIRMED) |
| `get_risk_level()` (coarse 1–3) | (summary of hidden multipliers) | yes ("OVERALL") | 3 · SUSPECTED: "cause not identified" |
| `is_emergency` | bleeding ×1.4, complications ×1.3, a clock | yes | 3 · CRITICAL |
| `patience` | pay cut when running over time; comeback chance after deferring | yes (bar) | 1 · PATIENCE with both effects |
| `age` < 18 | staff with the no-minors ethic refuse | yes ("MINOR") | 1 · CAUTION |
| `faction_id`, `backer` | faction standing, who pays | yes | 1 · AFFILIATION, PAID FOR BY |
| `dependency` | lowers neural stability; care options | yes | 4 · ON FILE, CAUTION |
| debts (`PeopleManager.owed_by`), past operations | payment, history | yes | 1 · OWES, 4 · LAST JOB HERE |
| readiness `accepts` (consent rule) | whether you can begin | yes (plan) | 3 · CONSENT |
| `medical_history` (one line, e.g. "Allergic to polymer sealant") | **nothing**: display only | yes | 4 · PATIENT HISTORY: REPORTED, never flagged |
| `dialogue` (statement) | nothing | yes | 4 · STATEMENT: REPORTED, styled as flavor |
| bleed / pain / neural-sensitivity / complication / health-drain multipliers (rolled per patient) | the operation | **no, by design** (no way to discover them) | **not shown** (only their sum shows, through the existing SUSPECTED rating) |
| `street_rep`, `wealth`, `personality`, `traits`, appearance | not the procedure (traits affect haggling, shown in the file) | yes (file) | left in the full file |

## How the form distinguishes sources

| Label | Meaning | Comes from |
|---|---|---|
| REPORTED | the patient says so | statement, history line, who they are, what they want |
| ON FILE | the clinic's records | installed chrome, past jobs here, debts, dependency, the procedure's data |
| CONFIRMED | examined or measured | `revealed_conditions`, measured stability, patience, visible neural load, emergency, consent rule |
| SUSPECTED | indicated, cause not identified | the existing coarse risk rating |
| UNKNOWN | not known yet | hidden conditions, the diagnosis (until the scan) |

Emphasis uses existing classifications only:
- **Neural load:** the bands (minor = CAUTION, instability = SIGNIFICANT,
  severe or critical = CRITICAL).
- **Overall risk:** the 1–3 rating (medium = CAUTION, high = SIGNIFICANT).
- **Missing instruments:** they block the operation, so SIGNIFICANT.
- **Emergency:** CRITICAL.
- **Conditions:** no severity exists in the data, so each is a CAUTION with
  its effect in words.

Nothing is scored. Every level has a mark and a word, not just a colour.

## Visibility boundary (preserved, and tightened in the summary)

- **Hidden conditions:** unrevealed ones are never named or counted; the form
  says the scan can find some.
- **Scan findings:** pre-generated findings, which hint at the diagnosis, are
  not shown.
- **Neural load:** uses `NeuralLoad.projected_visible` (new helper: the same
  formula as `projected`, from `compute_visible`).
- **The 3.7 summary leaked hidden conditions in three places**, all now closed:
  - a "neural load after" line from the true load (now on the form, visible
    figure);
  - "may hide conditions" shown only when the patient really had one (now:
    "hidden conditions not screened yet", whenever they're possible at this
    stage and nothing was scanned);
  - `Recommend` used the true load and complication risk. It now counts only
    revealed conditions. `Recommend` is used only by screens: the surgery's
    real roll (`SurgeryManager.get_extra_complication_chance`) is unchanged.
- **Overall risk rating (existing, unchanged):** `get_risk_level()` is
  computed from the patient's full multipliers, as it was before 3.8. The
  form shows it as SUSPECTED, "cause not identified", which is all it reveals.

- CONSENT ("won't accept the unit") is the game's own consent rule
  (`GameManager.customer_accepts`). The operation plan already applies and
  shows it before BEGIN; the form only surfaces it earlier.

## Gameplay unchanged

Files changed: `scripts/components/intake_form.gd` (new),
`scripts/ui/intake_record.gd` (new), `scripts/components/patient_summary.gd`
(layout), `scripts/ui/patient_brief.gd` and `scripts/ui/recommend.gd`
(display estimates only), `scripts/core/neural_load.gd` (one new read-only
helper), `scripts/components/side_nav.gd` (labels clip), tests.

Untouched: the patient generator, CustomerManager, SurgeryManager, the
scoring, GameManager, the economy and every data file.

`tests/intake_tests.gd` checks that building the form leaves the patient's
saved state, the generator's RNG state, the odds, the fee, the complication
estimate and your money exactly as they were, and reveals nothing.
