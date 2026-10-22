class_name SurgeryStageRegistry
extends RefCounted
## Maps SurgeryStageData.type to the interaction that implements it.
## New surgeries reuse these by referencing a type in data/surgeries.json.

const STAGE_TYPES := {
	&"anesthesia": preload("res://scripts/surgery/stages/anesthesia_stage.gd"),
	&"incision": preload("res://scripts/surgery/stages/incision_stage.gd"),
	&"expose": preload("res://scripts/surgery/stages/expose_stage.gd"),
	&"remove_tissue": preload("res://scripts/surgery/stages/remove_tissue_stage.gd"),
	&"install_implant": preload("res://scripts/surgery/stages/install_implant_stage.gd"),
	&"connect_interface": preload("res://scripts/surgery/stages/connect_interface_stage.gd"),
	&"calibrate": preload("res://scripts/surgery/stages/calibrate_stage.gd"),
	&"close_incision": preload("res://scripts/surgery/stages/close_incision_stage.gd"),
	&"anchor_drill": preload("res://scripts/surgery/stages/anchor_drill_stage.gd"),
	&"sequence": preload("res://scripts/surgery/stages/sequence_stage.gd"),
	&"hold_steady": preload("res://scripts/surgery/stages/hold_steady_stage.gd"),
}


static func create(type: StringName) -> SurgeryStage:
	var script: GDScript = STAGE_TYPES.get(type)
	if script == null:
		push_error("SurgeryStageRegistry: unknown stage type '%s'" % type)
		return null
	return script.new() as SurgeryStage
