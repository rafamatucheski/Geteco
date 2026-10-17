extends SceneTree
const TONES = preload("res://world/city_look/HarborFacadeTones.gd")
const ROOFS = preload("res://world/city_look/RoofSurfaces.gd")
const SURFACE = preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var ground = SURFACE.new()
	ground.configure()
	var styles := {}
	var overlap := 0.0
	for i in ground._visible_surfaces.size():
		var a = ground._visible_surfaces[i]
		styles[a.kind] = true
		for j in range(i+1,ground._visible_surfaces.size()):
			overlap += (a.rect as Rect2).intersection(ground._visible_surfaces[j].rect).get_area()
	check(overlap < .001,"Pavement finishes must replace each other without overlaps")
	check(styles.size() >= 5,"Courts must no longer all use one finish")
	for source in ground._surfaces:
		var at: Vector2 = source.rect.get_center()
		var owners := 0
		for visible in ground._visible_surfaces:
			if visible.rect.has_point(at): owners += 1
		check(owners == 1,"Every authored lot centre remains covered once")
	var chunk := Node3D.new()
	root.add_child(chunk)
	var building := UrbanBuildingBase.new()
	building.building_id = "FoundryLofts"
	chunk.add_child(building)
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	wall.mesh.size = Vector3(8,6,8)
	var original := StandardMaterial3D.new()
	wall.material_override = original
	building.add_child(wall)
	var glass := MeshInstance3D.new()
	glass.mesh = wall.mesh
	glass.material_override = StandardMaterial3D.new()
	glass.material_override.emission_enabled = true
	building.add_child(glass)
	var glass_mesh := glass.mesh
	var batched_trim := MultiMeshInstance3D.new()
	batched_trim.multimesh = MultiMesh.new()
	batched_trim.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batched_trim.multimesh.use_colors = true
	batched_trim.multimesh.mesh = BoxMesh.new()
	batched_trim.multimesh.instance_count = 1
	batched_trim.multimesh.set_instance_color(0,Color(.7,.8,.6,1.0))
	batched_trim.material_override = UrbanMaterials.trim_stone()
	building.add_child(batched_trim)
	var original_trim := batched_trim.material_override as StandardMaterial3D
	var original_trim_color := original_trim.albedo_color
	var original_instances := batched_trim.multimesh
	var original_instance_color := original_instances.get_instance_color(0)
	var child_count := building.get_child_count()
	TONES.apply(chunk)
	check(wall.mesh is ArrayMesh,"Existing wall receives vertex colours")
	check(wall.mesh.get_surface_count() == 1,"No added wall surfaces")
	check(building.get_child_count() == child_count,"No added mesh nodes")
	check(glass.mesh == glass_mesh,"Emissive windows unchanged")
	check(not original.vertex_color_use_as_albedo,"Shared original material unchanged")
	check(batched_trim.multimesh == original_instances and batched_trim.multimesh.get_instance_color(0) == original_instance_color,"Batched trim preserves geometry and per-instance RGB variation")
	check(original_trim.albedo_color == original_trim_color,"Shared source stone remains unchanged outside Harbor")
	check(batched_trim.material_override.albedo_color.get_luminance() < original_trim_color.get_luminance(),"Existing batched stone finish is aged rather than left white")
	var arrays = wall.mesh.surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var color: Color = arrays[Mesh.ARRAY_COLOR][i]
		var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][i]
		if absf(normal.y) <= .35:
			check(color.get_luminance() < .65 and color.get_luminance() > .10,"Facade palette stays darker than white, with readable colour")
	check(wall.mesh.surface_get_material(0).albedo_texture != null,"Replacement wall has an actual shared surface texture")
	check(not wall.mesh.surface_get_material(0).uv1_triplanar,"Facade UVs are baked, avoiding extra triplanar samples")
	var once := wall.mesh
	TONES.apply(chunk)
	check(once == wall.mesh,"Streaming dressing is idempotent")
	var roof := building.find_child("V1RoofSurface",true,false) as MeshInstance3D
	check(roof != null,"Fixture includes an authored source roof")
	if roof != null:
		var roof_mesh := roof.mesh
		var roof_transform := roof.transform
		var roof_children := building.find_children("*","MeshInstance3D",true,false).size()
		ROOFS.replace_existing(building,building.building_kind,building.building_id)
		check(roof.mesh == roof_mesh and roof.transform == roof_transform,"Roof replacement keeps physical geometry and height")
		check(building.find_children("*","MeshInstance3D",true,false).size() == roof_children,"Roof finish introduces no overlay mesh")
		check(roof.material_override.albedo_texture != null,"Roof finish replaces existing material with textured material")
	chunk.free()
	print("HARBOR_MATERIAL_DIVERSITY failures=",failures," overlaps_m2=",overlap," styles=",styles.keys())
	quit(0 if failures == 0 else 1)
