extends Node
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BOARDING_PRESENTATION := preload("res://gameplay/VehicleBoardingPresentation.gd")
var world
var car: CharacterBody3D
var occupied := false
var transition: Node
var prompt: Label
var speed_label: Label
var instructions: Label
var status := ""
var status_time := 0.0
var interface_clock := 0.0
var exit_capsule := CapsuleShape3D.new()
var _player_layer := 2
var _player_mask := 7
var _last_vehicle_position := Vector3.ZERO

func _ready() -> void:
	car = VEHICLE.new()
	if is_instance_valid(world.production): car.archetype = str(world.production.starting_vehicle().get("archetype","sport_coupe"))
	car.name = "PlayerCoupe"
	car.position = Vector3(-4.25,0.04,9)
	world.add_child(car)
	_watch_car(car)
	exit_capsule.radius = 0.32
	exit_capsule.height = 1.72
	prompt = Label.new()
	prompt.position = Vector2(26,626)
	prompt.add_theme_font_size_override("font_size",20)
	world.hud.add_child(prompt)
	speed_label = Label.new()
	speed_label.position = Vector2(1100,620)
	speed_label.add_theme_font_size_override("font_size",28)
	world.hud.add_child(speed_label)
	instructions = world.hud.get_node("Help")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("exit_vehicle" if occupied else "vehicle_interact"):
		if _external_transition_blocked():
			get_viewport().set_input_as_handled()
			return
		interact()

func _external_transition_blocked() -> bool:
	return is_instance_valid(world) and is_instance_valid(world.get("session")) and world.session.has_method("blocks_driving_change") and world.session.blocks_driving_change()

func is_body_transition_active() -> bool:
	return is_instance_valid(transition) or _jacking

func _player_alive() -> bool:
	return not is_instance_valid(world.get("gameplay")) or float(world.gameplay.get("health")) > 0

func _entry_option(allow_transition := false) -> Dictionary:
	if is_body_transition_active() or (not allow_transition and _external_transition_blocked()): return {}
	if occupied or world.player.input_locked: return {}
	var candidate: CharacterBody3D = car if is_instance_valid(car) else null
	if not "--sandbox" in OS.get_cmdline_user_args():
		candidate = null
		var distance := 5.0
		for possible in get_tree().get_nodes_in_group("drivable"):
			if not possible is CharacterBody3D or not possible.is_visible_in_tree() or possible.collision_layer == 0 or possible.has_meta("awaiting_ground"): continue
			if possible.health <= 0 or not _speed_allows_entry(possible): continue
			var separation: float = possible.global_position.distance_to(world.player.position)
			if separation < distance:
				candidate = possible
				distance = separation
	if not is_instance_valid(candidate) or not _speed_allows_entry(candidate) or candidate.health <= 0: return {}
	var reach := JACK_DOOR_REACH if absf(candidate.speed) > .5 else 1.8
	for side in (candidate.boarding_sides() if candidate.has_method("boarding_sides") else [-1,1]):
		var door: Vector3 = candidate.driver_door_anchor(side) if candidate.has_method("driver_door_anchor") else candidate.to_global(Vector3(side*(candidate.half_width+.51),0,0.15))
		if world.player.position.distance_to(door) > reach: continue
		var ray := PhysicsRayQueryParameters3D.create(world.player.position+Vector3.UP*.9,door+Vector3.UP*.9,7,[world.player.get_rid(),candidate.get_rid()])
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return {"car":candidate,"side":side,"door":door}
	return {}

## Roubo em movimento, como no GTA: carro ou moto do trânsito andando até
## JACK_MAX_SPEED pode ser agarrado pela porta. Carro parado continua igual; viatura
## em serviço e carro do jogador só parados.
const JACK_MAX_SPEED := 11.0 # ~40 km/h
const JACK_DOOR_REACH := 2.8 # a porta passa rápido: alcance maior que o 1,8 m parado
const JACK_STOP_SECONDS := .4
var _jacking := false
var _jack_generation := 0

func _speed_allows_entry(candidate: CharacterBody3D) -> bool:
	if absf(candidate.speed) <= .5: return true
	return candidate.traffic and not candidate.get_meta("dispatch_unit",false) and absf(candidate.speed) <= JACK_MAX_SPEED

func can_enter(allow_transition := false) -> bool:
	return not _entry_option(allow_transition).is_empty()

