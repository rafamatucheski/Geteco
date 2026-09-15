extends "res://world/mountain_pass/WinterResident.gd"
## Territorial wildlife. All den/guardian positions are global, including streamed regions.
## Optional external BearAudio: get_breathing_stream/get_grunt_alert_stream/get_charge_stream.
const AUDIO_PATH := "res://audio/review_0908/BearAudio.gd"
enum State { WANDER, WARNING, CHARGE, RECOVER }
var is_cub := false
var family_guardian: Node2D
var family_offset := Vector2.ZERO
var state := State.WANDER
var state_time := 0.0
var charge_direction := Vector2.ZERO
var charge_hit := false
var charge_cooldown := 2.0
var bite_cooldown := 0.0
var warning_cooldown := 0.0
var threat_time := 0.0
var sound_cooldown := 0.0
var audio_voice: AudioStreamPlayer2D
var breath_voice: AudioStreamPlayer2D
var audio_bank: Script
var _blood_pool: Polygon2D
var _death_age := 0.0

func _create_model() -> Node3D:
	var animal := preload("res://world/mountain_pass/MountainBearModel.gd").new()
	animal.is_cub = is_cub
	return animal

func _ready() -> void:
	super._ready()
	remove_from_group("winter_resident")
	add_to_group("mountain_wildlife")
	add_to_group("bear_cub" if is_cub else "bear_adult")
	health = 55 if is_cub else 360
	get_child(0).shape.radius = 8 if is_cub else 14
	speech.hide()
	viewport.size = Vector2i(128,128) if is_cub else Vector2i(160,160)
	var camera: Camera3D
	for child in viewport.get_children():
		if child is Camera3D: camera = child
	camera.size = 3.5
	for child in get_children():
		if child is Sprite2D:
			child.scale = Vector2.ONE * (18.0 * camera.size / viewport.size.x)
			child.position = (Vector2(viewport.size)*0.5-camera.unproject_position(Vector3.ZERO))*child.scale
	if ResourceLoader.exists(AUDIO_PATH):
		audio_bank = load(AUDIO_PATH) as Script
		if audio_bank != null and not audio_bank.has_method("get_grunt_alert_stream"): audio_bank = null
	audio_voice = AudioStreamPlayer2D.new()
	audio_voice.name = "BearVoice"
	audio_voice.bus = &"SFX"
	audio_voice.max_distance = 500
	audio_voice.volume_db = -14
	add_child(audio_voice)
	breath_voice = AudioStreamPlayer2D.new()
	breath_voice.name = "BearBreathing"
	breath_voice.bus = &"SFX"
	breath_voice.max_distance = 170
	breath_voice.volume_db = -27
	if audio_bank != null and audio_bank.has_method("get_breathing_stream"):
		breath_voice.stream = audio_bank.call("get_breathing_stream")
	add_child(breath_voice)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return
	var distance := global_position.distance_to(player.global_position)
	if distance > 850:
		breath_voice.stop()
		return
	elapsed += delta
	bite_cooldown = maxf(0,bite_cooldown-delta)
	charge_cooldown = maxf(0,charge_cooldown-delta)
	warning_cooldown = maxf(0,warning_cooldown-delta)
	sound_cooldown = maxf(0,sound_cooldown-delta)
	threat_time = maxf(0,threat_time-delta)
	var exposed: bool = player.is_visible_in_tree() and not player.is_dead and not player.get_meta("mountain_interior",false)
	var breathe := exposed and distance < 160 and not is_cub and state != State.CHARGE
	if breathe and breath_voice.stream != null and not breath_voice.playing: breath_voice.play()
	elif not breathe: breath_voice.stop()
	if is_cub:
		_update_cub(player,exposed,distance)
	else:
		_update_adult(player,exposed,distance,delta)
	move_and_slide()
	if state == State.CHARGE and get_slide_collision_count() > 0:
		state = State.RECOVER
		state_time = 0.75
	if velocity.length()>1: model.rotation.y = lerp_angle(model.rotation.y,-velocity.angle()+PI*0.5,minf(1,delta*9))
	model.walking = velocity.length()>1
	model.alert = state == State.WARNING
	model.charging = state == State.CHARGE
	render_clock += delta
	if render_clock >= 0.05:
		model._process(render_clock)
		render_clock = 0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_adult(player: Node2D, exposed: bool, distance: float, delta: float) -> void:
	var hunting := exposed and distance < (310 if threat_time>0 else 235) and player.global_position.distance_to(home)<370
	if not hunting:
		state = State.WANDER
		var roam := home + Vector2(sin(elapsed * 0.11), cos(elapsed * 0.08)) * 48.0
		velocity = global_position.direction_to(roam)*30 if global_position.distance_to(roam)>10 else Vector2.ZERO
		return
	if warning_cooldown == 0:
		player._show_weapon_notice("URSA PROTEGENDO A MATA! Afaste-se dos filhotes; desvie quando ela baixar a cabeça.")
		warning_cooldown = 18
	if state == State.WARNING:
		velocity = Vector2.ZERO
		model.rotation.y = lerp_angle(model.rotation.y,-global_position.direction_to(player.global_position).angle()+PI*0.5,delta*4)
		state_time -= delta
		if state_time <= 0:
			charge_direction = global_position.direction_to(player.global_position)
			state = State.CHARGE
			state_time = 0.8
			charge_hit = false
			charge_cooldown = 2.4
			_voice("charge",true)
	elif state == State.CHARGE:
		velocity = charge_direction*320
		state_time -= delta
		if not charge_hit and distance < 36 and _clear_attack(player):
			player.take_damage(60)
			preload("res://guns/combat/BodyWound.gd").apply(player, charge_direction)
			charge_hit = true
			bite_cooldown = 1.4
		if state_time <= 0:
			state = State.RECOVER
			state_time = 0.7
	elif state == State.RECOVER:
		velocity = velocity.move_toward(Vector2.ZERO,delta*700)
		state_time -= delta
		if state_time <= 0: state = State.WANDER
	else:
		velocity = global_position.direction_to(player.global_position)*135
		if distance<32 and bite_cooldown == 0 and _clear_attack(player):
			player.take_damage(38)
			preload("res://guns/combat/BodyWound.gd").apply(player, global_position.direction_to(player.global_position))
			bite_cooldown = 1.2
			_voice("warning")
		elif distance>62 and distance<210 and charge_cooldown == 0 and _clear_attack(player):
			state = State.WARNING
			state_time = 0.72
			velocity = Vector2.ZERO
			_voice("warning",true)

