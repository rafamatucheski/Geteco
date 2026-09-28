extends Node
## Two bounded rear-wheel emitters and one bounded, surface-aligned mark mesh.

const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const SURFACE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const STREET_PHYSICS := preload("res://gameplay/street_physics/StreetPhysics.gd")
const MAX_MARK_SEGMENTS := 320
const MARK_LIFETIME_MSEC := 10000
# Sulco em chão macio fica mais tempo que a borracha do asfalto: é o rastro que o
# carro deixa na grama/terra mesmo andando reto, sem derrapar.
const RUT_LIFETIME_MSEC := 30000
const SOFT_KINDS := ["grass","dirt","snow"]
const PROBE_INTERVAL := .05
const REDRAW_INTERVAL := .10

var vehicle: CharacterBody3D
var emitters: Array[GPUParticles3D] = []
var marks: Array[Dictionary] = []
var last_contacts: Array[Dictionary] = [{},{}]
var last_modes: Array[String] = ["",""]
var mark_mesh: MeshInstance3D
var geometry := ImmediateMesh.new()
var skid_audio: AudioStreamPlayer3D
var _probe_clock := 0.0
var _redraw_clock := 0.0

func configure(car: CharacterBody3D) -> void:
	vehicle = car

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void:
	_stop_emitters()
	if is_instance_valid(skid_audio): skid_audio.stop()
	geometry.clear_surfaces()

func physics_tick(delta: float, active: bool) -> void:
	_expire_marks()
	_redraw_clock -= delta
	if not active:
		_stop_emitters()
		last_contacts = [{},{}]
		if _redraw_clock <= 0: _redraw_marks()
		return
	_probe_clock -= delta
	if _probe_clock > 0:
		if _redraw_clock <= 0: _redraw_marks()
		return
	_probe_clock = PROBE_INTERVAL
	var contacts := _rear_contacts()
	var motion := Vector3(vehicle.horizontal_velocity.x,0,vehicle.horizontal_velocity.z)
	var road_speed := motion.length()
	var lateral_speed := absf(motion.dot(vehicle.global_basis.x))
	var any_wet := false
	for contact in contacts:
		if not contact.is_empty() and bool(contact.wet): any_wet = true
	var skid_threshold := 3.125 if any_wet else 5.625
	var sliding: bool = lateral_speed > skid_threshold or (vehicle.controlled and vehicle.brake_input and road_speed > 3.75)
	_update_skid_audio(sliding and road_speed > 2.5, road_speed, lateral_speed)
	for side in 2:
		var contact: Dictionary = contacts[side]
		if contact.is_empty():
			_set_emitting(side,false)
			last_modes[side] = ""
			last_contacts[side] = {}
			continue
		var kind: String = contact.kind
		var mode := ""
		if bool(contact.wet) and road_speed > 3.0: mode = "water"
		elif kind in SOFT_KINDS and road_speed > 2.5: mode = kind
		elif sliding and kind == "hard": mode = "smoke"
		last_modes[side] = mode
		if mode.is_empty(): _set_emitting(side,false)
		else: _emit_surface(side,contact,mode,road_speed,lateral_speed)
		if sliding and road_speed > 2.5: _append_mark(side,contact,kind,false)
		elif kind in SOFT_KINDS and road_speed > .8: _append_mark(side,contact,kind,true)
		else: last_contacts[side] = contact
	if _redraw_clock <= 0: _redraw_marks()

func _rear_contacts() -> Array[Dictionary]:
	var points: Array[Vector3] = []
	for pivot in vehicle.wheels:
		if not bool(pivot.get_meta("front",false)): points.append(pivot.global_position)
	if points.size() < 2:
		points.assign([
			vehicle.to_global(Vector3(-vehicle.half_width*.68,.42,vehicle.half_length*.64)),
			vehicle.to_global(Vector3(vehicle.half_width*.68,.42,vehicle.half_length*.64))])
	points.sort_custom(func(a: Vector3,b: Vector3): return vehicle.to_local(a).x < vehicle.to_local(b).x)
	return [SURFACE.sample(vehicle,points[0]),SURFACE.sample(vehicle,points[1])]

