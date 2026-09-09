extends Node
## Context adapter with session-only hint history.
var presenter: TutorialHintPresenter
var elapsed := 0.0
var combat_cooldown := 0.0
var previous_health := -1
func _ready() -> void:
	add_to_group("gameplay_tutorials")
	process_mode = Node.PROCESS_MODE_ALWAYS
	presenter = preload("res://ui/tutorial_preview/TutorialHintPresenter.gd").new()
	add_child(presenter)
	presenter.layer = 28
	presenter._box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	presenter._box.offset_left = -404
	presenter._box.offset_right = -24
	presenter._box.offset_top = -160
	presenter._box.offset_bottom = -24
func request_context(id: String) -> void:
	if id in ["first_trunk","loadout_capacity"]:
		var actor := get_tree().get_first_node_in_group("player")
		if actor == null or not actor.personal_loadout_enabled: return
	_refresh_context()
	presenter.request_hint(id)
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.2: return
	combat_cooldown = maxf(0,combat_cooldown-elapsed)
	elapsed = 0
	_refresh_context()
func _refresh_context() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return
	var health := int(player.get("health"))
	if previous_health >= 0 and health < previous_health: combat_cooldown = 5
	previous_health = health
	if float(player.get("fire_cooldown")) > 0: combat_cooldown = 5
	var modal := get_tree().paused or bool(player.get("is_in_dialogue")) or bool(player.get("is_control_disabled")) or bool(player.get("is_dead"))
	var mission := get_parent().get_node_or_null("ArrivalMission")
	var hud := get_parent().get_node_or_null("HUD")
	if hud != null and hud.get("vehicle_name_label") != null:
		modal = modal or hud.vehicle_name_label.visible
	var personal := get_tree().get_first_node_in_group("personal_car_manager")
	if personal != null and personal.panel != null: modal = modal or personal.panel.visible
	if mission != null:
		modal = modal or mission._is_any_interior_modal_open()
		var board: Node = mission.garage.get("mission_board")
		if board != null: modal = modal or bool(board.get("is_ui_open"))
	var car: Node2D = get_node("/root/RegionTravel").controlled_car()
	# Set an aggregate guard first so sequential updates cannot briefly release a queued hint.
	presenter.set_modal_active(true)
	presenter.set_combat_active(combat_cooldown > 0)
	presenter.set_fast_driving_active(car != null and car.velocity.length() > 180)
	presenter.set_modal_active(modal)
	presenter.set_locale("en" if TranslationServer.get_locale().begins_with("en") else "pt")
	if modal: return
	var wanted := get_node("/root/WantedManager")
	if player.has_meta("police_exterior_position") and wanted.current_stars > 0:
		presenter.request_hint("police_search")
	var stream := get_parent().get_node_or_null("ContinuousWorld")
	if stream == null or not stream.ready_for_crossing or stream.current_region != "mountain": return
	var mountain: Node2D = stream.mountain
	var cold: Node = mountain.cold_controller
	if cold.current_temperature < 65 and not cold.sheltered:
		presenter.request_hint("cold_shelter")
	var pos: Vector2 = mountain.to_local(player.global_position)
	if not player.mountain_thermal_coat and pos.distance_to(Vector2(5980,530)) < 220:
		presenter.request_hint("thermal_shop")
	if mountain.tunnel.contains_actor(player): presenter.request_hint("tunnel")