func _update_cub(player: Node2D, exposed: bool, distance: float) -> void:
	var guardian_alive: bool = is_instance_valid(family_guardian) and not family_guardian.is_dead
	var den: Vector2 = family_guardian.global_position if guardian_alive else home
	var target := den + family_offset
	if exposed and distance < 155:
		var away := player.global_position.direction_to(global_position)
		target = home + away*110
		velocity = global_position.direction_to(target)*82
		if guardian_alive: family_guardian.threat_time = 5
		_voice("cub_call")
	else:
		target += Vector2(sin(elapsed*0.21),cos(elapsed*0.17))*15
		velocity = global_position.direction_to(target)*36 if global_position.distance_to(target)>15 else Vector2.ZERO

func _clear_attack(player: Node2D) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(global_position,player.global_position,1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func take_damage(amount: int, _source: Variant = null) -> void:
	if is_dead or amount <= 0: return
	health = maxi(0,health-amount)
	threat_time = 6
	if is_instance_valid(family_guardian) and not family_guardian.is_dead: family_guardian.threat_time = 6
	_blood(amount)
	_voice("hurt",true)
	if health > 0:
		model.hurt_flash = 0.18
		return
	is_dead = true
	get_node("/root/NPCMedicalCare").report_injury(self)
	breath_voice.stop()
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	model.walking = false
	model.alert = false
	model.charging = false
	model.dead = true
	_voice("death",true)
	var tween := create_tween()
	tween.tween_property(model,"rotation:z",-PI*0.45,0.45).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(model,"position:y",0.26 if is_cub else 0.45,0.45)
	tween.step_finished.connect(func(_index): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	# Animate the short fall, then render the carcass once until cleanup.
	model.set_process(true)
	tween.finished.connect(func():
		model.set_process(false)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

func _blood(amount: int) -> void:
	var effects := get_tree().get_first_node_in_group("weapon_effects")
	if effects != null: effects.spawn_blood(global_position,Vector2.UP,amount)
	if is_instance_valid(_blood_pool): return
	_blood_pool = Polygon2D.new()
	_blood_pool.name = "WildlifeBlood"
	_blood_pool.add_to_group("wildlife_blood")
	_blood_pool.z_as_relative = false
	_blood_pool.z_index = 3
	_blood_pool.color = Color("61242b")
	var points := PackedVector2Array()
	var radius := 6.0 if is_cub else 13.0
	for i in 13:
		var angle := float(i)*TAU/13
		points.append(Vector2(cos(angle),sin(angle)*0.6)*radius*(0.8+0.2*sin(i*2.7)))
	_blood_pool.polygon = points
	get_parent().add_child(_blood_pool)
	_blood_pool.global_position = global_position
	preload("res://guns/combat/BloodTransferSystem.gd").ensure(self)
	var fade := _blood_pool.create_tween()
	fade.tween_interval(25)
	fade.tween_property(_blood_pool,"modulate:a",0.0,8)
	fade.tween_callback(_blood_pool.queue_free)

func _voice(event: String, urgent := false) -> void:
	if audio_bank == null or (sound_cooldown>0 and not urgent): return
	var method := "get_charge_stream" if event == "charge" else "get_grunt_alert_stream"
	if not audio_bank.has_method(method): return
	var stream: AudioStream = audio_bank.call(method)
	if stream == null: return
	audio_voice.stream = stream
	audio_voice.pitch_scale = 1.1 if is_cub else 0.96
	audio_voice.play()
	sound_cooldown = 4

func on_medical_discharge() -> void:
	_death_age = 0.0
	state = State.WANDER
	state_time = 0.0
	threat_time = 0.0
	charge_cooldown = 5.0
	model.dead = false
	model.alert = false
	model.charging = false
	model.rotation.z = 0.0
	model.position.y = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
