extends SceneTree
const GRASS:=preload("res://world/urban_detail/CobraVegetation.gd")
const GEOMETRY:=preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const CUT:=preload("res://world/urban_detail/GroundCut.gd")
class District extends Node3D:
	var roads: Array[Dictionary]=[]
	var harbor_road_geometry: RefCounted
	var records: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var district:=District.new()
	root.add_child(district)
	var centre:=Vector3(481.25,0,106.25)
	var ring:=PackedVector3Array()
	for i in 49:
		var angle:=TAU*i/48.0
		ring.append(centre+Vector3(cos(angle)*18.75,0,sin(angle)*18.75))
	for quarter in 4:
		district.roads.append({"id":"cobra_test_ring_%d"%quarter,"points":ring.slice(quarter*12,quarter*12+13),"width":9.0})
	district.roads.append({"id":"cobra_test_path","points":PackedVector3Array([centre+Vector3(-45,0,-30),centre+Vector3(45,0,-30)]),"width":6.0})
	district.harbor_road_geometry=GEOMETRY.new()
	district.harbor_road_geometry.configure(district.roads)
	var parent:=preload("res://world/editing/EditableCobraDressing.gd").new()
	parent.configure("cobra")
	parent.position=centre
	district.add_child(parent)
	var doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/editing/world_edits.json"))
	preload("res://world/editing/WorldEditPieces.gd").apply(parent,doc.regions.harbor)
	parent.finalize_ground()
	var grass:=GRASS.scatter(parent)
	await process_frame
	await process_frame
	var areas:=GRASS._paved_areas(parent,0)
	var grid:=GRASS._paving_grid(areas)
	var invalid:=0
	var checked:=0
	var vertices:PackedVector3Array=grass.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in grass.multimesh.instance_count:
		var transform:Transform3D=grass.global_transform*grass.multimesh.get_instance_transform(i)
		for vertex in vertices:
			var p:=transform*vertex
			checked+=1
			if GRASS._on_paving(Vector2(p.x,p.z),grid.get(Vector2i(floori(p.x/8),floori(p.z/8)),[])): invalid+=1
	var regrown:=GRASS.scatter(parent)
	await process_frame
	await process_frame
	var stable:=regrown.multimesh.instance_count==grass.multimesh.instance_count
	if stable:
		for i in grass.multimesh.instance_count:
			if regrown.multimesh.get_instance_transform(i)!=grass.multimesh.get_instance_transform(i): stable=false; break
	var ok:bool=areas.size()>district.harbor_road_geometry._layers[0].polygons.size() and invalid==0 and grass.multimesh.instance_count>500 and stable
	print("COBRA_GRASS_PAVING final_paving_polygons=",areas.size()," tufts=",grass.multimesh.instance_count," vertices=",checked," on_pavement=",invalid," deterministic=",stable)
	district.free()
	quit(0 if ok else 1)
