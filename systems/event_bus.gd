extends Node
## Global, cross-cutting game events. Systems emit here so UI and other systems
## can react without holding direct references to each other.
## Surgery-specific, high-frequency events live on SurgeryManager instead.

signal money_changed(amount: int, delta: int)
signal reputation_changed(value: int, delta: int)
signal xp_changed(total_xp: int, level: int)
signal level_up(new_level: int)
signal inventory_changed()
signal cyberware_unlocked(cyberware_id: StringName)
signal customer_arrived(customer: CustomerData)
signal customer_left(customer: CustomerData)
signal surgery_rewarded(result: SurgeryResult)
signal game_saved()
signal game_loaded()
signal new_game_started()
signal screen_changed(screen_id: StringName)
