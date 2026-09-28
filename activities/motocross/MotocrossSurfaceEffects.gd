extends Node3D
## One bounded track-mark batch for the whole event; at most six pairs of small
## emitters. Contacts are real collision ray hits, sampled at 10 Hz, not decals
## floating at the route height. No particles or tire marks are emitted in air.
const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const MAX_MARKS := 2048
const MAX_RIDERS := 6
const SAMPLE_INTERVAL := 0.1
var mark_count := 0
var contact_samples := 0
var _course: Node3D
var _riders: Array = []
var _wetness := 0.0
var _clock := 0.0
var _last_update := -100
var _cursor := 0
var _marks: MultiMeshInstance3D
var _previous: Dictionary = {}
var _emitters: Array[Dictionary] = []
var _dust_process: ParticleProcessMaterial
var _mud_process: ParticleProcessMaterial
var _mud_mesh: SphereMesh

func configure(course: Node3D) -> void:
	_course = course

func _ready() -> void:
	name = "MotocrossSurfaceEffects"
	process_physics_priority = 20
	_build_marks()
	_build_particle_resources()

## Call every gameplay physics frame. The node samples the latest positions
## itself at 10 Hz. Both bike arrays and controller rows {bike: ...} are valid.
func update_riders(riders: Array, wetness: float) -> void:
	_riders = riders
	_wetness = clampf(wetness, 0.0, 1.0) if is_finite(wetness) else 0.0
	_last_update = Engine.get_physics_frames()

func suspend() -> void:
	_riders = []
	_previous.clear()
	for slot in _emitters: _stop_slot(slot)

func _physics_process(delta: float) -> void:
	# If the controller stops updating after a race, emitters stop automatically.
	if Engine.get_physics_frames() - _last_update > 2 or not is_instance_valid(_course):
		if not _riders.is_empty(): suspend()
		return
	_clock += delta
	if _clock < SAMPLE_INTERVAL: return
	_clock = fmod(_clock, SAMPLE_INTERVAL)
	var seen := {}
	for index in mini(MAX_RIDERS, _riders.size()):
		var entry: Variant = _riders[index]
		var bike: Variant = entry.get("bike") if entry is Dictionary else entry
		if not is_instance_valid(bike) or not bike is CharacterBody3D: continue
		var id: int = bike.get_instance_id()
		seen[id] = true
		var slot := _slot(index)
		if absf(bike.speed) < 1.0 or bike.crash_state != "riding" or not bike.race_enabled or not bike.is_on_floor():
			_previous.erase(id)
			_stop_slot(slot)
			continue
		var rear: Vector3 = bike.to_global(Vector3(0.0, 0.36, 0.83))
		if not _course.BOUNDS.grow(1.0).has_point(Vector2(rear.x, rear.z)):
			_previous.erase(id)
			_stop_slot(slot)
			continue
		var query := PhysicsRayQueryParameters3D.create(rear + Vector3.UP * 0.65, rear - Vector3.UP * 1.45, 1)
		query.hit_back_faces = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		contact_samples += 1
		if hit.is_empty() or float(hit.normal.y) < 0.45:
			_previous.erase(id)
			_stop_slot(slot)
			continue
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if _previous.has(id):
			var prior: Dictionary = _previous[id]
			var distance: float = point.distance_to(prior.point)
			if distance >= 0.08 and distance <= 3.5:
				_stamp(prior.point, point, (normal + Vector3(prior.normal)).normalized(), _wetness)
		_previous[id] = {"point": point, "normal": normal}
		_emit(slot, bike, point, normal)
	for id in _previous.keys():
		if not seen.has(id): _previous.erase(id)
	for index in range(mini(MAX_RIDERS, _riders.size()), _emitters.size()): _stop_slot(_emitters[index])

