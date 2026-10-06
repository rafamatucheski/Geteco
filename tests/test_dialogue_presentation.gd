extends SceneTree
## Dialogue surfaces retain readable bounds, live control hints and one advance.
const CARD := preload("res://ui/dialogue/DialogueCard.gd")
const CAPTION := preload("res://ui/dialogue/DialogueCaption.gd")
const LONG_LINE := "Se quiser descobrir por onde seu irmão passou, começa pelo porto. Eu conheço quem estava trabalhando naquela noite, mas a gente precisa conversar com calma antes de seguir. Guarda o nome de quem falar com você e volta aqui quando tiver uma pista."
var failures: Array[String] = []
var checks := 0
var advances := 0

class Controls extends Node:
	signal bindings_changed
	signal device_changed
	var binding := "E"
	func prompt(_action: String) -> String: return binding

func _initialize() -> void: run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for frame in 4: await process_frame

func run() -> void:
	var controls := Controls.new()
	root.add_child(controls)
	var card := CARD.new()
	root.add_child(card)
	card.advance_requested.connect(func(): advances += 1)
	card.configure("Maciota", LONG_LINE, controls)
	await settle()
	check(card.visible and card.speaker_label.text == "Maciota" and card.message.text == LONG_LINE, "conversation preserves complete speaker and line")
	check(card.binding_label.text == "E", "continue hint uses current controls")
	controls.binding = "F"
	controls.bindings_changed.emit()
	check(card.binding_label.text == "F", "rebinding updates visible continue hint")
	controls.binding = "A"
	controls.device_changed.emit()
	check(card.binding_label.text == "A", "device change updates visible continue hint")
	card.advance_button.pressed.emit()
	check(advances == 1, "one button activation requests one advance")
	card.focus_advance()
	check(card.advance_button.has_focus(), "conversation has a focusable continue action")
	for extent in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(800,600)]:
		root.content_scale_size = extent
		root.size = extent
		await settle()
		card.layout_for_viewport(Vector2(extent))
		await settle()
		var surface := card.get_global_rect()
		check(surface.position.x >= 18.0 and surface.end.x <= extent.x-18.0 and surface.position.y > 0 and surface.end.y <= extent.y-18.0, "dialogue stays inside safe bounds at %s" % extent)
		check(surface.size.y < extent.y*.6, "long conversation keeps the scene visible at %s" % extent)
		check(card.message.get_line_count() > 1 and card.message.visible_characters == -1, "long line wraps without truncation at %s" % extent)
	var short_height := card.size.y
	card.configure("Dante", "Entendi.", controls)
	await settle()
	check(card.size.y < short_height, "short reply releases unused vertical space")
	card.hide()
	card.configure("Dante", "Entendi.", controls)
	check(card.visible, "reopening the same conversation restores its surface")
	var caption := CAPTION.new()
	root.add_child(caption)
	caption.set_line("Voz ao telefone", "Seu irmão está em Harbor.")
	await settle()
	check(caption.text == "Voz ao telefone\nSeu irmão está em Harbor." and caption.visible, "caption exposes legacy text and displays spoken line")
	check(caption.mouse_filter == Control.MOUSE_FILTER_IGNORE and not caption.is_processing(), "caption does not take gameplay input or own a processing loop")
	caption.text = ""
	check(caption.text.is_empty() and not caption.visible, "silence clears the whole caption surface")
	caption.text = "DANTE\nTá certo."
	check(caption.speaker_label.text == "DANTE" and caption.message.text == "Tá certo.", "legacy subtitle assignment preserves identity and body")
	card.free()
	controls.bindings_changed.emit()
	controls.device_changed.emit()
	check(controls.get_signal_connection_list("bindings_changed").is_empty() and controls.get_signal_connection_list("device_changed").is_empty(), "disposed card releases control subscriptions")
	caption.free()
	controls.free()
	print("DIALOGUE_PRESENTATION checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