func _ensure_emitters() -> void:
	if not emitters.is_empty(): return
	for side in 2:
		var emitter := RESOURCES.emitter("RearWheelSurface%d"%side,18,.48,Vector2(.26,.26))
		emitter.process_material = RESOURCES.particle_process()
		vehicle.add_child(emitter)
		emitter.top_level = true
		emitters.append(emitter)

func _emit_surface(side: int, contact: Dictionary, mode: String, road_speed: float, lateral_speed: float) -> void:
	_ensure_emitters()
	var emitter := emitters[side]
	var process := emitter.process_material as ParticleProcessMaterial
	# 0 = moto/carro leve, 1 = caminhão/ônibus: veículo pesado arranca mais chão.
	var heft := _heft()
	var normal: Vector3 = contact.normal
	var wake := -Vector3(vehicle.horizontal_velocity.x,0,vehicle.horizontal_velocity.z).normalized()
	process.direction = (normal*.75+wake*.45+vehicle.global_basis.x*(-.15 if side==0 else .15)).normalized()
	process.spread = 38
	process.gravity = Vector3(0,-2.5,0) if mode == "water" else (Vector3(0,-7.5,0) if mode == "grass" else Vector3(0,.28,0))
	process.initial_velocity_min = .9 if mode == "water" else .45
	process.initial_velocity_max = 2.7 if mode == "water" else 1.65
	if mode == "water":
		process.scale_min = .45
		process.scale_max = .9
		process.color = Color(.75,.86,1,.62)
	elif mode == "snow":
		process.scale_min = .55
		process.scale_max = 1.15
		process.color = Color(.88,.91,.91,.45)
	elif mode == "dirt":
		process.scale_min = .48+heft*.3
		process.scale_max = 1.25+heft*.9
		process.color = Color(.38,.30,.22,.48+heft*.2)
	elif mode == "grass":
		# Tufos arrancados sobem e caem (gravidade), não pairam como poeira.
		process.initial_velocity_min = 1.0+heft
		process.initial_velocity_max = 2.6+heft*1.8
		process.scale_min = .22+heft*.15
		process.scale_max = .6+heft*.45
		process.color = Color(.27,.36,.15,.85).lerp(Color(.30,.24,.14,.85),heft*.6)
	else:
		var is_heavy: bool = lateral_speed > 6.0 or (vehicle.controlled and vehicle.brake_input and road_speed > 4.5)
		process.scale_min = .30 if is_heavy else .22
		process.scale_max = 1.30 if is_heavy else .70
		process.color = Color(.88,.88,.90,.36) if is_heavy else Color(.90,.91,.92,.22)
		process.angle_min = 0.0
		process.angle_max = 360.0
		process.angular_velocity_min = -2.2
		process.angular_velocity_max = 2.2
	emitter.global_position = contact.point+normal*.035
	var soft_boost := heft*.35 if mode in SOFT_KINDS else 0.0
	emitter.amount_ratio = clampf(.22+road_speed/18.0+lateral_speed/20.0+soft_boost,.22,1.0)
	emitter.emitting = true

func _set_emitting(side: int, value: bool) -> void:
	if side < emitters.size(): emitters[side].emitting = value

func _stop_emitters() -> void:
	for emitter in emitters: emitter.emitting = false
	if is_instance_valid(skid_audio) and skid_audio.playing: skid_audio.stop()

func _update_skid_audio(audible: bool, road_speed: float, lateral_speed: float) -> void:
	if not audible:
		if is_instance_valid(skid_audio) and skid_audio.playing: skid_audio.stop()
		return
	if not is_instance_valid(skid_audio):
		var family: String = ENGINE_PROFILE.family(str(vehicle.archetype))
		var kind := "monaliza" if str(vehicle.archetype) == "monaliza" else ("heavy" if family in ["truck", "bus", "fire_diesel", "diesel"] else ("muscle" if family == "muscle" else ("sport" if family in ["sport", "vq35", "m8_v8", "rosso_v12", "bike_sport"] else "street")))
		var source := load("res://audio/acoustic/skid_%s.wav" % kind) as AudioStreamWAV
		if source == null: return
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
		skid_audio = AudioStreamPlayer3D.new()
		skid_audio.name = "VehicleSkid"
		skid_audio.stream = stream
		skid_audio.max_distance = 55.0
		skid_audio.unit_size = 14.0
		skid_audio.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		vehicle.add_child(skid_audio)
	skid_audio.volume_db = lerpf(-24.0, -11.0, clampf(road_speed / 16.25, 0.0, 1.0))
	skid_audio.pitch_scale = lerpf(0.88, 1.12, clampf(lateral_speed / 11.25, 0.0, 1.0))
	if not skid_audio.playing: skid_audio.play()