func interact(allow_transition := false) -> bool:
	if get_tree().paused: return false
	if is_body_transition_active(): return _reverse_entry_to_exit()
	if not allow_transition and _external_transition_blocked(): return false
	if world.player.input_locked: return false
	if occupied: return leave()
	var option := _entry_option(allow_transition)
	if option.is_empty(): return false
	# Viatura trancada do pátio da delegacia: a porta só abre pelo lockpick do dono.
	var lock_handler: Callable = option.car.get_meta("lockpick_handler", Callable())
	if lock_handler.is_valid(): return bool(lock_handler.call(option.car))
	return _begin_entry(option.car,int(option.side))

func _begin_entry(candidate: CharacterBody3D, side: int) -> bool:
	var dispatch_car := bool(candidate.get_meta("dispatch_unit",false))
	if dispatch_car:
		if not is_instance_valid(world.get("dispatch")) or not world.dispatch.vehicle_stolen(candidate,side): return false
	car = candidate
	_watch_car(car)
	_last_vehicle_position = car.global_position
	occupied = true
	# A crash temporarily suspends traffic. Its pending recovery still belongs
	# to the NPC until theft transfers ownership, otherwise it resumes mid-entry.
	if (car.traffic or car.get_meta("crash_was_traffic", false)) and not dispatch_car:
		car.traffic = false
		car.remove_meta("crash_was_traffic")
		# It is now a persistent player vehicle, including after dismounting.
		car.remove_meta("ambient_traffic")
		if world.get("gameplay") != null: world.gameplay.register_crime(15,car.global_position)
		_eject_civilian_driver(car,side)
	car.controlled = false
	car.external_input = false
	car.input_locked = true
	if is_instance_valid(world.production): car.ensure_equipment(world)
	car.brake_input = true
	car.throttle_input = 0
	_player_layer = world.player.collision_layer
	_player_mask = world.player.collision_mask
	world.player.input_locked = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.show()
	if not world.camera.locked: world.camera.target = car
	if absf(car.speed) > .5:
		_grab_moving(side)
		return true
	_start_boarding(side)
	return true

## Jogador agarrado à porta enquanto o motorista freia; depois segue o roubo normal.
func _grab_moving(side: int) -> void:
	_jacking = true
	_jack_generation += 1
	var generation := _jack_generation
	var start_speed: float = car.speed
	var elapsed := 0.0
	while elapsed < JACK_STOP_SECONDS:
		await get_tree().physics_frame
		if generation != _jack_generation or not _jacking or not occupied: return
		if not is_instance_valid(car) or car.is_queued_for_deletion() or car.health <= 0 or not _player_alive():
			_jacking = false
			_force_detach("jack_failed")
			return
		elapsed += get_physics_process_delta_time()
		car.speed = lerpf(start_speed, 0.0, clampf(elapsed / JACK_STOP_SECONDS, 0.0, 1.0))
		var door: Vector3 = car.driver_door_anchor(side)
		world.player.global_position = door
	car.speed = 0.0
	_jacking = false
	_start_boarding(side)

func _start_boarding(side: int) -> void:
	car.stop_boarding_motion()
	transition = BOARDING_PRESENTATION.new()
	add_child(transition)
	transition.entered.connect(_complete_entry)
	transition.exited.connect(_complete_exit)
	transition.cancelled.connect(_transition_cancelled)
	transition.begin_entry(world,car,world.player,side)

## Carro de trânsito tem motorista. Antes o roubo só tirava o carro da faixa e ninguém
## saía dele. O motorista desce pela porta dele assim que o ladrão abre a do lado de
## lá (ou é empurrado para trás, se o ladrão veio pela mesma porta) e foge em pânico.
func _eject_civilian_driver(candidate: CharacterBody3D, thief_side: int) -> void:
	if not is_instance_valid(world.get("production")) or world.get("people") == null: return
	# O banco do motorista é o esquerdo; no ônibus ele sai pela porta de serviço.
	var driver_side := 1 if candidate.has_method("boarding_class") and candidate.boarding_class() == "bus" else -1
	var point: Vector3 = candidate.driver_door_anchor(driver_side)
	if driver_side == thief_side:
		point = candidate.to_global(candidate.to_local(point)+Vector3(float(driver_side)*.35,0,1.25))
	point.y = candidate.global_position.y+.08
	var civilian = preload("res://scripts/Actor.gd").new()
	civilian.identity = randi_range(0,10000)
	civilian.speed = randf_range(1.2,1.6)
	civilian.position = point
	civilian.route = PackedVector3Array([point,point+(point-candidate.global_position).normalized()*8.0])
	civilian.set_meta("region_id",candidate.get_meta("region_id",""))
	civilian.hide()
	world.add_child(civilian)
	civilian.add_collision_exception_with(candidate)
	world.people.append(civilian)
	# Aparece quando a porta dele abre, não antes do ladrão chegar ao carro.
	get_tree().create_timer(.35).timeout.connect(func():
		if not is_instance_valid(civilian): return
		civilian.show()
		if is_instance_valid(candidate) and candidate.has_method("animate_driver_door") and driver_side != thief_side:
			candidate.animate_driver_door(driver_side,true,.22)
			get_tree().create_timer(.9).timeout.connect(func():
				if is_instance_valid(candidate): candidate.animate_driver_door(driver_side,false,.3))
		var reactions = world.production.get("civilian_reactions")
		if is_instance_valid(reactions) and reactions.has_method("report_assault"): reactions.report_assault(civilian,world.player))

