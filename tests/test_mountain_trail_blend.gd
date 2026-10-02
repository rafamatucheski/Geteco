extends SceneTree
const BLEND := preload("res://world/regions/MountainTrailBlend.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var road := {"points":PackedVector3Array([Vector3(40,0,-20),Vector3(90,0,20)]),"width":2.0,"surface":"dirt"}
	var other := {"points":PackedVector3Array([Vector3(60,0,-20),Vector3(60,0,20)]),"width":2.0,"surface":"dirt"}
	var blend := BLEND.new()
	blend.configure([road,other])
	var a := blend.image_for(Rect2(0,-64,64,64))
	var b := blend.image_for(Rect2(64,-64,64,64))
	var c := blend.image_for(Rect2(0,0,64,64))
	for i in 129:
		check(a.get_pixel(128,i) == b.get_pixel(0,i),"X seam sample "+str(i))
		check(a.get_pixel(i,128) == c.get_pixel(i,0),"Z seam sample "+str(i))
	var copy := BLEND.new()
	copy.configure([road,other,road,other])
	check(copy.image_for(Rect2(0,-64,64,64)).get_data() == a.get_data(),"Duplicate routes do not darken a crossing")
	check(c.get_pixel(120,0).r > .99,"Path center survives crossing")
	check(c.get_pixel(0,128).r == 0,"Unrelated ground untouched")
	var terrain := TERRAIN.new()
	terrain.configure([road,other],[],[])
	var host := Node3D.new()
	root.add_child(host)
	var mesh := terrain.build_chunk(host,Rect2(0,0,64,64))
	check(mesh.material_override.get_shader_parameter("trail_mask") is ImageTexture,"Terrain owns union texture")
	check(mesh.get_child(0) is StaticBody3D,"Real terrain keeps physical support")
	var arrays := mesh.mesh.surface_get_arrays(0)
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		check(is_equal_approx(vertex.y,terrain.surface_height_at(Vector2(vertex.x,vertex.z))),"Render and support keep same height")
	host.free()
	print("TRAIL_BLEND ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
