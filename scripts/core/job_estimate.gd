class_name JobEstimate
extends RefCounted
## What a job is likely to earn, from real game data: the expected fee, what
## the patient can actually pay today (their budget; the rest is owed on an
## instalment plan), and what the job uses
## up (the implant: bought for it or its replacement value from stock; the
## medical supplies). One source for the customer file, the surgery
## preview, the door card and the economy simulator.
##
## Everything here is an estimate (the real fee depends on how the
## operation goes); the results screen shows the real numbers afterwards.

## {fee, can_pay, owed, implant_cost, implant_source, supplies, supplies_cost,
##  net, cash_net, covers_implant: bool}
static func for_customer(c: CustomerData, readiness: Dictionary = {}) -> Dictionary:
	var out := {"fee": 0, "can_pay": 0, "owed": 0, "implant_cost": 0, "implant_source": "", "supplies": 0,
		"supplies_cost": 0, "net": 0, "cash_net": 0, "covers_implant": true}
	if c == null:
		return out
	var fee := CustomerGenerator.estimate_fee(c)
	var planned: ImplantInstance = readiness.get("implant", null)
	if planned and planned.source == &"black_market":
		fee -= int(round(CustomerGenerator.estimate_part(c) * (1.0 - GameConfig.BLACK_MARKET_PART_SHARE)))
	var cast := c.character_id != &"" and CharacterManager.has_character(c.character_id)
	var can_pay := fee if (cast or c.budget <= 0) else mini(fee, c.budget)
	out["fee"] = fee
	out["can_pay"] = can_pay
	out["owed"] = fee - can_pay
	var item := CyberwareManager.get_cyberware(c.requested_cyberware_id)
	var src := str(readiness.get("implant_source", ""))
	if src == "":
		src = "stock" if item and InventoryManager.get_implant_count(item.id) > 0 else "buy"
	out["implant_source"] = src
	if item and src != "salvaged":
		var inst: ImplantInstance = readiness.get("implant", null)
		var data := CyberwareManager.get_cyberware(inst.cyberware_id) if inst else item
		out["implant_cost"] = InventoryManager.implant_price(data if data else item)
	var s := SurgeryManager.get_surgery(c.requested_surgery_id)
	var sup := s.supplies if s else 1
	out["supplies"] = sup
	out["supplies_cost"] = int(round(sup * GameManager.supply_unit_cost()))
	# Direct margin: the whole fee (what they can't pay today goes on an
	# instalment plan, PeopleManager.settle) minus what the job uses up.
	# Rent and wages are not per job, so they're not in here.
	out["net"] = fee - int(out["implant_cost"]) - int(out["supplies_cost"])
	# Cash today: a unit from stock is already paid for.
	out["cash_net"] = can_pay - (int(out["implant_cost"]) if src == "buy" else 0) - int(out["supplies_cost"])
	out["covers_implant"] = can_pay >= int(out["implant_cost"])
	return out
