extends Node
## Clinics the player owns and works from (data/clinics.json) and the
## upgrades installed in each (data/clinic_upgrades.json).
##
## Seven purchasable clinics run from a back-alley room in the Sump to a
## decommissioned Lyra lab. The player can own several; one is the
## *active* clinic (where they operate, whose art and modifiers apply).
## Owned clinics cost rent and running costs every day (BusinessManager);
## staff can run the others (StaffManager).
##
## Compatibility: `tier` is the index of the active clinic and the old tier
## API (get_next_tier / upgrade / get_tier_data ...) means "the next clinic
## in the progression", so older screens and saves keep working.

const CATEGORIES: Array[StringName] = [&"surgery", &"diagnostics", &"security", &"black_market", &"staff", &"customer"]
const MAX_UPGRADE_LEVEL := 3
const SELL_BACK := 0.5

var tiers: Array[Dictionary] = []  # clinics, progression order
var upgrade_defs: Dictionary = {}  # category -> {name, icon, levels[]}
var overlays: Dictionary = {}  # "clinic/category/level" -> {path, x, y, fx}
var tier: int = 0  # active clinic index
var owned: Array[int] = [0]
## clinic id -> {category -> level}
var upgrades: Dictionary = {}


func _ready() -> void:
	for t: Variant in DataLoader.load_entries(GameConfig.DATA_CLINICS, "clinics"):
		tiers.append(t)
	var u: Variant = DataLoader.load_json(GameConfig.DATA_CLINIC_UPGRADES)
	upgrade_defs = u.get("categories", {}) if u is Dictionary else {}
	var o: Variant = DataLoader.load_json(GameConfig.DATA_CLINIC_OVERLAYS)
	overlays = o.get("overlays", {}) if o is Dictionary else {}
	reset_state()


func reset_state() -> void:
	tier = 0
	owned = [0]
	upgrades.clear()


# --- Clinics -----------------------------------------------------------------

func get_tier_data(t: int = -1) -> Dictionary:
	var i := tier if t < 0 else t
	return tiers[clampi(i, 0, tiers.size() - 1)] if not tiers.is_empty() else {}


func clinic_id(t: int = -1) -> String:
	return str(get_tier_data(t).get("id", ""))


func index_of(id: String) -> int:
	for i in tiers.size():
		if str(tiers[i]["id"]) == id:
			return i
	return -1


func get_tier_name() -> String:
	return str(get_tier_data().get("name", "Clinic"))


func owns(i: int) -> bool:
	return owned.has(i)


## The next clinic in the progression the player doesn't own yet (-1 = all).
func next_index() -> int:
	for i in tiers.size():
		if not owned.has(i):
			return i
	return -1


func is_max_tier() -> bool:
	return next_index() < 0


func get_next_tier() -> Dictionary:
	var n := next_index()
	return {} if n < 0 else get_tier_data(n)


## "" if clinic i can be bought, otherwise the reason.
func purchase_block_reason(i: int) -> String:
	if i < 0 or i >= tiers.size():
		return "No such clinic"
	if owned.has(i):
		return "Already owned"
	var n := get_tier_data(i)
	if ProgressionManager.level < int(n.get("min_level", 1)):
		return "Requires LV %d" % int(n["min_level"])
	if ReputationManager.reputation < int(n.get("min_reputation", 0)):
		return "Requires REP %d" % int(n["min_reputation"])
	if not WorldManager.is_district_unlocked(StringName(str(n.get("district", "")))):
		return "District locked"
	if not EconomyManager.can_afford(price(i)):
		return "Not enough credits"
	return ""


func get_upgrade_block_reason() -> String:
	var n := next_index()
	return "Fully upgraded" if n < 0 else purchase_block_reason(n)


func price(i: int) -> int:
	return int(get_tier_data(i).get("price", get_tier_data(i).get("cost", 0)))


