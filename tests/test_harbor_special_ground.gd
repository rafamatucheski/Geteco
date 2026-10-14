extends SceneTree
## Exterior ground ownership only; no interior setup or gameplay mutation.
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const SALVAGE := preload("res://world/places/SalvageYardNative.gd")
const TERMINAL := preload("res://world/urban_detail/HarborTerminalModel3D.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")
var failures := 0
class FacadeContext extends Node3D:
	var harbor_road_geometry = null
	var harbor_facade_ground: Array[PackedVector2Array] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size(): result += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(result)*.5

func inspect(meshes: Array[MeshInstance3D], expected: float, label: String) -> void:
	var triangles: Array[PackedVector2Array] = []
	var total := 0.0
	for node in meshes:
		if node.mesh == null: continue
		# get_faces() routes through TriangleMesh's snapped collision vertices.
		# Inspect the actual render buffers, preserving shared-edge precision.
		var faces := PackedVector3Array()
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty(): faces.append_array(vertices)
			else:
				for index in indices: faces.append(vertices[index])
		for i in range(0,faces.size(),3):
			var a: Vector3 = node.global_transform*faces[i]
			var b: Vector3 = node.global_transform*faces[i+1]
			var c: Vector3 = node.global_transform*faces[i+2]
			if absf(a.y-b.y)>.0001 or absf(a.y-c.y)>.0001: continue
			var polygon := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
			if area(polygon)<.000001: continue
			for previous in triangles:
				if not CUT.bounds(previous).intersects(CUT.bounds(polygon)): continue
				for overlap in Geometry2D.intersect_polygons(previous,polygon):
					if area(overlap)>=.0001: print("GROUND_OVERLAP area=",area(overlap)," prior=",previous," current=",polygon," intersection=",overlap)
					check(area(overlap)<.0001,label+": no overlapping floor triangles")
			total += area(polygon)
			triangles.append(polygon)
	check(absf(total-expected)<.02,label+": complete coverage, no lost ground (%f/%f)"%[total,expected])
	print("SPECIAL_GROUND ",label," triangles=",triangles.size()," area=",total)

func run() -> void:
	var cemetery := CEMETERY.new()
	root.add_child(cemetery)
	var meshes: Array[MeshInstance3D] = []
	for node in cemetery.get_children():
		if node is MeshInstance3D and node.has_meta("harbor_owned_ground"): meshes.append(node)
	inspect(meshes,(780.0*700.0+50.0*140.0)/256.0,"cemetery paths/lawn")
	check(cemetery.solids.get_child_count()>0,"Cemetery physical support remains")
	cemetery.free()
	# The standalone fixture above has no region reservation. Exercise the real
	# keeper floor union separately: foundation plus only the protruding step.
	var context := FacadeContext.new()
	context.harbor_facade_ground = preload("res://world/urban_detail/HarborFacadeGround.gd").footprints()
	root.add_child(context)
	cemetery = CEMETERY.new()
	cemetery.position = CEMETERY.world_position()
	context.add_child(cemetery)
	meshes.clear()
	for node in cemetery.get_children():
		if node is MeshInstance3D and node.has_meta("harbor_owned_ground"): meshes.append(node)
	var keeper_floor_area := 7.6*5.9 + 1.6*(3.395-2.95)
	inspect(meshes,(780.0*700.0+50.0*140.0)/256.0-keeper_floor_area,"cemetery with keeper floor reserved")
	check(cemetery.solids.get_child_count()>0,"Keeper reservation preserves cemetery support")
	context.free()
	var salvage := SALVAGE.new()
	root.add_child(salvage)
	meshes.clear()
	for node in salvage.find_children("*","MeshInstance3D",true,false):
		if node.mesh is ArrayMesh and node.material_override in [salvage._mat("706a56"),salvage._mat("888c7f")]: meshes.append(node)
	inspect(meshes,736.0,"salvage gravel/concrete")
	salvage.free()
	var terminal := TERMINAL.new()
	root.add_child(terminal)
	inspect(terminal._ground_slabs,598.0*409.0/(TERMINAL.PPM*TERMINAL.PPM*TERMINAL.FLOOR_Y),"terminal aprons/platforms")
	terminal.free()
	print("HARBOR_SPECIAL_GROUND failures=",failures)
	quit(0 if failures==0 else 1)
