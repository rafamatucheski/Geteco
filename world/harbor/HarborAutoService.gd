extends Node2D
## Drive-in service: proximity opens the shutter; parking inside starts repair.
const PRICE := 100
const SERVICE_SECONDS := 4.5
const EXIT_OFFSET := Vector2(0,-6)
var busy := false
var serviced_count := 0
var service_elapsed := 0.0
var phase := "idle"
var target: Node2D
var player: Node2D
var _saved := {}
var _clock := 0.0
var _departing: Node2D
var _motion: Tween
var _insufficient_notified := false
var _door_motion: Tween
var _door_open := false
var shutter: Polygon2D
var spray: CPUParticles2D
func _ready() -> void:
	add_to_group("auto_service")
	global_position = get_parent().get_node("NorthDistrict/MotorWorkshopApron").global_position
	player = get_parent().get_node("Player")
	z_index = 15
	var doorway := Polygon2D.new()
	doorway.polygon = PackedVector2Array([Vector2(-55,-104),Vector2(55,-104),Vector2(55,-58),Vector2(-55,-58)])
	doorway.color = Color("111c20")
	add_child(doorway)
	shutter = Polygon2D.new()
	shutter.polygon = PackedVector2Array([Vector2(-55,-104),Vector2(55,-104),Vector2(55,-58),Vector2(-55,-58)])
	shutter.color = Color("425a60")
	add_child(shutter)
	for y in range(-100,-57,6):
		var slat := Line2D.new()
		slat.points = PackedVector2Array([Vector2(-53,y),Vector2(53,y)])
		slat.width = 1
		slat.default_color = Color("81b1a4")
		shutter.add_child(slat)
	spray = CPUParticles2D.new()
	spray.position = Vector2(0,-65)
	spray.emitting = false
	spray.amount = 20
	spray.lifetime = 0.6
	spray.direction = Vector2.UP
	spray.spread = 75
	spray.gravity = Vector2.ZERO
	spray.initial_velocity_min = 12
	spray.initial_velocity_max = 28
	spray.scale_amount_min = 2
	spray.scale_amount_max = 4
	spray.color = Color(0.7,0.92,0.85,0.35)
	add_child(spray)
func eligible(car: Node2D) -> bool:
	return is_instance_valid(car) and car != _departing and not car.has_meta("vehicle_boarding") and car.has_method("repair_vehicle") and car.get("is_driven_by_player")==true and car.is_physics_processing() and car.velocity.length()<35 and Rect2(-20,-155,40,48).has_point(to_local(car.global_position)) and not player.is_control_disabled and not player.is_dead
func _process(delta: float) -> void:
	if busy:
		if not is_instance_valid(target) or player.is_dead or target.get("is_driven_by_player")!=true:
			_cancel()
			return
		player.global_position = target.global_position
		if target.get("body_model") != null:
			target.body_model.rotation.y = -target.global_rotation-PI/2
			if target.get("sprite") != null: target.sprite.global_rotation = 0
			if target.get("visual") != null: target.visual.global_rotation = 0
		if target.has_method("request_appearance_update"): target.request_appearance_update()
		elif target.has_method("_update_3d_orientation"): target._update_3d_orientation(delta)
		if phase == "repair": service_elapsed += delta
		return
	_clock -= delta
	if _clock>0: return
	_clock = 0.15
	if is_instance_valid(_departing) and _departing.global_position.distance_to(global_position + Vector2(0,-65))>210: _departing = null
	var car := get_node("/root/RegionTravel").controlled_car() as Node2D
	var visitor: Node2D = car if is_instance_valid(car) else player
	_set_open(is_instance_valid(visitor) and visitor.global_position.distance_to(global_position + Vector2(0,-65)) < 210)
	if eligible(car):
		if player.money < PRICE:
			if not _insufficient_notified:
				player._show_weapon_notice(_text("SERVIÇO: $100 / SALDO INSUFICIENTE","SERVICE: $100 / INSUFFICIENT FUNDS"))
				_insufficient_notified = true
		else: start_service(car)
	else:
		_insufficient_notified = false
func _set_open(value: bool) -> void:
	if _door_open == value: return
	_door_open = value
	if is_instance_valid(_door_motion): _door_motion.kill()
	_door_motion = create_tween()
	_door_motion.tween_property(shutter,"position:y",-48.0 if value else 0.0,0.35)