func _heft() -> float:
	return clampf((STREET_PHYSICS._vehicle_mass(vehicle)-.6)/4.0,0.0,1.0)

func _append_mark(side: int, contact: Dictionary, kind: String, rut := false) -> void:
	var previous: Dictionary = last_contacts[side]
	last_contacts[side] = contact
	if previous.is_empty(): return
	var length: float = previous.point.distance_to(contact.point)
	if length < .035 or length > 2.2: return
	var heft := _heft()
	# Pneu de caminhão é mais largo e afunda mais: sulco mais largo e mais escuro.
	var width := lerpf(.10,.22,heft) if rut else .075
	marks.append({"a":previous.point,"b":contact.point,"na":previous.normal,"nb":contact.normal,"kind":kind,
		"born":Time.get_ticks_msec(),"life":RUT_LIFETIME_MSEC if rut else MARK_LIFETIME_MSEC,"w":width,"depth":lerpf(.75,1.35,heft) if rut else 1.0})
	while marks.size() > MAX_MARK_SEGMENTS: marks.pop_front()

func _ensure_mark_mesh() -> void:
	if is_instance_valid(mark_mesh): return
	mark_mesh = MeshInstance3D.new()
	mark_mesh.name = "SurfaceAlignedTireMarks"
	mark_mesh.mesh = geometry
	mark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark_mesh.material_override = material
	vehicle.add_child(mark_mesh)
	mark_mesh.top_level = true
	mark_mesh.global_transform = Transform3D.IDENTITY

func _expire_marks() -> void:
	var now := Time.get_ticks_msec()
	marks = marks.filter(func(mark: Dictionary): return now-int(mark.born)<int(mark.life))

func _redraw_marks() -> void:
	_redraw_clock = REDRAW_INTERVAL
	if marks.is_empty():
		if is_instance_valid(mark_mesh): mark_mesh.visible = false
		return
	_ensure_mark_mesh()
	mark_mesh.visible = true
	geometry.clear_surfaces()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var now := Time.get_ticks_msec()
	for mark in marks:
		var a: Vector3 = mark.a
		var b: Vector3 = mark.b
		var na: Vector3 = mark.na
		var nb: Vector3 = mark.nb
		var tangent := (b-a).normalized()
		var half_width: float = mark.w
		var sa := tangent.cross(na).normalized()*half_width
		var sb := tangent.cross(nb).normalized()*half_width
		var age := float(now-int(mark.born))/float(mark.life)
		var depth: float = mark.depth
		var tint := Color(.035,.035,.03,(1.0-age)*(.48 if mark.kind=="hard" else .30))
		if mark.kind == "snow": tint = Color(.38,.43,.44,(1.0-age)*.38)
		elif mark.kind == "dirt": tint = Color(.15,.10,.07,minf(1.0,(1.0-age)*.36*depth))
		elif mark.kind == "grass": tint = Color(.13,.15,.06,minf(1.0,(1.0-age)*.42*depth))
		for entry in [[a-sa+na*.012,na],[b-sa+nb*.012,nb],[b+sb+nb*.012,nb],[a-sa+na*.012,na],[b+sb+nb*.012,nb],[a+sa+na*.012,na]]:
			geometry.surface_set_color(tint)
			geometry.surface_set_normal(entry[1])
			geometry.surface_add_vertex(entry[0])
	geometry.surface_end()

func clear_all() -> void:
	_stop_emitters()
	marks.clear()
	last_contacts = [{},{}]
	last_modes = ["",""]
	geometry.clear_surfaces()
	if is_instance_valid(mark_mesh): mark_mesh.visible = false