## Buys clinic i (does not move in).
func buy(i: int) -> bool:
	if purchase_block_reason(i) != "":
		return false
	if not EconomyManager.spend(price(i), &"clinics"):
		return false
	owned.append(i)
	owned.sort()
	WorldManager.visit(StringName(str(get_tier_data(i).get("district", ""))))
	EventBus.clinic_purchased.emit(i)
	StoryManager.check()
	return true


## Moves the practice to an owned clinic.
func move_to(i: int) -> bool:
	if not owned.has(i) or i == tier:
		return false
	tier = i
	WorldManager.visit(StringName(str(get_tier_data(i).get("district", ""))))
	EventBus.clinic_upgraded.emit(tier)
	EventBus.modifiers_changed.emit()
	return true


## Old API: buy the next clinic in the progression and move in.
func upgrade() -> bool:
	var n := next_index()
	if n < 0 or not buy(n):
		return false
	move_to(n)
	return true


## Sells an owned clinic that isn't the active one (half the price back).
func sell(i: int) -> bool:
	if not owned.has(i) or i == tier or owned.size() <= 1:
		return false
	owned.erase(i)
	upgrades.erase(clinic_id(i))
	EconomyManager.add_money(int(price(i) * SELL_BACK), &"clinics")
	EventBus.clinic_purchased.emit(-1)
	return true


# --- Upgrades ------------------------------------------------------------------

func upgrade_level(cat: StringName, t: int = -1) -> int:
	return int(upgrades.get(clinic_id(t), {}).get(String(cat), 0))


func used_slots(t: int = -1) -> int:
	var n := 0
	for c: Variant in upgrades.get(clinic_id(t), {}):
		n += int(upgrades[clinic_id(t)][c])
	return n


func slots(t: int = -1) -> int:
	return int(get_tier_data(t).get("upgrade_slots", 3))


func upgrade_def(cat: StringName, level: int) -> Dictionary:
	var levels: Array = upgrade_defs.get(String(cat), {}).get("levels", [])
	return levels[level - 1] if level >= 1 and level <= levels.size() else {}


func category_name(cat: StringName) -> String:
	return str(upgrade_defs.get(String(cat), {}).get("name", String(cat).capitalize()))


## "" if the next level of `cat` can be installed in the active clinic.
func install_block_reason(cat: StringName) -> String:
	var lv := upgrade_level(cat) + 1
	if lv > MAX_UPGRADE_LEVEL:
		return "Maxed"
	var d := upgrade_def(cat, lv)
	if d.is_empty():
		return "Unavailable"
	if used_slots() >= slots():
		return "No free upgrade slots"
	if cat == &"black_market" and lv > int(get_tier_data().get("black_market_access", 0)):
		return "No Undermarket access at this address"
	if not EconomyManager.can_afford(int(d.get("cost", 0))):
		return "Not enough credits"
	return ""


func install(cat: StringName) -> bool:
	if install_block_reason(cat) != "":
		return false
	var lv := upgrade_level(cat) + 1
	if not EconomyManager.spend(int(upgrade_def(cat, lv).get("cost", 0)), &"upgrades"):
		return false
	var cid := clinic_id()
	if not upgrades.has(cid):
		upgrades[cid] = {}
	upgrades[cid][String(cat)] = lv
	EventBus.clinic_upgrade_installed.emit(cat, lv)
	StoryManager.check()
	EventBus.modifiers_changed.emit()
	return true


## Overlay sprites for the active clinic: [{path, x, y, fx}].
func get_overlays(t: int = -1) -> Array:
	var out: Array = []
	for cat in CATEGORIES:
		var lv := upgrade_level(cat, t)
		if lv > 0:
			var o: Dictionary = overlays.get("%s/%s/%d" % [clinic_id(t), cat, lv], {})
			if not o.is_empty():
				out.append(o)
	return out


# --- Stats ---------------------------------------------------------------------

