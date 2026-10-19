extends RefCounted
## Local, matte finish for the authored Police wall boxes. Two shared maps are
## built once; tint variation is deliberately absent from the relief field.
const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const MAP_SIZE := 256
const WALL_COLOR := Color("4f6878")
static var _wall_material: StandardMaterial3D

static func decorate(building: UrbanBuildingBase) -> void:
	if building.building_id != "Police" or not is_instance_valid(building.visuals_root): return
	var root := building.visuals_root
	var body := root.get_node_or_null("PrecinctBody") as MeshInstance3D
	var wing := root.get_node_or_null("PrecinctFrontWing") as MeshInstance3D
	var vestibule := root.get_node_or_null("PrecinctVestibuleSide") as MeshInstance3D
	# Direct children only: never reach interiors or the separate facade dressing.
	# add_solid_box repeats wing/vestibule names. Godot may give the second box
	# an anonymous name, so identify its exact mirrored authored dimensions too.
	for child in root.get_children():
		var wall := child as MeshInstance3D
		if wall == null or not wall.mesh is BoxMesh: continue
		if wall == body or _same_wall_pair(wall, wing) or _same_wall_pair(wall, vestibule):
			wall.material_override = _material()

static func _same_wall_pair(candidate: MeshInstance3D, source: MeshInstance3D) -> bool:
	if source == null or not source.mesh is BoxMesh: return false
	if candidate == source: return true
	var mirrored := Vector3(-source.position.x, source.position.y, source.position.z)
	return candidate.position.is_equal_approx(mirrored) \
		and (candidate.mesh as BoxMesh).size.is_equal_approx((source.mesh as BoxMesh).size)

static func _material() -> StandardMaterial3D:
	if _wall_material != null: return _wall_material
	var albedo := Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var heights := PackedFloat32Array()
	heights.resize(MAP_SIZE * MAP_SIZE)
	var tint_rng := RandomNumberGenerator.new()
	tint_rng.seed = 73041
	var relief_rng := RandomNumberGenerator.new()
	relief_rng.seed = 91327
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			# 4m repeat, 2m by 1.33m panels. Periodic distance and
			# smooth profiles avoid a hard seam at the texture boundary.
			var dx := float(mini(x % 128, 128 - x % 128))
			var panel_y := fposmod(float(y), float(MAP_SIZE)/3.0)
			var dy := minf(panel_y, float(MAP_SIZE)/3.0-panel_y)
			var joint := 1.0 - smoothstep(0.0, 2.5, minf(dx, dy))
			var panel_index := int(x / 128.0) + int(float(y)*3.0/MAP_SIZE)*2
			var panel_tone: float = [-.025,.02,.035,-.015,-.035,.015][panel_index]
			var u := TAU * float(x) / float(MAP_SIZE)
			var v := TAU * float(y) / float(MAP_SIZE)
			var tone := 1.0 + .014 * sin(u + .7) * cos(v - .4) \
				+ .008 * sin(2.0 * u - v) + tint_rng.randf_range(-.012, .012)
			# Keep panel separation readable at gameplay scale; the first 7%
			# trial disappeared after minification. No baked directional light.
			var tint := WALL_COLOR * (tone + float(panel_tone) - joint * .22)
			tint.a = 1.0
			albedo.set_pixel(x, y, tint)
			# Only fine aggregate and recessed joints affect the normals;
			# broad color mottling remains flat, avoiding embossed stains.
			heights[y * MAP_SIZE + x] = .5 - joint * .08 + relief_rng.randf_range(-.006, .006)
	albedo.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.resource_name = "CoastalPoliceMatteMasonry"
	material.albedo_color = Color.WHITE
	material.albedo_texture = ImageTexture.create_from_image(albedo)
	material.normal_enabled = true
	material.normal_texture = SURFACES.normal_from_height(heights, MAP_SIZE, 2.0)
	material.normal_scale = .75
	material.roughness = .92
	material.metallic = 0.0
	material.metallic_specular = .16
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / 4.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_wall_material = material
	return _wall_material
