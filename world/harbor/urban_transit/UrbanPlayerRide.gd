extends CanvasLayer
## Player passenger state belongs to the service, so lane reparenting cannot end a ride.
var system: Node2D
var bus: CharacterBody2D
var actor: CharacterBody2D
var stop_requested := false
var panel: PanelContainer
var status: Label
var action: Button
var continue_button: Button
var steal_button: Button
var _saved := {}
var _last_safe_position := Vector2.ZERO
var _candidate: CharacterBody2D

func _ready() -> void:
	layer = 70
	add_to_group("urban_player_ride")
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -205
	panel.offset_right = 205
	panel.offset_top = -166
	panel.offset_bottom = -28
	panel.add_theme_stylebox_override("panel",preload("res://ui/GameStyle.gd").panel())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	panel.add_child(column)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
	action = Button.new()
	action.custom_minimum_size.y = 38
	action.pressed.connect(_activate)
	column.add_child(action)
	steal_button = Button.new()
	steal_button.text = "Roubar e dirigir · E"
	steal_button.pressed.connect(func():
		var person := get_tree().get_first_node_in_group("player") as CharacterBody2D
		var candidate := nearby_bus(person)
		if candidate != null: candidate.enter_vehicle(person)
	)
	column.add_child(steal_button)
	continue_button = Button.new()
	continue_button.text = "Continuar passeio"
	continue_button.pressed.connect(func(): stop_requested = false; _refresh())
	column.add_child(continue_button)
	preload("res://ui/GameStyle.gd").apply(panel)
	hide()

func nearby_bus(person: CharacterBody2D) -> CharacterBody2D:
	if not is_instance_valid(person) or not person.visible or person.is_control_disabled or person.is_in_dialogue or person.is_dead: return null
	if not system.operating: return null
	for vehicle in system.buses:
		if not is_instance_valid(vehicle) or vehicle.is_broken or vehicle.suspended or not vehicle.dwelling or vehicle.doors < 0.95: continue
		var stop: Node2D = system.stops[vehicle.current_stop]
		if stop.can_board_from(person.global_position):
			return vehicle
	return null

func board_nearby(person: CharacterBody2D) -> bool:
	var vehicle := nearby_bus(person)
	if vehicle == null: return false
	return board(vehicle,person)

func board(vehicle: CharacterBody2D, person: CharacterBody2D) -> bool:
	if is_instance_valid(actor) or nearby_bus(person) != vehicle: return false
	bus = vehicle
	actor = person
	_last_safe_position = actor.global_position
	_saved = {"layer":actor.collision_layer,"mask":actor.collision_mask,"physics":actor.is_physics_processing(),"disabled":actor.is_control_disabled,"visible":actor.visible,"interpolation":actor.physics_interpolation_mode}
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	actor.is_control_disabled = true
	actor.velocity = Vector2.ZERO
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.hide()
	actor.global_position = bus.global_position
	stop_requested = false
	_refresh()
	return true

func can_exit() -> bool:
	return is_instance_valid(bus) and bus.dwelling and bus.doors >= 0.95 and bus.velocity.length() < 1.0

func holds_stop(vehicle: Node2D) -> bool:
	return is_instance_valid(actor) and bus == vehicle and (stop_requested or not system.operating or vehicle.is_broken)

func _process(_delta: float) -> void:
	if is_instance_valid(actor):
		if not is_instance_valid(bus) or bus.is_broken or actor.is_dead or actor.is_arrested:
			_finish(_last_safe_position)
			return
		actor.global_position = bus.global_position
		if can_exit():
			_last_safe_position = system.stops[bus.current_stop].platform_exit()
		_refresh()
	else:
		if not _saved.is_empty(): _finish(_last_safe_position)
		var person := get_tree().get_first_node_in_group("player") as CharacterBody2D
		_candidate = nearby_bus(person)
		visible = _candidate != null
		if visible:
			status.text = "510 · " + system.stops[_candidate.current_stop].stop_name
			action.text = "Viajar como passageiro"
			action.disabled = false
			continue_button.hide()
			steal_button.show()
	panel.offset_top = panel.offset_bottom-panel.get_combined_minimum_size().y

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(actor) and event.is_action_pressed("interact") and not event.is_echo():
		_activate()
		get_viewport().set_input_as_handled()

func _activate() -> void:
	if not is_instance_valid(actor):
		board_nearby(get_tree().get_first_node_in_group("player") as CharacterBody2D)
	elif can_exit():
		exit_at_stop()
	else:
		stop_requested = true
		_refresh()

func _refresh() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(bus): return
	steal_button.hide()
	show()
	if can_exit():
		status.text = "510 · " + system.stops[bus.current_stop].stop_name
		action.text = "Sair do articulado · E"
		action.disabled = false
	else:
		status.text = "Próxima: " + system.stops[bus.next_stop].stop_name
		action.text = "Parada solicitada" if stop_requested else "Pedir próxima parada · E"
		action.disabled = stop_requested
	continue_button.visible = stop_requested and system.operating

func exit_at_stop() -> bool:
	if not is_instance_valid(actor) or not can_exit(): return false
	var stop: Node2D = system.stops[bus.current_stop]
	var position := _clear_exit(stop)
	if not position.is_finite():
		stop_requested = true
		status.text = "Aguarde a saída da plataforma liberar"
		return false
	_finish(position)
	return true

func _clear_exit(stop: Node2D) -> Vector2:
	# Query the player's actual body before returning control on the sidewalk.
	var shape := actor.get_node("Collision") as CollisionShape2D
	for offset in [Vector2(123,14),Vector2(100,8),Vector2(151,7)]:
		var point: Vector2 = stop.to_global(offset)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = Transform2D(actor.global_rotation,point)*shape.transform
		query.collision_mask = int(_saved.mask)
		query.exclude = [actor.get_rid()]
		if actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return point
	return Vector2.INF

func _finish(point: Vector2) -> void:
	if is_instance_valid(actor):
		actor.global_position = point
		actor.velocity = Vector2.ZERO
		actor.collision_layer = int(_saved.layer)
		actor.collision_mask = int(_saved.mask)
		actor.is_control_disabled = bool(_saved.disabled)
		actor.visible = bool(_saved.visible)
		actor.set_physics_process(bool(_saved.physics))
		actor.physics_interpolation_mode = int(_saved.interpolation)
		actor.reset_physics_interpolation()
	actor = null
	bus = null
	stop_requested = false
	_saved.clear()
	hide()

func _exit_tree() -> void:
	if is_instance_valid(actor): _finish(_last_safe_position)
