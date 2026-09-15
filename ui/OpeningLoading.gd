extends Control
## Identidade do estúdio entre o fade do menu e a CGI.
var shown_progress := 1.0
var stage: Label
var recovery: Button
var elapsed := 0.0
var card: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	card = preload("res://cutscenes/opening/scripts/rcm_studio_card.gd").new()
	add_child(card)
	stage = Label.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	stage.position = Vector2(40, get_viewport_rect().size.y - 110)
	add_child(stage)
	recovery = Button.new()
	recovery.text = "Back" if TranslationServer.get_locale().begins_with("en") else "Voltar"
	recovery.position = Vector2(40, get_viewport_rect().size.y - 60)
	recovery.hide()
	add_child(recovery)

func _process(delta: float) -> void:
	elapsed += delta
	# A logo surge depois do menu escurecer. GameLoading limita sua duração.
	card.elapsed = clampf(elapsed - 0.9, 0.0, 1.8)
	card.queue_redraw()

func set_stage(_value: float, _message: String) -> void:
	pass
