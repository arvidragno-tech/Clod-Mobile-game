class_name GameConfig
extends RefCounted
## Central tuning / configuration values.
## Everything a designer may want to tweak lives here or in res://data/*.json,
## never as magic numbers inside scenes or systems.

# --- Meta --------------------------------------------------------------------
const GAME_TITLE := "UNDERCITY"
const GAME_SUBTITLE := "RIPPER"
## Credits, shown as a suffix: "320 cr".
const CURRENCY_SUFFIX := " cr"

# --- Data paths --------------------------------------------------------------
const DATA_CUSTOMERS := "res://data/customers.json"
const DATA_CYBERWARE := "res://data/cyberware.json"
const DATA_TOOLS := "res://data/tools.json"
const DATA_SURGERIES := "res://data/surgeries.json"
const DATA_COMPLICATIONS := "res://data/complications.json"

# --- Save --------------------------------------------------------------------
const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

# --- New game ----------------------------------------------------------------
const STARTING_MONEY := 300
const STARTING_REPUTATION := 0
const STARTING_IMPLANT_STOCK := {&"nx1_neural_bridge": 2}
const STARTING_UNLOCKED_CYBERWARE: Array[StringName] = [&"nx1_neural_bridge"]

# --- Progression -------------------------------------------------------------
const XP_BASE_TO_LEVEL := 100
const XP_GROWTH_PER_LEVEL := 60
const MAX_REPUTATION := 100
const MIN_REPUTATION := -100
const BLACK_MARKET_REPUTATION := 25

# --- Clinic ------------------------------------------------------------------
const CUSTOMER_ARRIVAL_DELAY_SEC := 1.2
const DECLINE_REPUTATION_PENALTY := -1
## Used when the clinic has no implant in stock and cannot afford one: the
## customer brings a salvaged unit, which performs worse.
const SALVAGED_IMPLANT_QUALITY := 0.8

# --- Surgery: vitals (all vitals are 0..100) --------------------------------
const VITAL_MAX := 100.0
const START_HEALTH := 100.0
const START_BLOOD_LOSS := 0.0
const START_PAIN := 35.0
const START_NEURAL := 100.0

## Bleed rate (blood loss %/sec) while the incision is open, before mistakes.
const OPEN_WOUND_BLEED_RATE := 0.12
## Bleed rate slowly returns to the open-wound baseline (clotting), per second.
const CLOT_RATE_PER_SEC := 0.05
const MAX_BLEED_RATE := 4.0
## Above this blood loss, health starts draining.
const BLOOD_LOSS_SAFE := 25.0
const HEALTH_DRAIN_PER_BLOOD := 0.045
## Pain drifts toward the sedation baseline at this rate (per second).
const PAIN_SETTLE_RATE := 6.0
const PAIN_SAFE := 55.0
const NEURAL_DRAIN_PER_PAIN := 0.06
const NEURAL_RECOVERY_PER_SEC := 0.15
## Warning thresholds: crossing these triggers warning feedback once.
const WARN_HEALTH := 40.0
const WARN_BLOOD_LOSS := 45.0
const WARN_PAIN := 70.0
const WARN_NEURAL := 40.0

## Effects applied per mistake type; scaled by mistake severity (0..1+).
## Keys: bleed_rate (+%/s), blood (instant %), pain, health, neural (deltas).
const MISTAKE_EFFECTS := {
	&"wrong_tool": {"pain": 4.0},
	&"cut_deviation": {"bleed_rate": 0.35, "blood": 2.0, "pain": 4.0},
	&"tissue_tear": {"bleed_rate": 0.3, "blood": 2.5, "pain": 8.0},
	&"nerve_burn": {"neural": -9.0, "pain": 10.0},
	&"implant_drop": {"pain": 5.0},
	&"misalignment": {"neural": -14.0, "pain": 6.0},
	&"wrong_connection": {"neural": -11.0, "pain": 6.0},
	&"poor_calibration": {"neural": -5.0},
	&"bad_stitch": {"bleed_rate": 0.2, "blood": 1.5, "pain": 5.0},
	&"underdose": {"pain_baseline": 18.0},
	&"overdose": {"health": -10.0, "neural": -10.0},
}