func _complete_entry() -> void:
	transition = null
	if not is_instance_valid(car) or car.is_queued_for_deletion() or car.health <= 0 or not _player_alive():
		_force_detach("invalid_entry")
		return
	car.controlled = true
	car.external_input = false
	car.input_locked = false
	car.brake_input = false
	world.player.input_locked = false
	world.player.hide()
	world.player.teleport(car.global_position)
	_update_mounted_player()

func exit_position() -> Vector3:
	if not is_instance_valid(car): return Vector3.INF
	for side in (car.boarding_sides() if car.has_method("boarding_sides") else [-1,1]):
		for offset in [car._cab_z() if car.has_method("_cab_z") else -clampf(car.half_length*.18,.30,.62),-1.1,1.1]:
			var point := car.to_global(Vector3(side*(car.half_width+.61),0,offset))
			point.y = car.position.y+.04
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = exit_capsule
			query.collision_mask = 7
			query.exclude = [world.player.get_rid()]
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*0.87)
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
			var start := car.to_global(Vector3(side*(car.half_width+.04),0,offset))
			start.y = point.y
			query.exclude = [world.player.get_rid(),car.get_rid()]
			query.transform.origin = start+Vector3.UP*0.87
			query.motion = point-start
			var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
			if sweep[0] < 1.0: continue
			var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.3,point-Vector3.UP*0.2,1)
			if world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty(): continue
			return point
	return Vector3.INF

func leave() -> bool:
	if is_body_transition_active(): return _reverse_entry_to_exit()
	if not occupied or not is_instance_valid(car): return false
	if _external_transition_blocked(): return false
	if car.input_locked:
		_message("Aguarde o serviço terminar")
		return false
	if absf(car.speed) > 0.5:
		_message("Pare a moto para sair" if car.archetype.begins_with("bike_") else "Pare o carro para sair")
		return false
	var point := exit_position()
	if not point.is_finite():
		_message("Saída bloqueada — afaste a moto" if car.archetype.begins_with("bike_") else "Saída bloqueada — afaste o carro")
		return false
	car.controlled = false
	car.external_input = false
	car.input_locked = true
	car.throttle_input = 0
	car.brake_input = true
	car.stop_boarding_motion()
	world.player.input_locked = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	var side := -1 if car.to_local(point).x < 0 else 1
	transition = BOARDING_PRESENTATION.new()
	add_child(transition)
	transition.entered.connect(_complete_entry)
	transition.exited.connect(_complete_exit)
	transition.cancelled.connect(_transition_cancelled)
	transition.begin_exit(world,car,world.player,point,side)
	if not world.camera.locked:
		world.camera.target = world.player
		world.camera.initialized = false
	return true

func _reverse_entry_to_exit() -> bool:
	if not occupied or not is_instance_valid(transition) or transition.exiting or not transition.reverse_entry_to_exit(): return false
	if not world.camera.locked:
		world.camera.target = world.player
		world.camera.initialized = false
	return true

func _complete_exit(point: Vector3) -> void:
	transition = null
	occupied = false
	if is_instance_valid(car):
		car.controlled = false
		car.external_input = false
		car.input_locked = false
		car.throttle_input = 0
		car.brake_input = false
	_restore_player_on_foot(point)

func _transition_cancelled(_reason: String, point: Vector3) -> void:
	transition = null
	occupied = false
	if is_instance_valid(car):
		car.controlled = false
		car.external_input = false
		car.input_locked = false
		car.throttle_input = 0
		car.brake_input = false
	_restore_player_on_foot(point)

func cancel_transition(reason := "cancelled") -> void:
	_jacking = false
	_jack_generation += 1
	if is_instance_valid(transition):
		transition.abort(reason)
		return
	if occupied: _force_detach(reason)

