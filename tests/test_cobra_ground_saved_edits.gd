extends SceneTree
const DRESSING := preload("res://world/editing/EditableCobraDressing.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const GROUND := preload("res://world/urban_detail/HarborDressingGround.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures+=1; push_error(label)

func coverage(parent: Node3D) -> Dictionary:
	var covered := {}
	for node in parent.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null: continue
		var label := str(node.get_meta("harbor_ground_label",node.name))
		if not GROUND._is_ground(label) and label!="ReservedGroundInfill": continue
		var faces := GROUND._render_faces(node.mesh)
		for i in range(0,faces.size(),3):
			var polygon := PackedVector2Array()
			for j in 3:
				var p: Vector3=node.global_transform*faces[i+j]
				polygon.append(Vector2(p.x,p.z))
			var bounds:=CUT.bounds(polygon)
			for x in range(floori(bounds.position.x),ceili(bounds.end.x)):
				for z in range(floori(bounds.position.y),ceili(bounds.end.y)):
					var p:=Vector2(x+.4637,z+.4637)
					if Geometry2D.point_is_inside_triangle(p,polygon[0],polygon[1],polygon[2]):
						var key:=Vector2i(x,z)
						covered[key]=int(covered.get(key,0))+1
	return covered

func run() -> void:
	var doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/editing/world_edits.json"))
	var dressing:=DRESSING.new()
	dressing.configure("cobra")
	dressing.position=Vector3(481.25,0,106.25)
	dressing.set_meta("harbor_ground_fill_reservation",true)
	root.add_child(dressing)
	var outline_count:=0
	for piece in PIECES.collect(dressing):
		var id:="piece/"+str(piece.get_meta("world_edit_piece_id"))
		var row:Dictionary=doc.regions.harbor.get(id,{})
		if row.get("outline",[]).size()>=3:
			outline_count+=1
			check(not PIECES.shape_info(piece).is_empty(),"Saved outline retains primitive shape information: "+id)
	check(outline_count>0,"Actual document exercises edited polygon outlines")
	PIECES.apply(dressing,doc.regions.harbor)
	dressing.finalize_ground()
	var first:=coverage(dressing)
	var holes:=0
	var stacks:=0
	var reservations:=GROUND.footprints("cobra",Vector2(481.25,106.25))
	for x in range(405,534):
		for z in range(59,153):
			var p:=Vector2(x+.4637,z+.4637)
			var reserved:=false
			for polygon in reservations:
				if Geometry2D.is_point_in_polygon(p,polygon): reserved=true; break
			if not reserved: continue
			var count:int=first.get(Vector2i(x,z),0)
			if count==0:
				holes+=1
				if holes<5: print("COBRA_HOLE ",p)
			if count>1: stacks+=1
	check(holes==0,"No sky gaps after actual saved path deletes/moves/outlines")
	check(stacks==0,"Reserved ground contains one visible floor layer")
	PIECES.apply(dressing,doc.regions.harbor)
	dressing.finalize_ground()
	check(first==coverage(dressing),"Reapplying saved edits preserves ground coverage")
	check(CUT.failed_triangulations==0,"All ground polygons triangulate")
	print("COBRA_SAVED_GROUND outlines=",outline_count," holes=",holes," stacks=",stacks," triangulation_failures=",CUT.failed_triangulations," failures=",failures)
	dressing.free()
	quit(0 if failures==0 else 1)
