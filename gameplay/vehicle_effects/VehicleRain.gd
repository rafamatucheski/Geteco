extends Node
## Wet paint and millimetre-scale beads. Beads use an independent pass so damage
## normals, paint textures and door/body mesh changes cannot erase them.
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const DROP_SHADER := preload("res://gameplay/vehicle_effects/VehicleBodyRain.gdshader")
const STEP := .25
const NEAR := 160.0
const RAY_NEAR := 90.0
const WET_RISE_SECONDS := 14.0
const DRY_SECONDS := 120.0
const LEVELS := 20.0
const WET_MIN_ROUGHNESS := .2
var weather: Node
var _clock := 0.0
var _query := PhysicsRayQueryParameters3D.new()

static func enabled() -> bool:
	return OS.get_environment("HARBOR_VEHICLE_RAIN") != "0" and "--no-vehicle-rain" not in OS.get_cmdline_user_args()

func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < STEP: return
	var dt := _clock
	_clock = 0.0
	if not enabled() or weather == null or DisplayServer.get_name() == "headless": return
	var controller = weather.get("controller")
	if controller == null: return
	var focus: Vector3 = ATMOSPHERE.focus_position(controller)
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		if vehicle is Node3D and is_instance_valid(vehicle) and vehicle.is_inside_tree(): _step(vehicle, focus, dt)

func _step(vehicle: Node3D, focus: Vector3, dt: float) -> void:
	var wet := float(vehicle.get_meta("rain_wet", 0.0))
	var point := vehicle.global_position
	var near := point.distance_squared_to(focus) < NEAR * NEAR
	var rain: float = weather.rain_strength_at(point)
	var exposed: bool = rain > .05 and not weather.atmosphere.SHELTER.sheltered(point)
	if exposed and point.distance_squared_to(focus) < RAY_NEAR * RAY_NEAR: exposed = not _covered(vehicle, point)
	if exposed: wet = minf(1.0, wet + dt / WET_RISE_SECONDS * (.35 + .65 * rain))
	elif wet > 0.0: wet = maxf(0.0, wet - dt / DRY_SECONDS)
	vehicle.set_meta("rain_wet", wet)
	# Rainfall controls new beads; accumulated wetness controls the lasting film.
	var falling := roundf((rain if exposed else 0.0) * LEVELS) / LEVELS
	var changed := not is_equal_approx(float(vehicle.get_meta("rain_falling", -1.0)), falling)
	vehicle.set_meta("rain_falling", falling)
	if not near: return
	var level := roundf(wet * LEVELS)
	var applied := float(vehicle.get_meta("rain_level", 0.0))
	if level == applied and not changed and not (level > 0.0 and _needs_refresh(vehicle)): return
	vehicle.set_meta("rain_level", level)
	apply(vehicle, level / LEVELS)

func _covered(vehicle: Node3D, point: Vector3) -> bool:
	var space := vehicle.get_world_3d().direct_space_state
	_query.from = point + Vector3.UP * 1.4
	_query.to = point + Vector3.UP * 14.0
	_query.collision_mask = 7
	_query.exclude = [vehicle.get_rid()] if vehicle is CollisionObject3D else []
	var hit := space.intersect_ray(_query)
	return not hit.is_empty() and hit.collider is StaticBody3D and not (hit.collider as Node).is_in_group("drivable")

static func apply(vehicle: Node3D, wet: float) -> void:
	var paint = vehicle.get("_paint")
	if paint == null: return
	# Primeira vez molhado: a pintura troca de variante num carro já desenhado (sonda, 27/10).
	if wet > 0.0 and is_instance_valid(preload("res://runtime/PipelineProbe.gd")._instance) and not vehicle.has_meta("probe_wet_noted"):
		vehicle.set_meta("probe_wet_noted", true)
		preload("res://runtime/PipelineProbe.gd").note("paint_wet", vehicle)
	var visual = vehicle.get("visual")
	var dirt := 0
	if is_instance_valid(visual): dirt = (visual.get_meta("usage_profile", Vector2i.ZERO) as Vector2i).x
	var falling := float(vehicle.get_meta("rain_falling", wet))
	var identity := str(vehicle.get("vehicle_id"))
	var pattern := float(absi(identity.hash() if not identity.is_empty() else vehicle.get_instance_id()) % 8191)
	for material: StandardMaterial3D in paint.materials:
		_apply_material(material, wet, wet * (1.0 - .3 * dirt), 1.0 - .25 * dirt, falling, pattern)