func _force_detach(_reason: String) -> void:
	_jacking = false
	_jack_generation += 1
	var point := _last_vehicle_position
	if is_instance_valid(car):
		_last_vehicle_position = car.global_position
		point = car.to_global(Vector3(-(car.half_width+.65),.04,-clampf(car.half_length*.18,.30,.62)))
		car.controlled = false
		car.external_input = false
		car.input_locked = false
		car.throttle_input = 0
		car.brake_input = false
	occupied = false
	transition = null
	_restore_player_on_foot(point)

func _restore_player_on_foot(point: Vector3) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player): return
	world.player.teleport(point)
	world.player.collision_layer = _player_layer if _player_layer != 0 else 2
	world.player.collision_mask = _player_mask if _player_mask != 0 else 7
	world.player.show()
	world.player.set_physics_process(_player_alive())
	world.player.input_locked = not _player_alive() or _external_transition_blocked()
	if not world.camera.locked:
		world.camera.target = world.player
		world.camera.initialized = false

func _watch_car(candidate: CharacterBody3D) -> void:
	if not is_instance_valid(candidate): return
	var callback := _on_car_tree_exiting.bind(candidate)
	if not candidate.tree_exiting.is_connected(callback): candidate.tree_exiting.connect(callback,CONNECT_ONE_SHOT)
	var blast := _on_car_destroyed.bind(candidate)
	if candidate.has_signal("destroyed") and not candidate.destroyed.is_connected(blast): candidate.destroyed.connect(blast)

## Quem está no carro tem a colisão desligada, então a esfera de `Gameplay.explode` não o
## encontrava e o jogador saía vivo da explosão. Aqui ele é jogado para fora e morre.
func _on_car_destroyed(candidate: CharacterBody3D) -> void:
	if candidate != car or not (occupied or is_body_transition_active()): return
	var gameplay = world.get("gameplay")
	cancel_transition("vehicle_destroyed")
	if is_instance_valid(gameplay) and gameplay.has_method("damage_player"):
		gameplay.damage_player(1000.0)

func _on_car_tree_exiting(candidate: CharacterBody3D) -> void:
	if candidate != car: return
	_last_vehicle_position = candidate.global_position
	if occupied or is_body_transition_active(): cancel_transition("vehicle_removed")
	# The persistence owner retires deliberate removals while this body is still
	# valid; teardown/reparenting can capture without ever reading a freed ref.
	if is_instance_valid(world.get("production")):
		world.production.release_player_vehicle()
	car = null

func _message(text: String) -> void:
	status = text
	status_time = 2.5

func _process(delta: float) -> void:
	if is_body_transition_active():
		if not is_instance_valid(car) or car.is_queued_for_deletion(): cancel_transition("vehicle_removed")
		elif not _player_alive(): cancel_transition("death")
		elif _external_transition_blocked() and not (is_instance_valid(world.get("session")) and world.session.has_method("allows_saved_driver_animation") and world.session.allows_saved_driver_animation()): cancel_transition("session_transition")
	status_time = maxf(0,status_time-delta)
	interface_clock += delta
	if interface_clock < 0.1: return
	interface_clock = 0
	instructions.visible = not world.player.input_locked
	var entry := {} if occupied else _entry_option()
	# Carro comum não mostra aviso ao chegar perto (pedido do usuário); só a viatura trancada avisa que exige arrombar.
	var entry_label := "F  Arrombar viatura" if entry.get("car") != null and entry.car.get_meta("police_locked", false) else ""
	var exit_label := "F  Sair da moto" if is_instance_valid(car) and car.archetype.begins_with("bike_") else "F  Sair do carro"
	prompt.text = status if status_time > 0 else ("" if _external_transition_blocked() or is_body_transition_active() else (exit_label if occupied else (entry_label if not entry.is_empty() else "")))
	speed_label.text = "%02d km/h" % roundi(absf(car.speed)*3.6) if occupied and is_instance_valid(car) else ""
	instructions.text = "W / S  acelerar / ré    A / D  virar    Espaço  frear    F  sair    Esc  pausa" if occupied else "WASD  mover    Shift  correr    E  interagir    F  carro    Z / C  girar    Esc  pausa"

func _physics_process(_delta: float) -> void:
	if occupied and not is_body_transition_active() and is_instance_valid(car):
		_last_vehicle_position = car.global_position
		world.player.position = car.position
		_update_mounted_player()

func _update_mounted_player() -> void:
	if not car.archetype.begins_with("bike_"): return
	world.player.global_position = car.driver_seat_anchor()
	world.player.visual.rotation.y = car.global_rotation.y
	world.player.pose_vehicle(1.0, 0.0, -1, 1.0, car.motorcycle_handholds())
	world.player.show()