func _text(pt: String,en: String) -> String: return en if TranslationServer.get_locale().begins_with("en") else pt
func start_service(car: Node2D) -> bool:
	if busy or not eligible(car) or player.money < PRICE: return false
	busy = true
	target = car
	phase = "enter"
	service_elapsed = 0
	_saved = {"physics":car.is_physics_processing(),"layer":car.collision_layer,"mask":car.collision_mask,"modulate":car.modulate,"disabled":player.is_control_disabled,"paid":false}
	# Light2D ignores the body sprite fade and otherwise projects through the
	# facade. Disable emission without changing the driver's headlight setting.
	_saved["lights"] = []
	for light in car.find_children("", "Light2D", true, false):
		_saved.lights.append({"node":light,"enabled":light.enabled})
		light.enabled = false
	# Keep car and player from triggering any exterior entrance/interior transition
	# while the service is animating.
	player.set_meta("pay_n_spray_busy", true)
	car.set_meta("pay_n_spray_busy", true)
	car.set_meta("service_safe_position",global_position+EXIT_OFFSET)
	car.set_meta("service_safe_rotation",-PI/2)
	player.is_control_disabled = true
	car.set_physics_process(false)
	car.velocity = Vector2.ZERO
	for audio_name in ["engine_audio","skid_audio","spool"]:
		var audio = car.get(audio_name)
		if audio is AudioStreamPlayer2D: audio.stop()
	car.collision_layer = 0
	car.collision_mask = 0
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(_door_motion): _door_motion.kill()
	_door_open = false
	_motion.tween_property(shutter,"position:y",0.0,0.35)
	_motion.parallel().tween_property(car,"modulate:a",0.0,0.35)
	_motion.tween_callback(_begin_repair)
	_motion.tween_interval(SERVICE_SECONDS)
	_motion.tween_callback(_repair)
	_motion.tween_property(shutter,"position:y",-48.0,0.35)
	_motion.parallel().tween_property(car,"modulate:a",1.0,0.35)
	_motion.tween_callback(_finish)
	return true
func _begin_repair() -> void:
	phase = "repair"
	spray.emitting = true
	var sound := AudioStreamPlayer2D.new()
	sound.bus = &"SFX"
	sound.stream = ProceduralAudio.get_skid_stream()
	sound.pitch_scale = 1.8
	sound.volume_db = -24
	sound.max_distance = 350
	add_child(sound)
	sound.play()
	get_tree().create_timer(SERVICE_SECONDS).timeout.connect(sound.queue_free)
func _repair() -> void:
	if not is_instance_valid(target): return
	phase = "exit"
	spray.emitting = false
	player.money -= PRICE
	_saved.paid = true
	var punctured: bool = target.get("has_punctured_tires") == true
	var restored_speed: float = target.max_speed/0.45 if punctured else target.max_speed
	var restored_acceleration: float = target.acceleration/0.5 if punctured else target.acceleration
	var restored_turn: float = target.turn_speed/0.7 if punctured else target.turn_speed
	# Personal livery is never randomly recolored by a service.
	if target.is_in_group("personal_vehicle"):
		target.repair_vehicle()
		target.max_speed = 560
		target.acceleration = 460
		target.turn_speed = 3.1
		target.drift_factor = 0.88
	elif target.has_method("repair_and_repaint"):
		target.repair_and_repaint()
	else:
		target.repair_vehicle()
		if target.has_method("repaint_vehicle"): target.repaint_vehicle()
	if punctured and not target.is_in_group("personal_vehicle"):
		target.max_speed = restored_speed
		target.acceleration = restored_acceleration
		target.turn_speed = restored_turn
		target.drift_factor = float(VehicleCatalog.get_vehicle_spec(target.active_archetype_id).get("drift_factor",0.9))
	var wanted := get_node_or_null("/root/WantedManager")
	if is_instance_valid(wanted) and wanted.has_method("reset_crime"): wanted.reset_crime()
	player._refresh_weapon_ui()
func _release() -> void:
	for entry in _saved.get("lights", []):
		if is_instance_valid(entry.node): entry.node.enabled = entry.enabled
	if is_instance_valid(target):
		target.remove_meta("pay_n_spray_busy")
		target.modulate = _saved.get("modulate",Color.WHITE)
		target.collision_layer = _saved.get("layer",2)
		target.collision_mask = _saved.get("mask",1)
		target.set_physics_process(_saved.get("physics",true))
		target.velocity = Vector2.ZERO
		if "_drive_input_armed" in target: target._drive_input_armed = false
		target.remove_meta("service_safe_position")
		target.remove_meta("service_safe_rotation")
		if is_instance_valid(player) and not player.is_dead and target.get("is_driven_by_player")==true:
			player.global_position = target.global_position
		_departing = target
	if is_instance_valid(player): player.is_control_disabled = _saved.get("disabled",false)
	if is_instance_valid(player): player.remove_meta("pay_n_spray_busy")
	busy = false
	phase = "idle"
	spray.emitting = false
func _finish() -> void:
	_door_open = true
	_release()
	serviced_count += 1
	player._show_weapon_notice(_text("RESTAURADO / -$100","RESTORED / -$100"))
	var personal := get_tree().get_first_node_in_group("personal_car_manager")
	if personal != null: personal.capture_state()
func _cancel() -> void:
	if is_instance_valid(_motion): _motion.kill()
	_release()
	_door_open = true
	shutter.position.y = -48.0
func _exit_tree() -> void:
	if busy: _cancel()
