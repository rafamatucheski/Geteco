extends SceneTree
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const SESSION := preload("res://world/editing/WorldSessionEdits.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func group_for(course: Node, id: String) -> Node3D:
	for group in PIECES.collect(course):
		if "piece/"+str(group.get_meta("world_edit_piece_id","")) == id: return group
	return null

func hit(at: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*20,at-Vector3.UP*20,1))

func inside(node: Node, ancestor: Node) -> bool:
	return node != null and is_instance_valid(ancestor) and (node == ancestor or ancestor.is_ancestor_of(node))

func run() -> void:
	var official := DATA.disk_hash()
	var old_preview: Variant = Engine.get_meta("geteco_live_preview_build") if Engine.has_meta("geteco_live_preview_build") else null
	var old_document: Variant = Engine.get_meta("geteco_world_edit_document") if Engine.has_meta("geteco_world_edit_document") else null
	Engine.set_meta("geteco_live_preview_build",true)
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var holder := Node3D.new()
	root.add_child(holder)
	var course := COURSE.new()
	holder.add_child(course)
	course.finish_build()
	SESSION.finalize_places(holder,"harbor",{})
	var rows := UNITS.manifest(course)
	check(rows.size()>50,"Staged motocross exposes individual static objects after construction")
	var rocks: Array = []
	var stakes := 0
	var ids := {}
	for row in rows:
		ids[row.id] = true
		if str(row.label)=="Quarry Rocks": rocks.append(row)
		if str(row.label)=="Course Stake": stakes += 1
		check(str(row.source_record)=="unit/harbor/s_motocross","Session unit has persistent source identity")
	check(rocks.size()>1 and stakes>5,"Rocks and course stakes are individually selectable")
	check(ids.size()==rows.size(),"Every individual object has a distinct stable identity")
	SESSION.finalize_places(holder,"harbor",{})
	check(UNITS.manifest(course).size()==rows.size(),"Repeated finalization does not duplicate units")
	var actors := course.find_children("Digo","",true,false)
	check(not actors.is_empty(),"Production instructor exists")
	if not actors.is_empty():
		var cursor: Node = actors[0]
		var claimed := false
		while cursor != course:
			claimed = claimed or cursor.has_meta("world_edit_piece_id")
			cursor = cursor.get_parent()
		check(not claimed,"Instructor and gameplay identity are excluded from static editing")
	if rocks.size()<2:
		holder.free(); quit(1); return
	var moved: Dictionary = rocks[0]
	var removed: Dictionary = rocks[1]
	var moved_group := group_for(course,moved.id)
	var removed_group := group_for(course,removed.id)
	await physics_frame
	await physics_frame
	var before := hit(moved_group.global_position+Vector3.UP*float(moved.selection_height))
	check(not before.is_empty() and inside(before.get("collider"),moved_group),"Individual rock owns its original physical shape")
	var removed_before := hit(removed_group.global_position+Vector3.UP*float(removed.selection_height))
	check(not removed_before.is_empty() and inside(removed_before.get("collider"),removed_group),"Rock selected for deletion owns its original solid")
	var document := DATA.empty_document()
	var target := Vector2(float(moved.position[0])+400,float(moved.position[1])+300)
	document.regions.harbor[moved.id] = {"id":moved.id,"type":"piece","position":[target.x,target.y],"rotation":0.0,"source_record":moved.source_record}
	document.regions.harbor[removed.id] = {"id":removed.id,"type":"piece","deleted":true,"source_record":removed.source_record}
	check(DATA.validate_document(document).is_empty(),"Individual motocross edits fit the persistent document contract")
	var gate: Node3D = course.start_gate
	check(is_instance_valid(gate) and gate.is_inside_tree(),"Finalization preserves the live start gate reference")
	holder.free()
	Engine.set_meta("geteco_live_preview_build",false)
	Engine.set_meta("geteco_world_edit_document",document)
	var runtime_holder := Node3D.new()
	root.add_child(runtime_holder)
	var watcher: Variant = SESSION.install(self,runtime_holder,document)
	check(watcher!=null,"Runtime installs a watcher for motocross session edits")
	var runtime_course := COURSE.new()
	runtime_holder.add_child(runtime_course)
	runtime_course.finish_build()
	for entry in watcher.watched: entry.frame = int(entry.frame)-10
	watcher._process(0)
	var actual := group_for(runtime_course,moved.id)
	check(actual!=null,"Runtime and preview generate the same individual identity")
	check(group_for(runtime_course,removed.id)==null,"Deleted rock stays absent when the course is rebuilt")
	if actual!=null:
		check(Vector2(actual.global_position.x,actual.global_position.z).is_equal_approx(target),"Saved rock movement applies in normal runtime")
		await physics_frame
		await physics_frame
		var after := hit(actual.global_position+Vector3.UP*float(moved.selection_height))
		check(not after.is_empty() and inside(after.get("collider"),actual),"Moved rock carries its physical shape to the destination")
		var old_hit := hit(Vector3(float(removed.position[0]),float(removed.selection_height),float(removed.position[1])))
		check(old_hit.is_empty() or (not removed_before.is_empty() and float(old_hit.position.y)<float(removed_before.position.y)-.05),"Deleted rock leaves no detached collider")
	runtime_holder.free()
	if old_preview==null: Engine.remove_meta("geteco_live_preview_build")
	else: Engine.set_meta("geteco_live_preview_build",old_preview)
	if old_document==null: Engine.remove_meta("geteco_world_edit_document")
	else: Engine.set_meta("geteco_world_edit_document",old_document)
	check(DATA.disk_hash()==official,"Individualization tests never save the official world")
	print("WORLD_EDITOR_MOTOCROSS_UNITS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
