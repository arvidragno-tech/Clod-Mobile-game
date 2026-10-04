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
const DATA_CHARACTERS := "res://data/characters.json"
const DATA_CLINIC_FX := "res://data/clinic_fx.json"
const DATA_ARCHETYPES := "res://data/archetypes.json"
const DATA_NAMES := "res://data/names.json"
const DATA_DIALOGUE := "res://data/dialogue.json"
const DATA_CONDITIONS := "res://data/conditions.json"
const DATA_FACTIONS := "res://data/factions.json"
const DATA_SKILLS := "res://data/skills.json"
const DATA_CLINICS := "res://data/clinics.json"
const DATA_CLINIC_UPGRADES := "res://data/clinic_upgrades.json"
const DATA_CLINIC_OVERLAYS := "res://data/clinic_overlays.json"
const DATA_DISTRICTS := "res://data/districts.json"
const DATA_EVENTS := "res://data/events.json"
const DATA_RUMORS := "res://data/rumors.json"
const DATA_BLACK_MARKET := "res://data/black_market.json"
const DATA_PALETTES := "res://data/palettes.json"
const DATA_CHARACTER_PARTS := "res://data/character_parts.json"
const DATA_CYBERWARE := "res://data/cyberware.json"
const DATA_TOOLS := "res://data/tools.json"
const DATA_SURGERIES := "res://data/surgeries.json"
const DATA_COMPLICATIONS := "res://data/complications.json"

# --- Save --------------------------------------------------------------------
## Legacy single-save path (pre-PC); migrated into slot 1 on first run.
const SAVE_PATH := "user://savegame.json"
## Save slots live in user://saves/ (%APPDATA%/UndercityRipper/saves on Windows).
const SAVE_DIR := "user://saves"
const SAVE_SLOTS := 3
const SAVE_VERSION := 4

# --- New game ----------------------------------------------------------------
const STARTING_MONEY := 300
const STARTING_REPUTATION := 0
const STARTING_IMPLANT_STOCK := {&"nx1_neural_bridge": 2, &"kestrel_sight": 1, &"kevlace_mesh": 1}
const STARTING_UNLOCKED_CYBERWARE: Array[StringName] = [&"nx1_neural_bridge"]
const STARTING_SUPPLIES := 8
const STARTING_PARTS := 2
const STARTING_TOKENS := 0
const STARTING_SKILL_POINTS := 1
const SKILL_POINTS_PER_LEVEL := 1

# --- Progression -------------------------------------------------------------
const XP_BASE_TO_LEVEL := 100
const XP_GROWTH_PER_LEVEL := 60
const MAX_REPUTATION := 100
const MIN_REPUTATION := -100
const BLACK_MARKET_REPUTATION := 25
## Player level needed for each cyberware tier (tier 5 = black market only).
const CYBERWARE_TIER_LEVEL := {1: 1, 2: 3, 3: 5, 4: 8, 5: 99}

# --- Clinic ------------------------------------------------------------------
const CUSTOMER_ARRIVAL_DELAY_SEC := 1.2
const DECLINE_REPUTATION_PENALTY := -1
## Used when the clinic has no implant in stock and cannot afford one: the
## customer brings a salvaged unit, which performs worse.
const SALVAGED_IMPLANT_QUALITY := 0.8
## Chance an event fires when returning to the clinic after an operation.
const EVENT_CHANCE := 0.4
const SUPPLY_PACK_SIZE := 5
const SUPPLY_PACK_PRICE := 70
## Penalty when operating without enough supplies.
const NO_SUPPLIES_MODIFIERS := {"complication.chance": 0.2, "surgery.bleed": 0.3}

# --- Factions / heat ----------------------------------------------------------
const FACTION_STANDINGS := [[-50, "HOSTILE"], [-15, "UNFRIENDLY"], [15, "NEUTRAL"], [40, "FRIENDLY"], [101, "ALLIED"]]
const FACTION_REP_SUCCESS := 4
const FACTION_REP_FAILURE := -8
const FACTION_REP_DEATH := -14
const HEAT_DECAY_PER_OP := 3.0
const HEAT_PER_BM_INSTALL := 6.0
const HEAT_PER_DEATH := 10.0
const MAX_HEAT := 100.0

# --- Customer consequences -------------------------------------------------------
const REFERRAL_CHANCE := 0.3
const RETURN_CHANCE := 0.25
const RETURN_DELAY_OPS := Vector2i(2, 5)
const REGULAR_VISITS := 3
const REGULAR_PAY_BONUS := 0.1
const COMPLAINT_CHANCE := 0.5
const SUBSTITUTE_PAY_MULT := 0.85
## Share of (post-learning) customers whose job the clinic can already do.
const FEASIBLE_REQUEST_SHARE := 0.8
## Post-op complication chance by grade, added to the patient's hidden
## post-op risk (conditions) and the post_op.risk modifier.
const POST_OP_RISK_BY_GRADE := {"S": 0.0, "A": 0.02, "B": 0.05, "C": 0.12, "D": 0.2}

## Risk tolerance a customer needs to consent when the projected neural load
## lands in the severe (85-95) / critical (95+) band.
const CONSENT_RISK_SEVERE := 0.45
const CONSENT_RISK_CRITICAL := 0.75

# --- Cyberware ----------------------------------------------------------------
## Tolerance divisor per install-difficulty step above 1.
const DIFFICULTY_TOLERANCE_STEP := 0.12
## Extra complication risk for a fully worn (0% condition) implant.
const WORN_IMPLANT_RISK := 0.15
## Install pay markup on the implant's price.
const IMPLANT_PRICE_MARKUP := 0.45

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
	&"bone_crack": {"health": -7.0, "pain": 14.0, "bleed_rate": 0.25},
	&"loose_anchor": {"pain": 4.0},
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
	&"bone_crack": "BONE CRACK",
	&"loose_anchor": "LOOSE ANCHOR",
	&"overdose": "OVERDOSED",
}

## Mistakes that read as MAJOR (red). Everything else is MINOR (amber)
## unless its severity is >= MAJOR_SEVERITY.
const MAJOR_MISTAKES: Array[StringName] = [&"tissue_tear", &"nerve_burn", &"implant_drop", &"wrong_connection", &"bone_crack", &"overdose"]
const MAJOR_SEVERITY := 1.3

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
## If a stage is cleared before its complication fired, it fires this soon
## into the next stage instead.
const COMPLICATION_CARRY_OVER_SEC := 1.0
const COMPLICATION_FINAL_STAGE_SEC := 0.2

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
const GRADE_REPUTATION := {"S": 6, "A": 5, "B": 3, "C": 2, "D": 1, "F": -5}
const FAILED_XP_FRACTION := 0.25
const CORRECT_DIAGNOSIS_XP_BONUS := 0.2
const WRONG_DIAGNOSIS_PAY_MULT := 0.9

# --- UI ----------------------------------------------------------------------
## Viewport units per art pixel. Every sprite, background and the surgical
## field render at exactly this scale (see docs/ART_BIBLE.md).
const PIXEL_SCALE := 3
## Minimum height of a clickable control at the 1920x1080 design size.
const MIN_CONTROL := 40.0
## Extra forgiveness (UI units) around small click targets.
const CLICK_SLOP := 14.0
## Text sizes from older layout code are multiplied by this for 1080p.
const TEXT_SCALE := 1.4
const SCREEN_FADE_OUT_SEC := 0.14
const SCREEN_FADE_IN_SEC := 0.2
const MAX_TOASTS := 2
const TOAST_DURATION_SEC := 2.2
const SHAKE_DURATION_SEC := 0.22