## Human-readable labels for mistakes (shown as floating text / in the log).
const MISTAKE_LABELS := {
	&"wrong_tool": "WRONG TOOL",
	&"cut_deviation": "OFF LINE",
	&"tissue_tear": "TISSUE TEAR",
	&"nerve_burn": "NERVE BURN",
	&"implant_drop": "DROPPED",
	&"misalignment": "MISALIGNED",
	&"wrong_connection": "BAD SPLICE",
	&"poor_calibration": "POOR SYNC",
	&"bad_stitch": "BAD STITCH",
	&"underdose": "UNDERDOSED",
	&"overdose": "OVERDOSED",
}

## Sedation dose -> pain baseline mapping.
const SEDATION_PAIN_BASELINE_MIN := 8.0
const SEDATION_PAIN_BASELINE_MAX := 40.0

# --- Surgery: quick actions (emergency buttons) ------------------------------
const QUICK_ACTIONS := {
	&"coag": {"label": "COAG", "cooldown": 7.0, "bleed_rate": -0.9, "blood": -3.0},
	&"sedate": {"label": "SEDATE", "cooldown": 7.0, "pain": -25.0, "pain_baseline": -6.0, "neural": -1.5},
	&"stabilize": {"label": "STABIL", "cooldown": 9.0, "neural": 8.0},
}

# --- Surgery: complications --------------------------------------------------
const GUARANTEED_COMPLICATIONS := 1
const EXTRA_COMPLICATION_BASE_CHANCE := 0.25
const WRONG_DIAGNOSIS_RISK_MULT := 1.6
const COMPLICATION_DELAY_RANGE := Vector2(1.5, 4.0)

# --- Surgery: pacing ---------------------------------------------------------
## Pause after a stage is cleared before the next one starts.
const STAGE_CLEAR_DELAY_SEC := 0.6
## Pause on the success / failure stamp before the results screen.
const RESULTS_DELAY_SEC := 1.8

# --- Surgery: scoring --------------------------------------------------------
const SCORE_WEIGHT_STAGES := 0.4
const SCORE_WEIGHT_HEALTH := 0.2
const SCORE_WEIGHT_NEURAL := 0.2
const SCORE_WEIGHT_IMPLANT := 0.2
const TIME_BONUS_MAX := 0.08
const TIME_PENALTY_MAX := 0.15
## Seconds over target for the full time penalty.
const TIME_PENALTY_SPAN_SEC := 120.0
const GRADE_THRESHOLDS := [[0.92, "S"], [0.8, "A"], [0.66, "B"], [0.5, "C"], [0.0, "D"]]
const GRADE_REPUTATION := {"S": 8, "A": 6, "B": 4, "C": 2, "D": 0, "F": -6}
const FAILED_XP_FRACTION := 0.25
const CORRECT_DIAGNOSIS_XP_BONUS := 0.2
const WRONG_DIAGNOSIS_PAY_MULT := 0.9

# --- UI ----------------------------------------------------------------------
## Minimum touch target in viewport units (360 units ≈ 390pt iPhone width).
const MIN_TOUCH := 48.0
const TOUCH_SLOP := 26.0
const SCREEN_FADE_OUT_SEC := 0.14
const SCREEN_FADE_IN_SEC := 0.2
const TOAST_DURATION_SEC := 2.2
const SHAKE_DURATION_SEC := 0.22
const HAPTICS_MS := 25
## Set to a non-zero inset to preview notch/home-indicator handling on desktop.
const DEBUG_SIMULATED_SAFE_AREA := Rect2(0, 0, 0, 0)
