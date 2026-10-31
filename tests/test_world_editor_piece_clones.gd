extends SceneTree
## As peças autorais precisam copiar com colisão, sobreviver à exclusão da origem e carregar em streaming de forma independente.
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const SESSION := preload("res://world/editing/WorldSessionEdits.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func find_piece(node: Node, id: String) -> Node3D:
	for piece in PIECES.collect(node):
		if "piece/" + str(piece.get_meta("world_edit_piece_id")) == id: return piece
	return null

func run() -> void:
	var base := REGION.build_region("harbor")
	base.prepare_data()
	var source := {}
	var origin_cell := Vector2i.ZERO
	for cell in base.records:
		for record in base.records[cell]:
			if record.kind == "salvage":
				source = record
				origin_cell = cell
	check(not source.is_empty(), "Production salvage record exists")
	if source.is_empty(): base.free(); quit(1); return
	var source_id := "piece/neco/Office"
	var clone_id := "piece/clone/authored_remote"
	var doc := DATA.empty_document()
	doc.regions.harbor[clone_id] = {"id":clone_id,"type":"piece","clone_of":source_id,"source_record":PIECES.record_key(source),"position":[2200.0,2200.0],"rotation":37.0}
	doc.regions.harbor[source_id] = {"id":source_id,"type":"piece","source_record":PIECES.record_key(source),"deleted":true}
	Engine.set_meta("geteco_world_edit_document",doc)
	var region := REGION.build_region("harbor")
	region.prepare_data()
	Engine.remove_meta("geteco_world_edit_document")
	var destination := Vector2i(34,34)
	check(region.records.has(destination), "Remote pasted piece creates destination streaming record")
	var holder := Node3D.new()
	root.add_child(holder)
	for record in region.records.get(destination,[]):
		if record.kind == "salvage": region._build_record(holder,record)
	var clone := find_piece(holder,clone_id)
	check(clone != null, "Authored office copy reconstructs even when source was deleted")
	check(PIECES.collect(holder).size() == 1, "Destination contains only requested copy")
	if clone != null:
		check(clone.global_position.is_equal_approx(Vector3(2200,0,2200)), "Copy restores world position")
		check(clone.find_children("*","StaticBody3D",true,false).size() == 1, "Copy carries office collision")
		check(is_equal_approx(clone.rotation.y,deg_to_rad(37)), "Copy restores rotation")
	holder.free()
	holder = Node3D.new()
	root.add_child(holder)
	for record in region.records[origin_cell]:
		if record.kind == "salvage": region._build_record(holder,record)
	check(find_piece(holder,source_id) == null, "Deleted source stays absent")
	check(find_piece(holder,clone_id) == null, "Remote copy is absent from source chunk")
	check(find_piece(holder,"piece/neco/Barrel0") != null, "Unrelated authored furniture stays present")
	holder.free()
	region.free()
	base.free()
	var session_copy: Dictionary = doc.regions.harbor[clone_id].duplicate(true)
	session_copy.clone_of = "piece/unit/harbor/s_vertice/test~0_0"
	var session_doc := DATA.empty_document()
	session_doc.regions.harbor[clone_id] = session_copy
	var watcher := SESSION.install(self,root,session_doc)
	check(watcher != null, "A copied session piece installs the production edit watcher")
	if watcher != null:
		check(watcher.changes.has(clone_id), "Session watcher retains the clone edit")
		watcher.free()
	check_shape_copy()
	print("WORLD_EDITOR_PIECE_CLONES checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func check_shape_copy() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var original := Node3D.new()
	holder.add_child(original)
	PIECES.mark(original,"cobra/cobra_footpath/0","Path")
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(2,.05,2)
	original.add_child(mesh)
	# Cache contains a reference to the original mesh, which a copy cannot reuse.
	original.set_meta("world_edit_shape_info",PIECES.shape_info(original))
	var row := {"id":"piece/clone/path","type":"piece","clone_of":"piece/cobra/cobra_footpath/0","source_record":"test","position":[10,10],"rotation":0.0,"outline":[[-2,-1],[2,-1],[2,1],[-2,1]],"stretch":[5.0,.05]}
	check(DATA.validate_entity(row).is_empty(), "Copied editable path accepts its authored contour")
	PIECES.spawn_clones(original,{row.id:row})
	PIECES.spawn_clones(original,{row.id:row})
	var clone := find_piece(holder,row.id)
	check(PIECES.collect(holder).size() == 2, "Reapplying clone construction does not duplicate copies")
	check(mesh.mesh is BoxMesh, "Deforming the copy preserves source mesh")
	if clone != null:
		var copied_mesh: MeshInstance3D = clone.get_child(0)
		check(copied_mesh.mesh is ArrayMesh, "Copied contour deforms the copied mesh")
		check(is_equal_approx(copied_mesh.global_basis.x.length(),5.0) and is_equal_approx(copied_mesh.global_basis.z.length(),.05), "Runtime applies the same scale range accepted by the document")
	holder.free()