func _build_marks() -> void:
	_marks = MultiMeshInstance3D.new()
	_marks.name = "SharedTireTreadRing"
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
varying float stamp_length;
varying float stamp_wetness;
void vertex() { stamp_length = INSTANCE_CUSTOM.r; stamp_wetness = INSTANCE_CUSTOM.g; }
void fragment() {
 float x = abs(UV.x - 0.5);
 float tread = fract(UV.y * stamp_length * 10.0 + x * 0.8);
 // Gaps and alternating outer knobs read as off-road tire imprints.
 if (tread < 0.19 || x > 0.48 - 0.08 * step(0.64, tread)) { discard; }
 ALBEDO = mix(vec3(0.12,0.038,0.012),vec3(0.045,0.021,0.008),stamp_wetness) * (0.91 + 0.09 * step(0.34, x));
 ROUGHNESS = 0.97;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	mesh.material = material
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_MARKS
	multimesh.visible_instance_count = 0
	_marks.multimesh = multimesh
	add_child(_marks)

func _stamp(a: Vector3, b: Vector3, normal: Vector3, wetness: float) -> void:
	var direction := (b - a).slide(normal).normalized()
	if direction.length_squared() < 0.5: return
	var length := a.distance_to(b)
	var width := lerpf(0.18, 0.25, wetness)
	var side := normal.cross(direction).normalized()
	var basis := Basis(side * width, normal, direction * (length + 0.025))
	var point := (a + b) * 0.5 + normal * 0.027
	# The small lift avoids depth-fighting, with endpoint normals following
	# cambers; no ray or allocation per historical mark is needed thereafter.
	_marks.multimesh.set_instance_transform(_cursor, global_transform.affine_inverse() * Transform3D(basis, point))
	_marks.multimesh.set_instance_color(_cursor, Color("823f25").lerp(Color("452719"), wetness))
	_marks.multimesh.set_instance_custom_data(_cursor, Color(length, wetness, 0.0, 1.0))
	_cursor = (_cursor + 1) % MAX_MARKS
	mark_count = mini(MAX_MARKS, mark_count + 1)
	_marks.multimesh.visible_instance_count = mark_count

func _build_particle_resources() -> void:
	_dust_process = RESOURCES.particle_process()
	_dust_process.direction = Vector3(0.0, 0.6, 0.8)
	_dust_process.spread = 28.0
	_dust_process.initial_velocity_min = 0.6
	_dust_process.initial_velocity_max = 1.7
	_dust_process.gravity = Vector3(0.0, 0.3, 0.0)
	_dust_process.scale_min = 0.65
	_dust_process.scale_max = 1.45
	_dust_process.color = Color(0.67, 0.32, 0.16, 0.45)
	_mud_process = RESOURCES.particle_process()
	_mud_process.direction = Vector3(0.0, 0.75, 0.66)
	_mud_process.spread = 24.0
	_mud_process.initial_velocity_min = 1.8
	_mud_process.initial_velocity_max = 4.3
	_mud_process.gravity = Vector3(0.0, -12.0, 0.0)
	_mud_process.scale_min = 0.5
	_mud_process.scale_max = 1.4
	_mud_process.color = Color("58301b")
	_mud_mesh = SphereMesh.new()
	_mud_mesh.radius = 0.045
	_mud_mesh.height = 0.09
	_mud_mesh.radial_segments = 4
	_mud_mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("58301b")
	material.roughness = 0.94
	_mud_mesh.material = material

func _slot(index: int) -> Dictionary:
	while _emitters.size() <= index:
		var dust := RESOURCES.emitter("ClayDust%d" % _emitters.size(), 18, 0.7, Vector2(0.7, 0.7))
		dust.process_material = _dust_process
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dust)
		var mud := RESOURCES.emitter("MudSpray%d" % _emitters.size(), 14, 0.55, Vector2(0.1, 0.1))
		mud.draw_pass_1 = _mud_mesh
		mud.process_material = _mud_process
		mud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mud)
		_emitters.append({"dust": dust, "mud": mud})
	return _emitters[index]

func _emit(slot: Dictionary, bike: CharacterBody3D, point: Vector3, normal: Vector3) -> void:
	var dust: GPUParticles3D = slot.dust
	var mud: GPUParticles3D = slot.mud
	var direction := bike.global_basis.z.slide(normal).normalized()
	var side := normal.cross(direction).normalized()
	var where := Transform3D(Basis(side, normal, direction), point + normal * 0.055)
	dust.global_transform = where
	mud.global_transform = where
	var landing := clampf(-float(bike.get("_suspension"))*15.0,0.0,.75)
	var intensity := clampf(absf(bike.speed) / 16.0+landing, 0.1, 1.0)
	# Reuse the existing bounded emitters for a denser landing/braking plume.
	if bike.get("_brake")==true: intensity = minf(1.0,intensity+.2)
	dust.amount_ratio = intensity * (1.0 - _wetness)
	mud.amount_ratio = intensity * _wetness
	dust.emitting = _wetness < 0.85
	mud.emitting = _wetness > 0.15

func _stop_slot(slot: Dictionary) -> void:
	slot.dust.emitting = false
	slot.mud.emitting = false
