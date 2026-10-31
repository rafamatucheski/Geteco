extends RefCounted
## Authored Police upper glazing between the existing concrete pilasters.
## Two static meshes, one shader material per facade; no lights, collision,
## scene scans, per-frame work or private reflection camera.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const GLASS_SHADER := preload("res://world/city_look/coastal_facade_glass.gdshader")
const MASONRY := preload("res://world/city_look/CoastalMasonryFinish.gd")
const REFLECTION_GROUP := &"coastal_reflective_facade"
const ROOT_NAME := "CoastalFacadeFinish"

static func decorate(building: UrbanBuildingBase) -> MeshInstance3D:
	if building.building_id != "Police" or not is_instance_valid(building.visuals_root): return null
	MASONRY.decorate(building)
	var existing := building.visuals_root.get_node_or_null(ROOT_NAME + "/FrontGlazing")
	if existing is MeshInstance3D: return existing
	var bottom := 4.12
	var top := building.height - .38
	if top <= bottom + .8: return null
	var finish := Node3D.new()
	finish.name = ROOT_NAME
	building.visuals_root.add_child(finish)
	var glass := ShaderMaterial.new()
	glass.resource_name = "CoastalPoliceGlazing"
	glass.shader = GLASS_SHADER
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color.WHITE
	frame.vertex_color_use_as_albedo = true
	frame.vertex_color_is_srgb = true
	frame.roughness = .88
	frame.metallic = 0.0
	var mullion_color := Color("41545d")
	var reveal_color := Color("96988f")
	var panes := SurfaceTool.new()
	var joints := SurfaceTool.new()
	panes.begin(Mesh.PRIMITIVE_TRIANGLES)
	joints.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Mesmo espaçamento de PoliceStationDressing._facade; alvenaria sólida continua em
	# cada pilastra, na cornija e nas duas elevações laterais. Portas do térreo,
	# colisão, janelas de segurança e grades mantêm a geometria original.
	var count := maxi(1, int(building.building_size.x / 2.2))
	var span := (building.building_size.x - .3) / float(count)
	var first := -building.building_size.x * .5 + .15
	var front := building.building_size.y * .5 + .04
	var floors := maxi(1, int((top - bottom) / 1.65))
	glass.set_shader_parameter("facade_height_range", Vector2(bottom, top))
	glass.set_shader_parameter("facade_pane_layout", Vector2(first, span))
	glass.set_shader_parameter("facade_floor_height", (top - bottom) / float(floors))
	for index in count:
		var x := first + (float(index) + .5) * span
		var width := maxf(.1, span - .39)
		_append_box(panes, Vector3(x, (bottom + top) * .5, front - .008), Vector3(width, top - bottom, .016))
		for level in range(1, floors):
			var y := lerpf(bottom, top, float(level) / float(floors))
			_append_box(joints, Vector3(x, y, front + .013), Vector3(width, .025, .016), mullion_color)
		for y in [bottom, top]:
			_append_box(joints, Vector3(x, y, front + .013), Vector3(width, .04, .016), mullion_color)
		# Os recuos ocupam só o vão existente de 4.5cm entre vidraça e pilastra.
		# As faces laterais expostas dão profundidade real, sem engrossar/substituir
		# as colunas originais nem mudar o plano de reflexo frontal.
		for side in [-1.0, 1.0]:
			_append_box(joints, Vector3(x + side * (width * .5 + .0225), (bottom + top) * .5, front + .044), Vector3(.045, top - bottom, .088), reveal_color)
		_append_box(joints, Vector3(x, top + .015, front + .044), Vector3(width + .09, .06, .088), reveal_color)
		_append_box(joints, Vector3(x, bottom - .02, front + .06), Vector3(width + .09, .08, .12), reveal_color)
	var visual := _install(finish, "FrontGlazing", panes, glass)
	_install(finish, "GlazingMullions", joints, frame)
	# Os três transforms abaixo de visuals_root são identidade. O metadado é LOCAL
	# ao MeshInstance3D registrado, então um seletor pode usar o global_transform dele
	# para ponto e normal, incluindo rotação do prédio/espelhamento da entrada.
	visual.set_meta("coastal_reflection_plane_normal", Vector3.FORWARD * -1.0)
	visual.set_meta("coastal_reflection_plane_point", Vector3(0, 0, front))
	visual.set_meta("coastal_reflection_panes", count)
	visual.add_to_group(REFLECTION_GROUP)
	return visual

static func _append_box(surface: SurfaceTool, center: Vector3, size: Vector3, tint := Color.WHITE) -> void:
	var box := BoxMesh.new()
	box.size = size
	if tint == Color.WHITE:
		surface.append_from(box, 0, Transform3D(Basis.IDENTITY, center))
		return
	# Acabamentos foscos diferentes dividem uma superfície/material em vez de somar uma
	# malha de desenho por quadro. Esta construção só roda quando o chunk carrega.
	var arrays := MESH_ARRAYS.arrays_of(box, 0).duplicate()
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(tint)
	arrays[Mesh.ARRAY_COLOR] = colors
	var colored := ArrayMesh.new()
	colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.append_from(colored, 0, Transform3D(Basis.IDENTITY, center))

static func _install(parent: Node3D, label: String, surface: SurfaceTool, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = surface.commit()
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual
