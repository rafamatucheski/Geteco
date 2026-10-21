extends RefCounted
## Permanent, bounded stains: one overlay per exterior mesh, no frame callback.
const SHADER := preload("res://gameplay/vehicle_effects/VehicleBlood.gdshader")

static func valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= 0 and value <= 15

static func impact_side(car: Node3D, heading: Vector3) -> int:
	var local := car.global_basis.inverse() * heading
	if absf(local.z) >= absf(local.x): return 1 if local.z < 0 else 2
	return 4 if local.x < 0 else 8

static func eligible(part: MeshInstance3D, visual: Node3D) -> bool:
	if part.mesh == null: return false
	# Steering forks/fenders carry wheel_center too, but do not spin with tires.
	# Their exported names contain "wheel"; name filtering hid blood on bikes.
	if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true): return false
	var ancestor: Node = part
	while ancestor != null and ancestor != visual:
		if ancestor.get_meta("motorcycle_rider",false): return false
		ancestor = ancestor.get_parent()
	var path := str(visual.get_path_to(part)).to_lower()
	return "interior" not in path and "rider" not in path

static func apply(car: Node3D, mask: int) -> void:
	mask = clampi(mask, 0, 15)
	car.set_meta("blood_stains", mask)
	var visual: Node3D = car.get("visual")
	if not is_instance_valid(visual): return
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if not eligible(part,visual): continue
		var material := part.material_overlay as ShaderMaterial
		if material != null and material.shader == SHADER:
			if mask == 0: part.material_overlay = null
			else: material.set_shader_parameter("stains", mask)
			continue
		if mask == 0 or part.material_overlay != null: continue
		material = ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("part_to_car", car.global_transform.affine_inverse() * part.global_transform)
		material.set_shader_parameter("half_length", float(car.get("half_length")))
		# Bike collision bounds include handlebars; their narrow tank/fairings sit
		# inside that width and otherwise receive almost no lateral splatter.
		var width := float(car.get("half_width"))
		if str(car.get("archetype")).begins_with("bike_"): width=minf(width,.26)
		material.set_shader_parameter("half_width", width)
		material.set_shader_parameter("stains", mask)
		part.material_overlay = material
