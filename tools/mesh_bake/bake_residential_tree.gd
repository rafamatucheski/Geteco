extends SceneTree
## Bake offline: mantém leituras de malha da GPU fora do streaming residencial.
const OUTPUT := "res://assets/urban_detail/residential_tree.res"
func _initialize() -> void: bake.call_deferred()
func bake() -> void:
	var mesh := build_mesh()
	assert(ResourceSaver.save(mesh, OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
	var loaded := ResourceLoader.load(OUTPUT, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	assert(loaded.get_surface_count() == mesh.get_surface_count())
	assert(loaded.get_aabb() == mesh.get_aabb())
	for surface in mesh.get_surface_count():
		assert(loaded.surface_get_arrays(surface) == mesh.surface_get_arrays(surface))
	print("RESIDENTIAL_TREE_BAKE PASS: two surfaces, identical arrays and bounds after reload")
	quit()
func build_mesh() -> ArrayMesh:
	var _mesh: ArrayMesh
	_mesh = ArrayMesh.new()
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.append_from(preload("res://world/urban_detail/StreetTreeWood.gd").mesh(),0,Transform3D(Basis.from_scale(Vector3(.85,.88,.85)),Vector3.ZERO))
	wood.set_material(preload("res://assets/urban_detail/FloraSurfaces.gd").bark())
	wood.commit(_mesh)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crowns := [Vector3(-.55,3.1,0),Vector3(.54,3.2,.15),Vector3(0,3.65,-.25),Vector3(.12,2.9,.58),Vector3(-.4,3.6,.37),Vector3(.42,3.8,.17),Vector3(0,3.25,-.66)]
	for i in crowns.size():
		var shape := preload("res://world/urban_detail/StreetTreeCanopy.gd").mesh(i)
		var pose := Transform3D(Basis(Vector3.UP,float(i)*1.73).scaled(Vector3(.77,.68,.73)),crowns[i])
		leaves.append_from(shape,0,pose)
	leaves.set_material(preload("res://assets/urban_detail/FloraSurfaces.gd").foliage(Color("526b43")))
	leaves.commit(_mesh)
	return _mesh
