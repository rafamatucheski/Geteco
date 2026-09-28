extends Node
## Owns the Vicente dossier modal without putting quest documents in the
## droppable inventory grid. FullSession remains the modal/save authority.

const PANEL := preload("res://ui/SecretFilePanel.gd")
var session
var progression: RefCounted
var ui: Control
var _closing := false

func configure(owner_session, state: RefCounted) -> void:
	session = owner_session
	progression = state
	ui = PANEL.new()
	var host: Node = session.world.hud if is_instance_valid(session.world.hud) else session
	host.add_child(ui)
	ui.configure(progression)
	ui.closed.connect(_panel_requested_close)
	ui.audio_toggled.connect(_audio_toggled)
	ui.route_selected.connect(_route_selected)

func available() -> bool:
	return progression != null and bool(progression.snapshot().get("dossier_received",false))

func is_open() -> bool:
	return is_instance_valid(ui) and ui.visible

func open() -> bool:
	if not available() or session.modal or session.is_transition_blocked() or session.world.gameplay.health<=0: return false
	session._menu("Arquivo de Vicente")
	session.panel.hide()
	session.menu_closed = dismiss
	if not ui.open(progression):
		session.close_menu()
		return false
	return true

func open_from_journal() -> void:
	if not available(): return
	if session.modal: session.close_menu()
	call_deferred("open")

func close() -> void:
	if _closing or not session.modal: return
	_closing = true
	session.close_menu()
	_closing = false

func dismiss() -> void:
	if is_instance_valid(ui) and ui.visible: ui.close()

func refresh() -> void:
	if is_instance_valid(ui): ui.refresh(progression)

func _panel_requested_close() -> void:
	if not _closing: close()

func _audio_toggled(id: String, playing: bool) -> void:
	# Audio records receive authored streams later. Keep the state honest: the
	# UI never pretends a missing recording is playing.
	if playing:
		ui.set_audio_playing(id,false)
		session.show_message("A gravação está danificada.")

func _route_selected(id: String) -> void:
	if progression.has_route(id): session.show_message("Rota registrada na pasta.")