static func apply_material_for_test(material: StandardMaterial3D, wet: float, gloss: float, bead: float) -> void:
	_apply_material(material, wet, gloss, bead, wet, 0.0)

## Restore only fields still owned by rain. A new paint colour or finish written
## by another system is retained independently, never used as a reason to darken
## the already-wet colour a second time.
static func remove_weather_for_edit(material: StandardMaterial3D) -> Dictionary:
	var record: Dictionary = material.get_meta("rain_base", {})
	if record.is_empty(): return {}
	var base: Array = record.base
	var output: Array = record.out
	if is_equal_approx(material.roughness, float(output[0])): material.roughness = base[0]
	if is_equal_approx(material.clearcoat, float(output[1])): material.clearcoat = base[1]
	if material.albedo_color.is_equal_approx(output[2]): material.albedo_color = base[2]
	material.remove_meta("rain_base")
	return record

static func reapply_after_edit(material: StandardMaterial3D, record: Dictionary) -> void:
	if record.is_empty(): return
	_apply_material(material, record.wet, record.gloss, record.bead, record.falling, record.pattern)

static func _apply_material(material: StandardMaterial3D, wet: float, gloss: float, bead: float, falling: float, pattern: float) -> void:
	remove_weather_for_edit(material)
	if wet <= 0.0:
		_remove_beads(material)
		return
	var base := [material.roughness, material.clearcoat, material.albedo_color]
	material.roughness = maxf(minf(WET_MIN_ROUGHNESS, float(base[0])), float(base[0]) * (1.0 - .6 * gloss))
	if material.clearcoat_enabled: material.clearcoat = lerpf(float(base[1]), 1.0, gloss * .75)
	var albedo: Color = base[2]
	material.albedo_color = Color(albedo.r * (1.0 - .24 * wet), albedo.g * (1.0 - .24 * wet), albedo.b * (1.0 - .24 * wet), albedo.a)
	var drops: ShaderMaterial = material.get_meta("rain_drops") if material.has_meta("rain_drops") else null
	if drops == null:
		drops = ShaderMaterial.new()
		drops.shader = DROP_SHADER
		material.set_meta("rain_drops", drops)
	if not has_beads(material):
		# Preserve an existing extra finish instead of overwriting its chain.
		drops.next_pass = material.next_pass
		material.next_pass = drops
	drops.set_shader_parameter("wet", wet)
	drops.set_shader_parameter("falling", falling)
	drops.set_shader_parameter("pattern_seed", pattern)
	drops.set_shader_parameter("bead_visibility", bead)
	drops.set_shader_parameter("paint_color", material.albedo_color)
	material.set_meta("rain_base", {"base":base,"out":[material.roughness,material.clearcoat,material.albedo_color],"wet":wet,"gloss":gloss,"bead":bead,"falling":falling,"pattern":pattern})

static func _remove_beads(material: StandardMaterial3D) -> void:
	var drops: ShaderMaterial = material.get_meta("rain_drops") if material.has_meta("rain_drops") else null
	if drops == null: return
	if material.next_pass == drops: material.next_pass = drops.next_pass
	else:
		var cursor := material.next_pass
		while cursor != null and cursor.next_pass != drops: cursor = cursor.next_pass
		if cursor != null: cursor.next_pass = drops.next_pass
	material.remove_meta("rain_drops")

static func has_beads(material: StandardMaterial3D) -> bool:
	var drops: ShaderMaterial = material.get_meta("rain_drops") if material.has_meta("rain_drops") else null
	if drops == null: return false
	var cursor := material.next_pass
	while cursor != null:
		if cursor == drops: return true
		cursor = cursor.next_pass
	return false

static func _needs_refresh(vehicle: Node3D) -> bool:
	var paint = vehicle.get("_paint")
	if paint == null: return false
	for material: StandardMaterial3D in paint.materials:
		var record: Dictionary = material.get_meta("rain_base", {})
		if record.is_empty() or not has_beads(material): return true
		if not is_equal_approx(float(record.falling), float(vehicle.get_meta("rain_falling", record.falling))): return true
		var output: Array = record.out
		if not is_equal_approx(material.roughness, float(output[0])) or not is_equal_approx(material.clearcoat, float(output[1])) or not material.albedo_color.is_equal_approx(output[2]): return true
	return false

static func warm_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DROP_SHADER
	material.set_shader_parameter("wet", 1.0)
	material.set_shader_parameter("falling", 1.0)
	return material