func get_modifiers() -> Dictionary:
	var m: Dictionary = (get_tier_data().get("modifiers", {}) as Dictionary).duplicate()
	for cat in CATEGORIES:
		for lv in range(1, upgrade_level(cat) + 1):
			var mods: Dictionary = upgrade_def(cat, lv).get("modifiers", {})
			for k: Variant in mods:
				m[k] = float(m.get(k, 0.0)) + float(mods[k])
	return m


func _upgrade_sum(key: String, t: int = -1) -> int:
	var n := 0
	for cat in CATEGORIES:
		for lv in range(1, upgrade_level(cat, t) + 1):
			n += int(upgrade_def(cat, lv).get(key, 0))
	return n


func security_rating(t: int = -1) -> int:
	return int(get_tier_data(t).get("security", 1)) + _upgrade_sum("security", t)


func staff_capacity(t: int = -1) -> int:
	return int(get_tier_data(t).get("staff_capacity", 0)) + _upgrade_sum("staff_capacity", t)


func surgery_capacity(t: int = -1) -> int:
	return int(get_tier_data(t).get("surgery_capacity", 3)) + _upgrade_sum("surgery_capacity", t)


func upkeep(t: int = -1) -> int:
	return _upgrade_sum("upkeep", t)


## Daily costs for one owned clinic: {rent, operating, upkeep}.
func daily_costs(t: int = -1) -> Dictionary:
	var d := get_tier_data(t)
	return {"rent": int(d.get("rent", 0)), "operating": int(d.get("operating_cost", 0)), "upkeep": upkeep(t)}


func customer_pool() -> Dictionary:
	return WorldManager.get_district(StringName(str(get_tier_data().get("district", "")))).get("customers", {})


func get_max_cyberware_tier() -> int:
	return int(get_tier_data().get("max_cyberware_tier", 2))


func get_supplies_capacity() -> int:
	return int(get_tier_data().get("supplies_capacity", 12))


func get_background_path() -> String:
	return str(get_tier_data().get("background", ""))


func get_surgery_backdrop_level() -> int:
	return int(get_tier_data().get("surgery_backdrop", 0))


func district_id() -> StringName:
	return StringName(str(get_tier_data().get("district", "undercity")))


# --- Save --------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"tier": tier, "active": clinic_id(), "owned": owned.map(func(i: int) -> String: return clinic_id(i)),
		"upgrades": upgrades.duplicate(true)}


## Pre-v4 saves stored only a tier index 0..5 of six tiers.
const LEGACY_TIER_MAP := [0, 1, 2, 4, 5, 6]


static func migrate_legacy(data: Dictionary) -> Dictionary:
	if data.has("owned") or data.has("owned_idx"):
		return data
	var t := clampi(int(data.get("tier", 0)), 0, LEGACY_TIER_MAP.size() - 1)
	var idx: int = LEGACY_TIER_MAP[t]
	return {"tier": idx, "owned_idx": [idx] if idx == 0 else [0, idx], "upgrades": {}}


func load_save_data(data: Dictionary) -> void:
	reset_state()
	data = migrate_legacy(data)
	owned.clear()
	if data.has("owned_idx"):
		for i: Variant in data["owned_idx"]:
			owned.append(int(i))
	else:
		for id: Variant in data.get("owned", []):
			var i := index_of(str(id))
			if i >= 0 and not owned.has(i):
				owned.append(i)
	if owned.is_empty():
		owned.append(0)
	owned.sort()
	var active := index_of(str(data.get("active", ""))) if data.has("active") else int(data.get("tier", 0))
	tier = active if owned.has(active) else owned[0]
	var u: Dictionary = data.get("upgrades", {})
	for cid: Variant in u:
		if index_of(str(cid)) >= 0:
			var levels := {}
			for cat: Variant in u[cid]:
				if StringName(str(cat)) in CATEGORIES:
					levels[str(cat)] = clampi(int(u[cid][cat]), 0, MAX_UPGRADE_LEVEL)
			upgrades[str(cid)] = levels
	EventBus.modifiers_changed.emit()
