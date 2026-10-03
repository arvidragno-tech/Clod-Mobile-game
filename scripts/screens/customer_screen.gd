extends BaseScreen
## Customer intake: who they are, what they want, what they pay.

const CHARS_PER_SEC := 60.0
const RISK_LABELS := ["", "LOW", "MEDIUM", "HIGH"]
const RISK_COLORS: Array[Color] = [Palette.TEXT, Palette.OK, Palette.WARN, Palette.DANGER]

@onready var _back: Button = %BackButton
@onready var _portrait: TextureRect = %Portrait
@onready var _name: Label = %CustomerName
@onready var _alias: Label = %Alias
@onready var _bio: Label = %Bio
@onready var _dialogue: Label = %Dialogue
@onready var _dialogue_card: Control = %DialogueCard
@onready var _procedure: Label = %Procedure
@onready var _implant: Label = %Implant
@onready var _offer: Label = %Offer
@onready var _risk: Label = %Risk
@onready var _decline: Button = %DeclineButton
@onready var _accept: Button = %AcceptButton

var _type_tween: Tween


func on_enter(_params: Dictionary) -> void:
	var c := GameManager.get_current_customer()
	if c == null:
		UIManager.go_to.call_deferred(UIManager.SCREEN_CLINIC)
		return
	var surgery := GameManager.get_current_surgery()
	var item := CyberwareManager.get_cyberware(surgery.cyberware_id)
	_portrait.texture = load(c.portrait_path) as Texture2D if ResourceLoader.exists(c.portrait_path) else null
	_name.text = c.display_name
	_alias.text = "\"%s\"" % c.alias
	_bio.text = "%d yrs · %s" % [c.age, c.occupation]
	_procedure.text = surgery.display_name
	_implant.text = "%s (%s)" % [item.display_name, item.manufacturer] if item else "?"
	_offer.text = "~%s" % EconomyManager.format_money(int(round(surgery.base_pay * c.pay_multiplier)))
	var risk := c.get_risk_level()
	_risk.text = RISK_LABELS[risk]
	_risk.add_theme_color_override(&"font_color", RISK_COLORS[risk])
	_dialogue.text = c.dialogue
	_dialogue.visible_ratio = 0.0
	_type_tween = create_tween()
	_type_tween.tween_property(_dialogue, "visible_ratio", 1.0, c.dialogue.length() / CHARS_PER_SEC)
	_dialogue_card.gui_input.connect(_on_dialogue_input)
	_back.pressed.connect(GameManager.go_to_clinic)
	_decline.pressed.connect(_on_decline)
	_accept.pressed.connect(GameManager.accept_customer)


func _on_dialogue_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and _type_tween and _type_tween.is_running():
		_type_tween.kill()
		_dialogue.visible_ratio = 1.0


func _on_decline() -> void:
	UIManager.confirm("TURN THEM AWAY?", "Word gets around. Declining costs %d rep." % absi(GameConfig.DECLINE_REPUTATION_PENALTY),
			"DECLINE", GameManager.decline_customer, true)
