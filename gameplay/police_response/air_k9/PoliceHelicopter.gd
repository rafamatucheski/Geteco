extends CharacterBody3D
## Four-person rappel transport. Flight and each descending body use physics.
const MODELS = preload("res://gameplay/police_response/air_k9/AirK9Models.gd")
const AIRFRAME = preload("res://gameplay/police_response/air_k9/PoliceHelicopterArt.gd")
const OFFICER = preload("res://gameplay/PoliceAgent.gd")
const RAPPEL_POSE = preload("res://gameplay/police_response/air_k9/PoliceRappelPose.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const HOVER_HEIGHT := 13.0
const ROPE_SEGMENTS := 10
const DESCENT_SPEED := 2.3
## Patrulha aérea (27/10/2026). Antes, com 3 estrelas ele ficava a 13 m girando num raio de 9 m
## em cima do jogador (tampando a tela) e ia embora em 60 s; com 4+ chegava, soltava a equipe e
## partia no mesmo instante. Agora ele chega, circula mais alto e mais largo com o holofote no
## alvo, com 4+ estrelas desce para soltar a equipe depois de DROP_AFTER s circulando, volta a
## circular por STAY_AFTER_DROP s e só então vai embora.
const TRACK_HEIGHT := 22.0
const ORBIT_RADIUS := 18.0
const ORBIT_SPEED := 0.2
const RECON_STAY := 45.0
const DROP_AFTER := 9.0
const STAY_AFTER_DROP := 30.0
## Sem zona de pouso livre perto do alvo, tenta de novo a cada tanto; depois disto desiste de soltar.
const DROP_RETRY := 2.0
const DROP_GIVE_UP := 20.0
static var _rotor_audio: AudioStreamWAV
var director: Node3D
var landing_zone: Dictionary
var mode := "approach"
var health := 320.0
var dead := false
var visual: Node3D
var spotlight: SpotLight3D
var rotor: Node3D
var tail_rotor: Node3D
var doors: Array[Node3D] = []
var rope_mesh: MultiMeshInstance3D
## CPU geometry is retained for physics/headless inspection; the dummy renderer
## does not retain MultiMesh instance transforms for get_instance_transform().
var rope_transforms: Array[Transform3D] = []
var rope_control_points: Array[PackedVector3Array] = []
var sound: AudioStreamPlayer3D
var rappellers: Array[Dictionary] = []
var deployed_count := 0
var sees_player := false
var recon_only := false
var _clock := 0.0
var _mode_time := 0.0
var _sensor := 0.0
var _searchlight_point := Vector3.ZERO
var _searchlight_ready := false

var _next_drop := 0.0
var _reserved := 4
var _depart_requested := false
var _depart_target := Vector3.ZERO
var _rope_retract := 0.0
var _door_open := 0.0
var _depart_origin := Vector3.ZERO
var dropped := false
var _track_time := 0.0
var _stay_limit := RECON_STAY
var _orbit_angle := 0.0
var _drop_retry := 0.0
var _stop_drop := false

func _ready() -> void:
	name = "PoliceRappelHelicopter"
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	set_meta("gameplay_role", "police")
	add_to_group("v2_damageable")
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	# Protect the rotor sweep and tail, not just the fuselage.
	shape.radius = 7.7
	shape.height = 5.2
	collider.shape = shape
	collider.position = Vector3(0, 0.9, 0)
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	var rig := AIRFRAME.build(visual)
	rotor = rig.rotor
	tail_rotor = rig.tail_rotor
	doors = rig.doors
	spotlight = SpotLight3D.new()
	spotlight.position = Vector3(0, -0.9, -1.45)
	spotlight.rotation.x = -PI * 0.5
	spotlight.spot_range = 72.0
	spotlight.spot_angle = 24.0
	spotlight.light_energy = 2.3
	spotlight.light_color = Color("e9e9d7")
	spotlight.shadow_enabled = false
	spotlight.visible = false
	add_child(spotlight)
	_build_ropes()
	sound = AudioStreamPlayer3D.new()
	var recorded := _recorded_rotor()
	sound.stream = recorded if recorded != null else rotor_audio()
	sound.unit_size = 14.0
	sound.max_distance = 105.0
	sound.volume_db = -9.0 if recorded != null else -13.0
	add_child(sound)
	sound.play()
	_play_flyover()
	# A primeira volta começa do lado de onde ele vem, sem cruzar por cima do alvo.
	if is_instance_valid(director) and is_instance_valid(director.gameplay):
		var from: Vector3 = global_position - director.gameplay.last_known
		_orbit_angle = atan2(from.z, from.x)

## Rotor gravado (Firefly, 2026-10-15) em loop; sem o arquivo importado fica o sintetizado.
func _recorded_rotor() -> AudioStreamWAV:
	var take := FIREFLY.take("helicopter", "rotor_loop") as AudioStreamWAV
	if take == null: return null
	var looped := take.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = maxi(1, roundi(take.get_length() * take.mix_rate) - 8)
	return looped

## Passagem do helicóptero chegando: toca uma vez ao surgir, de mais longe que o rotor.
func _play_flyover() -> void:
	var flyover := FIREFLY.take("helicopter", "flyover")
	if flyover == null: return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = flyover
	voice.bus = FIREFLY.bus_name(&"Vehicles")
	voice.volume_db = -7.0
	voice.unit_size = 20.0
	voice.max_distance = 170.0
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(director): queue_free(); return
	if director.response_paused(): return
	_clock += delta
	_mode_time += delta
	rotor.rotation.y = fposmod(rotor.rotation.y + delta * (7.0 if dead else 39.0), TAU)
	tail_rotor.rotation.x = fposmod(tail_rotor.rotation.x + delta * 52.0, TAU)
	_door_open = move_toward(_door_open, 1.0 if mode in ["hover", "rappel"] else 0.0, delta * 0.8)
	for door in doors: door.position.z = 0.23 + _door_open * 2.22
	_sensor -= delta
	if _sensor <= 0.0:
		_sensor = 0.2
		_sense()
	_update_searchlight(delta)
	if dead:
		velocity.y = maxf(-14.0, velocity.y - delta * 8.0)
		move_and_slide()
		if _mode_time > 15.0: _finish()
		return
	if not director.exterior_active() and mode != "depart": begin_departure()
	match mode:
		"approach":
			var destination := _orbit_point()
			_fly_to(destination, 16.0, delta)
			if global_position.distance_to(destination) < 4.0:
				mode = "recon" if recon_only else "track"
				_mode_time = 0.0
			elif _mode_time > 35.0: begin_departure()
		"recon", "track":
			if rope_mesh.visible:
				# Recolhe as cordas parado sobre a zona antes de voltar a circular.
				_rope_retract = minf(1.0, _rope_retract + delta * 0.7)
				_fly_to(landing_zone.center + Vector3.UP * HOVER_HEIGHT, 2.0, delta)
				if _rope_retract >= 1.0: rope_mesh.visible = false
			else:
				# Follow only shared, witnessed information. Roofs still block _sense.
				# 24 m/s acompanha a fuga de carro pela cidade; perto do ponto `_fly_to` desacelera sozinho.
				_orbit_angle = fposmod(_orbit_angle + delta * ORBIT_SPEED, TAU)
				_fly_to(_orbit_point(), 24.0, delta)
			_track_time += delta
			if not _try_begin_drop(delta) and _track_time >= _stay_limit: begin_departure()
		"descend":
			var hover_point: Vector3 = landing_zone.center + Vector3.UP * HOVER_HEIGHT
			_fly_to(hover_point, 12.0, delta)
			if global_position.distance_to(hover_point) < 0.22 and velocity.length() < 0.8:
				mode = "hover"
				_mode_time = 0.0
			elif _mode_time > 25.0: _after_drop()
		"hover":
			_fly_to(landing_zone.center + Vector3.UP * HOVER_HEIGHT, 3.0, delta)
			if _mode_time >= 1.8 and absf(wrapf(rotation.y, -PI, PI)) < 0.04:
				var clear := true
				for point in landing_zone.points:
					if not director.landing_column_clear(point): clear = false; break
				if clear:
					mode = "rappel"
					_mode_time = 0.0
					rope_mesh.visible = true
				elif _mode_time > 6.0: _after_drop()
		"rappel":
			_fly_to(landing_zone.center + Vector3.UP * HOVER_HEIGHT, 2.0, delta)
			_update_rappel(delta)
		"depart":
			_rope_retract = minf(1.0, _rope_retract + delta * 0.7)
			if _rope_retract >= 1.0: rope_mesh.visible = false
			if _mode_time < 2.4:
				_fly_to(_depart_origin + Vector3.UP * 7.0, 4.0, delta)
			elif _mode_time < 8.0:
				var elapsed := _mode_time - 2.4
				var angle := minf(0.95, elapsed * 0.19)
				_fly_to(_depart_origin + Vector3(sin(angle) * elapsed * 15.0, 7.0 + elapsed * 1.2, -cos(angle) * elapsed * 15.0), 18.0, delta)
			else: _fly_to(_depart_target, 21.0, delta)
			if _mode_time > 10.0 and not director.point_on_screen(global_position, 12.0): _finish()
			elif _mode_time > 25.0 and global_position.distance_to(_depart_target) < 2.0: _finish()
	# Hands and harness move every physics tick: updating at a lower frequency
	# would leave visible gaps between the glove and the rope during descent.
	if rope_mesh.visible: _update_ropes()

func _fly_to(destination: Vector3, speed: float, delta: float) -> void:
	var offset := destination - global_position
	var desired := offset.normalized() * minf(speed, offset.length() * 1.4)
	# Swept collision stops the full rotor envelope. Climb over an obstruction
	# only within a bounded ceiling; never teleport through buildings.
	if offset.length() > 2.0 and test_move(global_transform, desired.normalized() * 2.8):
		desired = Vector3.UP * 5.0 if global_position.y < (landing_zone.center as Vector3).y + 52.0 else Vector3.ZERO
	velocity = velocity.move_toward(desired, delta * 9.0)
	move_and_slide()
	var planar := Vector2(velocity.x, velocity.z)
	var heading := 0.0 if mode in ["hover", "rappel"] else rotation.y
	if mode not in ["hover", "rappel"] and planar.length() > 0.8: heading = atan2(-velocity.x, -velocity.z)
	var turn := wrapf(heading - rotation.y, -PI, PI)
	rotation.y = lerp_angle(rotation.y, heading, minf(1.0, delta * 2.3))
	var local_velocity := global_basis.inverse() * velocity
	visual.rotation.z = lerpf(visual.rotation.z, clampf(-local_velocity.x * 0.012 + turn * 0.14, -0.21, 0.21), minf(1.0, delta * 3.0))
	visual.rotation.x = lerpf(visual.rotation.x, clampf(local_velocity.z * 0.012, -0.23, 0.14), minf(1.0, delta * 3.0))
	visual.position.y = sin(_clock * 2.15) * 0.035

func _sense() -> void:
	sees_player = false
	spotlight.visible = false
	if dead or mode == "depart" or not director.exterior_active(): return
	var gameplay: Node3D = director.gameplay
	var target: Node3D = gameplay.pursuit_target()
	if not is_instance_valid(target) or not target.visible: return
	var point := target.global_position + Vector3.UP
	sees_player = director.has_line_of_sight(self, point, target, 72.0)
	if sees_player: gameplay.report_contact(target.global_position)
	_searchlight_point = target.global_position if sees_player else gameplay.last_known
	_searchlight_ready = true

func _update_searchlight(delta: float) -> void:
	spotlight.visible = not dead and mode != "depart" and _searchlight_ready and director.exterior_active() and director.point_on_screen(global_position, 72.0)
	if not spotlight.visible: return
	# Track each physics frame, with a small search sweep after losing visual contact.
	var point := _searchlight_point
	var target: Node3D = director.gameplay.pursuit_target()
	if sees_player and is_instance_valid(target): point = target.global_position
	else: point += Vector3(cos(_clock * .8),0,sin(_clock * .8)) * 3.0
	if spotlight.global_position.distance_squared_to(point) < .1: return
	var desired := spotlight.global_transform.looking_at(point, Vector3.FORWARD).basis
	spotlight.global_basis = spotlight.global_basis.slerp(desired, minf(1.0, delta * 5.0))

func _spawn_rappeller(index: int) -> void:
	# Sem mais gente para soltar: quem já desceu fica, a aeronave volta a só observar.
	if director.gameplay.stars < 4:
		_stop_drop = true
		return
	if director.officer_count() + _reserved > director.officer_limit():
		# Legacy callers may add officers without consulting DispatchController.
		# Do not compound their allocation with another person on a rope.
		_stop_drop = true
		return
	var point: Vector3 = landing_zone.points[index]
	if not director.capsule_clear(point): return
	var officer := OFFICER.new()
	officer.controller = director.gameplay
	officer.tier = clampi(int(director.gameplay.stars) - 2, 2, 4)
	officer.set_meta("police_rappelling", true)
	officer.set_meta("police_place_id", "")
	officer.position = director.to_local(Vector3(point.x, global_position.y - 2.6, point.z))
	director.add_child(officer)
	officer.set_physics_process(false)
	var pose := RAPPEL_POSE.new()
	if not pose.configure(officer):
		officer.queue_free()
		return
	# The transport shell encloses the door; only the descending officer ignores
	# its own transport, while remaining solid to scenery, vehicles and people.
	officer.add_collision_exception_with(self)
	rappellers.append({"officer": officer, "point": point, "index": index, "blocked": 0.0,
		"pose": pose, "phase": "attach", "phase_time": 0.0, "start_height": officer.global_position.y, "contacts": {}})
	deployed_count += 1

func _update_rappel(delta: float) -> void:
	_next_drop -= delta
	if deployed_count < 4 and _next_drop <= 0.0 and not _depart_requested and not _stop_drop:
		_next_drop = 0.85
		_spawn_rappeller(deployed_count)
	for index in range(rappellers.size() - 1, -1, -1):
		var entry: Dictionary = rappellers[index]
		var officer: CharacterBody3D = entry.officer
		if not is_instance_valid(officer):
			rappellers.remove_at(index)
			_release_slot()
			continue
		if officer.get("dead") == true:
			# A casualty remains physical while lowered, then is released on the floor.
			officer.collision_mask = 7
		var point: Vector3 = entry.point
		entry.phase_time = float(entry.phase_time) + delta
		if entry.get("retrieve", false):
			officer.move_and_collide(Vector3.UP * DESCENT_SPEED * delta * 2.0)
			if officer.global_position.y >= global_position.y - 2.7:
				entry.pose.finish()
				officer.queue_free()
				rappellers.remove_at(index)
				_release_slot()
				continue
		else:
			match str(entry.phase):
				"attach":
					if float(entry.phase_time) >= 0.65: entry.phase = "descend"; entry.phase_time = 0.0
				"descend":
					var remaining := maxf(0.0, officer.global_position.y - point.y)
					var brake := clampf(remaining / 0.9, 0.28, 1.0)
					var cadence := 1.0 + 0.13 * sin(float(entry.phase_time) * 4.1 + float(entry.index))
					var travel := minf(DESCENT_SPEED * cadence * brake * delta, remaining)
					var before := officer.global_position
					officer.move_and_collide(Vector3.DOWN * travel)
					if officer.global_position.y - point.y < 0.055:
						entry.phase = "land"
						entry.phase_time = 0.0
					elif officer.global_position.distance_to(before) < travel * 0.2:
						entry.blocked = float(entry.blocked) + delta
						if float(entry.blocked) > 2.0: entry["retrieve"] = true
				"land":
					if float(entry.phase_time) >= 0.65: entry.phase = "release"; entry.phase_time = 0.0
				"release":
					if float(entry.phase_time) >= 0.55:
						entry.pose.update(delta, "release", 1.0, rope_anchor(int(entry.index)))
						_release_officer(officer)
						rappellers.remove_at(index)
						continue
		var phase_progress := float(entry.phase_time) / (0.55 if entry.phase == "release" else 0.65)
		if entry.phase == "descend": phase_progress = 1.0 - (officer.global_position.y - point.y) / maxf(0.1, float(entry.start_height) - point.y)
		entry.contacts = entry.pose.update(delta, entry.phase, phase_progress, rope_anchor(int(entry.index)))
	if (deployed_count == 4 or _depart_requested or _stop_drop) and rappellers.is_empty() and _mode_time > 6.0:
		if _depart_requested: _start_departure()
		else: _after_drop()
	elif _mode_time > 25.0:
		# Abort safely: all remaining live bodies recover their normal collision
		# and gravity. There is no forced placement through an occupied column.
		for entry in rappellers:
			if is_instance_valid(entry.officer): _release_officer(entry.officer)
		rappellers.clear()
		if _depart_requested: _start_departure()
		else: _after_drop()

func _release_officer(officer: CharacterBody3D) -> void:
	for entry in rappellers:
		if entry.officer == officer: entry.pose.finish(); break
	_release_slot()
	officer.remove_meta("police_rappelling")
	officer.remove_collision_exception_with(self)
	if officer.get("dead") != true:
		director.gameplay.police.append(officer)
		officer.reparent(director.gameplay, true)
		officer.velocity = Vector3.ZERO
		officer.set_physics_process(true)
		if director.gameplay.stars <= 0: director.retire_ground_officer(officer)

func _release_slot() -> void:
	if _reserved <= 0: return
	_reserved -= 1
	director.release_air_slot()

## Ponto da volta atual: em torno do alvo visto (ou da última posição conhecida), alto e largo o
## bastante para não tampar o jogador na câmera isométrica.
func _orbit_point() -> Vector3:
	var gameplay: Node3D = director.gameplay
	var anchor: Vector3 = gameplay.last_known
	var target: Node3D = gameplay.pursuit_target()
	if sees_player and is_instance_valid(target): anchor = target.global_position
	return anchor + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * ORBIT_RADIUS + Vector3.UP * TRACK_HEIGHT

## Transporte (4+ estrelas) circulando há DROP_AFTER s: procura zona livre perto do alvo e desce.
## Sem zona, tenta a cada DROP_RETRY s; passado DROP_GIVE_UP desiste e segue só observando.
func _try_begin_drop(delta: float) -> bool:
	if recon_only or dropped or _stop_drop or _track_time < DROP_AFTER: return false
	if director.gameplay.stars < 4:
		cancel_drop()
		return false
	_drop_retry -= delta
	if _drop_retry > 0.0: return false
	_drop_retry = DROP_RETRY
	var zone: Dictionary = director.find_landing_zone(director.gameplay.last_known)
	if zone.is_empty():
		if _track_time >= DROP_AFTER + DROP_GIVE_UP: cancel_drop()
		return false
	landing_zone = zone
	mode = "descend"
	_mode_time = 0.0
	return true

## Para de soltar gente (estrelas caíram para 3, sem zona de pouso) e segue observando;
## quem já está na corda termina de descer.
func cancel_drop() -> void:
	if recon_only or _stop_drop or dead: return
	_stop_drop = true
	if mode in ["descend", "hover"]: _after_drop()
	elif mode != "rappel":
		while _reserved > 0: _release_slot()

## Equipe no chão (ou inserção abortada): devolve as vagas reservadas, sobe de volta e circula
## mais STAY_AFTER_DROP s antes de ir embora.
func _after_drop() -> void:
	while _reserved > 0: _release_slot()
	dropped = true
	_stop_drop = true
	_rope_retract = 0.0
	mode = "track"
	_mode_time = 0.0
	_track_time = 0.0
	_stay_limit = STAY_AFTER_DROP

func begin_departure() -> void:
	if mode == "depart" or dead: return
	_depart_requested = true
	# Finish lowering the people already on ropes before moving the aircraft.
	if mode == "rappel" and not rappellers.is_empty():
		return
	_start_departure()

func _start_departure() -> void:
	while _reserved > 0: _release_slot()
	mode = "depart"
	_mode_time = 0.0
	spotlight.visible = false
	_depart_origin = global_position
	_depart_target = global_position + Vector3(115.0, 22.0, -100.0)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0.0: return
	health = maxf(0.0, health - amount)
	if health > 0.0: return
	dead = true
	_mode_time = 0.0
	spotlight.visible = false
	rope_mesh.visible = false
	sound.stop()
	for entry in rappellers:
		if is_instance_valid(entry.officer): _release_officer(entry.officer)
	rappellers.clear()
	while _reserved > 0: _release_slot()
	if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source():
		director.gameplay.report_vehicle_assault(self, source)

func cleanup_rappellers() -> void:
	for entry in rappellers:
		entry.pose.finish()
		if is_instance_valid(entry.officer): entry.officer.queue_free()
	rappellers.clear()
	while _reserved > 0: _release_slot()

func _finish() -> void:
	cleanup_rappellers()
	director.helicopter_finished(self)
	queue_free()

func _build_ropes() -> void:
	rope_mesh = MultiMeshInstance3D.new()
	rope_mesh.name = "FourRappelRopes"
	rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.028
	cylinder.bottom_radius = 0.028
	cylinder.height = 1.0
	cylinder.radial_segments = 5
	# Each rope retains ten articulated segments; only redundant rings are removed.
	cylinder.rings = 0
	cylinder.material = MODELS.material(Color("b7a477"))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = cylinder
	multi.instance_count = 4 * ROPE_SEGMENTS
	rope_transforms.resize(4 * ROPE_SEGMENTS)
	rope_control_points.resize(4)
	rope_mesh.multimesh = multi
	rope_mesh.visible = false
	add_child(rope_mesh)

func _update_ropes() -> void:
	for index in 4:
		var end: Vector3 = landing_zone.points[index]
		var start := rope_anchor(index)
		end = end.lerp(start, _rope_retract)
		var contacts: Dictionary = {}
		for entry in rappellers:
			if int(entry.index) == index and entry.contacts.get("attached", false): contacts = entry.contacts; break
		var controls := PackedVector3Array()
		if not contacts.is_empty():
			controls.append(start)
			controls.append(start.lerp(contacts.upper_hand, 0.5) + Vector3(sin(_clock * 1.8 + index) * 0.018, 0, 0))
			controls.append(contacts.upper_hand)
			controls.append(contacts.harness)
			controls.append(contacts.lower_hand)
			for step in 6: controls.append(_rope_point(contacts.lower_hand, end, float(step + 1) / 6.0, index))
		else:
			for step in ROPE_SEGMENTS + 1: controls.append(_rope_point(start, end, float(step) / ROPE_SEGMENTS, index))
		rope_control_points[index] = controls
		for segment in ROPE_SEGMENTS:
			var a := controls[segment]
			var b := controls[segment + 1]
			var along := b - a
			var length := maxf(0.001, along.length())
			var up := along / length
			var right := Vector3.RIGHT
			if absf(up.dot(right)) > 0.9: right = Vector3.FORWARD
			var forward := right.cross(up).normalized()
			right = up.cross(forward).normalized()
			var local_basis := Basis(right, up * length, forward)
			var local_transform := Transform3D(local_basis, (a + b) * 0.5)
			var local := rope_mesh.global_transform.affine_inverse() * local_transform
			rope_transforms[index * ROPE_SEGMENTS + segment] = local
			rope_mesh.multimesh.set_instance_transform(index * ROPE_SEGMENTS + segment, local)

func rope_anchor(index: int) -> Vector3:
	var point: Vector3 = landing_zone.points[index] - (landing_zone.center as Vector3)
	return visual.to_global(Vector3(point.x, 0.62, point.z))

func _rope_point(start: Vector3, finish: Vector3, weight: float, index: int) -> Vector3:
	var swing := sin(weight * PI) * 0.12
	return start.lerp(finish, weight) + Vector3(sin(_clock * 2.4 + index) * swing, 0, cos(_clock * 1.8 + index) * swing)

static func rotor_audio() -> AudioStreamWAV:
	if _rotor_audio != null: return _rotor_audio
	var samples := PackedByteArray()
	var rate := 22050
	samples.resize(rate)
	# Audio buffer/loop lengths count whole samples.
	@warning_ignore("integer_division")
	for index in rate / 2:
		var time := float(index) / rate
		var blade := pow(0.5 + 0.5 * sin(TAU * 24.0 * time), 7.0)
		var sample := (sin(TAU * 72.0 * time) * 0.24 + sin(TAU * 144.0 * time) * 0.1 + blade * sin(TAU * 336.0 * time) * 0.5) * 24000.0
		samples.encode_s16(index * 2, int(sample))
	_rotor_audio = AudioStreamWAV.new()
	_rotor_audio.format = AudioStreamWAV.FORMAT_16_BITS
	_rotor_audio.mix_rate = rate
	_rotor_audio.data = samples
	_rotor_audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	# Audio buffer/loop lengths count whole samples.
	@warning_ignore("integer_division")
	_rotor_audio.loop_end = rate / 2
	return _rotor_audio
