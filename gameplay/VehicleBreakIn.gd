extends RefCounted
## One temporary presentation for a locked civilian car. No idle work per parked car.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const AUDIO := preload("res://gameplay/VehicleEquipmentAudio.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const ALARM_SECONDS := 7.5
static var _missing_glass: StandardMaterial3D
static var _tool_material: StandardMaterial3D
static var _glass_sound: AudioStreamWAV

var method := ""
var alarm := false
var committed := false
var tool: MeshInstance3D

static func required(car: CharacterBody3D) -> bool:
	if not is_instance_valid(car) or not car.get_meta("vehicle_locked", false): return false
	if not car.get_meta("ambient_parked", false) or car.traffic or car.controlled or car.external_input: return false
	if car.get_meta("dispatch_unit", false) or car.get_meta("police_locked", false): return false
	if car.archetype in ["beach_cabriolet", "porto_rosso"]: return false # Open cabins have no closed side pane to break.
	if car.get_meta("lockpick_handler", Callable()).is_valid(): return false
	return car.boarding_class() in ["car", "tall"] and car.health > 0.0

func choose(method_roll: float, alarm_roll: float) -> void:
	method = "window" if method_roll < .48 else "tool"
	alarm = alarm_roll < .38

func seconds() -> float:
	return 1.15 if method == "window" else 1.8

static func closed_layout(car: CharacterBody3D, side: int) -> Dictionary:
	var spec: Dictionary = car.door_presentation.spec
	var skin := float(spec.get("x", car.half_width / car.visual.scale.x))
	var front := float(spec.zf)
	var rear := float(spec.zr)
	var z := lerpf(front, rear, .58)
	var grip: Vector3 = car.visual.transform * Vector3(float(side) * (skin + .015), float(spec.belt) + .16, z)
	var pane_center := Vector3.ZERO
	var pane_vertices := 0
	var hinge: Node3D = car.door_presentation.hinges.get(side)
	if is_instance_valid(hinge):
		for node in hinge.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			var keys: Array = part.get_meta("door_surface_material_keys", [])
			for surface in part.mesh.get_surface_count():
				var key := str(keys[surface]) if surface < keys.size() else ""
				var pane := "glass" in key or "window" in key
				if keys.is_empty() and part.material_override is BaseMaterial3D:
					pane = part.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED
				if not pane: continue
				var vertices: PackedVector3Array = MESH_ARRAYS.arrays_of(part.mesh, surface)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					pane_center += car.to_local(part.to_global(vertex))
					pane_vertices += 1
	if pane_vertices > 0: grip = pane_center / float(pane_vertices)
	# The ordinary boarding stand is behind the OPEN door's sweep. A locked door
	# needs its own contact point and a stance beside the CLOSED front window.
	# Dante's capsule radius is .27 m: keep a centimetre outside the hull while
	# close enough to reach an inward-sloping pane without stretching the rig.
	var stand := Vector3(float(side) * maxf(car.half_width + .28, absf(grip.x) + .34), .04, grip.z - .18)
	return {"grip": grip, "stand": stand}

func pose(actor: CharacterBody3D, car: CharacterBody3D, side: int, layout: Dictionary, t: float) -> void:
	var target: Vector3 = car.to_global(layout.grip)
	# The presentation is deliberately abstract: reach, gesture, entry. No minigame.
	var heading := target - actor.global_position
	actor.visual.rotation.y = atan2(-heading.x, -heading.z)
	if not actor._idle_pose.is_empty(): actor._apply_pose(actor._idle_pose)
	var hand: Vector3 = actor.visual.to_local(target)
	var working_side := "Right" if side < 0 else "Left"
	var sign_side := 1.0 if working_side == "Right" else -1.0
	var rest := Vector3(sign_side * .24, .95, -.18)
	var reach := smoothstep(.0, .22, t) * (1.0 - smoothstep(.82, 1.0, t))
	var lean_weight := reach
	if method == "window":
		var strike := smoothstep(.30, .43, t) * (1.0 - smoothstep(.55, .75, t))
		hand = hand.lerp(rest + Vector3(0, .25, .12), (1.0 - strike) * .8)
		lean_weight *= strike
	else:
		hand += Vector3(0, sin(t * TAU * 3.0) * .035, 0)
	_reach_with_torso(actor, working_side, rest.lerp(hand, reach), sign_side, lean_weight)
	actor._set_combat_grips(working_side == "Right", working_side == "Left", method == "window" and working_side == "Right", method == "window" and working_side == "Left")
	if method == "tool":
		if not is_instance_valid(tool):
			tool = MeshInstance3D.new()
			tool.name = "EntryTool"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(.025, .24, .012)
			tool.mesh = mesh
			if _tool_material == null:
				_tool_material = StandardMaterial3D.new()
				_tool_material.albedo_color = Color("767d83")
				_tool_material.metallic = .6
			tool.material_override = _tool_material
			tool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			actor.add_child(tool)
		tool.visible = t > .1 and t < .9
		tool.global_position = actor.combat_palm_position(working_side) + Vector3.UP * .075
		tool.global_rotation = Vector3(.12 * sin(t * TAU * 3.0), car.global_rotation.y, -.12 * sign_side)

func _reach_with_torso(actor: CharacterBody3D, working_side: String, hand: Vector3, sign_side: float, weight: float) -> void:
	# A sloped coupe pane is inside the body skin, below the shoulder. Keep the
	# feet and authored limb lengths fixed; bend the lumbar/chest only as needed.
	var lean := 0.0
	var maximum := .78 * weight
	var skeleton: Skeleton3D = actor.skeleton
	var right: Vector3 = (skeleton.global_basis.orthonormalized().inverse() * actor.visual.global_basis.x).normalized()
	var desired: Vector3 = actor.visual.to_global(hand)
	for attempt in 3:
		if not actor._idle_pose.is_empty(): actor._apply_pose(actor._idle_pose)
		var feet := {}
		for limb in ["Left", "Right"]:
			var foot: int = actor._combat_bones[limb + "Foot"]
			feet[limb] = {"bone":foot,"position":skeleton.to_global(skeleton.get_bone_global_pose(foot).origin),"basis":skeleton.get_bone_global_pose(foot).basis}
		actor._set_combat_bone_rotation(actor.hips, Basis(right, -lean * .65) * skeleton.get_bone_global_pose(actor.hips).basis)
		for entry in [["Spine01", .20], ["Spine02", .15]]:
			var bone: int = actor._combat_bones.get(entry[0], -1)
			if bone >= 0:
				actor._set_combat_bone_rotation(bone, Basis(right, -lean * float(entry[1])) * skeleton.get_bone_global_pose(bone).basis)
		for limb in feet:
			actor._solve_leg(limb, feet[limb].position)
			actor._set_combat_bone_rotation(int(feet[limb].bone), feet[limb].basis)
		actor._protract_clavicle(working_side)
		actor._solve_combat_arm(working_side, hand, Basis.IDENTITY, true, sign_side)
		var gap: float = actor.combat_palm_position(working_side).distance_to(desired)
		if gap <= .045 or lean >= maximum: break
		lean = minf(maximum, lean + gap / .45)

func commit(car: CharacterBody3D, side: int, point: Vector3) -> void:
	if committed or not is_instance_valid(car): return
	committed = true
	car.set_meta("vehicle_locked", false)
	car.set_meta("entry_break_in_method", method)
	if method == "window":
		car.set_meta("broken_entry_window_side", side)
		_break_window(car, side)
		if is_instance_valid(STREET.instance): STREET.instance.spawn_glass(point, car.global_basis.x * float(side))
		var sound := _play(car, _glass_stream(), "EntryGlass", -10.0)
		sound.finished.connect(sound.queue_free)
	if alarm: start_alarm(car)

static func start_alarm(car: CharacterBody3D) -> void:
	if car.has_node("EntryAlarm"): return
	var sound := _play(car, AUDIO.alarm_stream(), "EntryAlarm", -15.0)
	car.set_meta("entry_alarm_triggered", true)
	# Scene pause pauses this timer and the sound together; deleting the car owns cleanup.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = ALARM_SECONDS
	sound.add_child(timer)
	timer.timeout.connect(sound.queue_free)
	timer.start()

static func _play(car: CharacterBody3D, stream: AudioStream, label: String, volume: float) -> AudioStreamPlayer3D:
	var sound := AudioStreamPlayer3D.new()
	sound.name = label
	sound.stream = stream
	sound.volume_db = volume
	sound.max_distance = 45.0
	sound.unit_size = 6.0
	sound.position.y = 1.0
	if AudioServer.get_bus_index("Vehicles") >= 0: sound.bus = "Vehicles"
	car.add_child(sound)
	sound.play()
	return sound

static func _break_window(car: CharacterBody3D, side: int) -> void:
	if not is_instance_valid(car.door_presentation): return
	var hinge: Node3D = car.door_presentation.hinges.get(side)
	if not is_instance_valid(hinge): return
	if _missing_glass == null:
		_missing_glass = StandardMaterial3D.new()
		_missing_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_missing_glass.albedo_color = Color(0, 0, 0, 0)
	for node in hinge.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var keys: Array = part.get_meta("door_surface_material_keys", [])
		for surface in keys.size():
			if "glass" in str(keys[surface]) or "window" in str(keys[surface]):
				part.set_surface_override_material(surface, _missing_glass)
		# The original coupe's hand-authored pane is a separate, double-sided sheet.
		if keys.is_empty() and part.material_override is BaseMaterial3D:
			var material := part.material_override as BaseMaterial3D
			if material.cull_mode == BaseMaterial3D.CULL_DISABLED: part.hide()

static func _glass_stream() -> AudioStreamWAV:
	if _glass_sound != null: return _glass_sound
	var samples := 6615
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 7742
	for index in samples:
		var t := float(index) / 22050.0
		var transient := random.randf_range(-1.0, 1.0) * exp(-t * 23.0)
		var chime := (sin(t * 15230.0) + sin(t * 19830.0)) * .14 * exp(-t * 11.0)
		bytes.encode_s16(index * 2, clampi(int((transient * .7 + chime) * 24000), -32768, 32767))
	_glass_sound = AudioStreamWAV.new()
	_glass_sound.format = AudioStreamWAV.FORMAT_16_BITS
	_glass_sound.mix_rate = 22050
	_glass_sound.data = bytes
	return _glass_sound

func dispose() -> void:
	if is_instance_valid(tool): tool.queue_free()
	tool = null
