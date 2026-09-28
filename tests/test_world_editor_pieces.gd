extends SceneTree
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const YARD := preload("res://world/places/SalvageYardNative.gd")
var failures: Array[String] = []
var checks := 0
class Records:
	extends Node3D
	var records := {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func find_piece(node: Node,key: String) -> Node3D:
	for piece in PIECES.collect(node):
		if piece.get_meta("world_edit_piece_id") == key: return piece
	return null
func spawn_yard() -> Node3D:
	var yard := YARD.new()
	yard.position = Vector3(20,0,20)
	root.add_child(yard)
	return yard
func run() -> void:
	var yard := spawn_yard()
	var office := find_piece(yard,"neco/Office")
	check(office != null,"Office is an independent piece")
	check(find_piece(yard,"neco/Barrel0") != find_piece(yard,"neco/Barrel1"),"Barrels are separate pieces")
	check(find_piece(yard,"neco/Tire0") != null and find_piece(yard,"neco/Engine0") != null,"Tires and engines are independent")
	check(find_piece(yard,"neco/fence_north") != null and find_piece(yard,"neco/fence_west") != null,"Fence spans are separate")
	check(office.find_children("*","StaticBody3D",true,false).size() == 1,"Office carries its real collider")
	var origin := office.global_transform
	var mesh: MeshInstance3D = office.find_children("*","MeshInstance3D",true,false)[0]
	var body: StaticBody3D = office.find_children("*","StaticBody3D",true,false)[0]
	var mesh_relative := office.global_transform.affine_inverse()*mesh.global_transform
	var body_relative := office.global_transform.affine_inverse()*body.global_transform
	var press_point: Vector3 = yard.press.global_position
	var button_point: Vector3 = yard.button_point()
	var target := origin.origin+Vector3(90,0,4)
	var row := {"id":"piece/neco/Office","type":"piece","position":[target.x,target.z],"rotation":90.0}
	var changes := {row.id:row,"piece/neco/press":{"id":"piece/neco/press","type":"piece","position":[999,999],"rotation":45}}
	PIECES.apply(yard,changes)
	check(office.global_position.is_equal_approx(target),"Office moves to saved world position")
	check((office.global_transform.affine_inverse()*mesh.global_transform).is_equal_approx(mesh_relative),"Mesh follows edited pivot")
	check((office.global_transform.affine_inverse()*body.global_transform).is_equal_approx(body_relative),"Collider follows edited pivot")
	check(yard.press.global_position.is_equal_approx(press_point) and yard.button_point().is_equal_approx(button_point),"Operational press/button ignore unsupported edits")
	var after := office.global_transform
	PIECES.apply(yard,changes)
	check(office.global_transform.is_equal_approx(after),"Applying saved rotation twice does not accumulate rotation")
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(target.x,10,target.z),Vector3(target.x,-1,target.z),1)
	var hit := yard.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider == body,"Physical ray finds moved office collider")
	var base := spawn_yard()
	check(find_piece(base,"neco/Office").global_transform.is_equal_approx(origin),"New construction retains stable source pivot")
	base.free()
	yard.free()
	var record := {"kind":"salvage","position":Vector3(20,0,20)}
	row.source_record = PIECES.record_key(record)
	var fake := Records.new()
	fake.records[Vector2i.ZERO] = [record]
	root.add_child(fake)
	PIECES.prepare(fake,{row.id:row})
	var target_cell := Vector2i(floori(target.x/64),floori(target.z/64))
	check(fake.records.has(target_cell),"Moved piece receives destination streaming record")
	var original := spawn_yard()
	PIECES.apply(original,{row.id:row})
	PIECES.filter_record(original,fake.records[Vector2i.ZERO][0])
	check(find_piece(original,"neco/Office") == null,"Original chunk removes relocated office")
	check(find_piece(original,"neco/Barrel0") != null,"Original chunk keeps other pieces")
	var destination := spawn_yard()
	PIECES.apply(destination,{row.id:row})
	PIECES.filter_record(destination,fake.records[target_cell][0])
	check(PIECES.collect(destination).size() == 1,"Destination clones only the relocated piece")
	check(destination.find_children("*","StaticBody3D",true,false).size() == 1,"Destination keeps only relocated piece collision")
	check(find_piece(destination,"neco/Office").global_position.is_equal_approx(target),"Destination reconstruction restores saved location")
	original.free()
	destination.free()
	var guarded := spawn_yard()
	PIECES.filter_record(guarded,{"editor_piece_exclude":["piece/neco/press"]})
	check(find_piece(guarded,"neco/press") != null,"Hand-edited document cannot remove operational machinery at source")
	guarded.free()
	guarded = spawn_yard()
	PIECES.filter_record(guarded,{"editor_piece_only":["piece/neco/press"]})
	check(find_piece(guarded,"neco/press") == null,"Hand-edited document cannot clone operational machinery")
	guarded.free()
	fake.free()
	check_multiple_destinations()
	check_runtime_adapter()
	print("WORLD_EDITOR_PIECES checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func check_runtime_adapter() -> void:
	var base := REGION.build_region("harbor")
	base.prepare_data()
	var source := {}
	var source_cell := Vector2i.ZERO
	for cell in base.records:
		for record in base.records[cell]:
			if record.kind == "salvage":
				source = record
				source_cell = cell
	var row := {"id":"piece/neco/Office","type":"piece","position":[145.0,45.0],"rotation":25.0,"source_record":PIECES.record_key(source)}
	var doc := DATA.empty_document()
	doc.regions.harbor[row.id] = row
	Engine.set_meta("geteco_world_edit_document",doc)
	var region := REGION.build_region("harbor")
	region.prepare_data()
	Engine.remove_meta("geteco_world_edit_document")
	var target_cell := Vector2i(2,0)
	var target_record := {}
	for record in region.records.get(target_cell,[]):
		if record.get("kind","") == "salvage": target_record = record
	check(not target_record.is_empty(),"Runtime adapter registers relocated piece in destination chunk")
	var holder := Node3D.new()
	root.add_child(holder)
	if not target_record.is_empty(): region._build_record(holder,target_record)
	var office := find_piece(holder,"neco/Office")
	check(office != null and office.global_position.is_equal_approx(Vector3(145,0,45)),"Real record builder reconstructs saved office in destination")
	check(PIECES.collect(holder).size() == 1,"Runtime destination contains only moved piece")
	holder.free()
	var original := Node3D.new()
	root.add_child(original)
	for record in region.records[source_cell]:
		if record.kind == "salvage": region._build_record(original,record)
	check(find_piece(original,"neco/Office") == null and find_piece(original,"neco/Barrel0") != null,"Runtime source retains yard without duplicate office")
	original.free()
	region.free()
	base.free()

func check_multiple_destinations() -> void:
	var source := {"kind":"salvage","position":Vector3(20,0,20)}
	var key := PIECES.record_key(source)
	var changes := {}
	for spec in [["Office",100.0],["Barrel0",110.0],["Barrel1",170.0]]:
		var id: String = "piece/neco/"+str(spec[0])
		changes[id] = {"id":id,"type":"piece","position":[spec[1],20.0],"rotation":0.0,"source_record":key}
	var fake := Records.new()
	fake.records[Vector2i.ZERO] = [source]
	PIECES.prepare(fake,changes)
	check(fake.records.size() == 3,"One source supports pieces relocated into multiple chunks")
	for spec in [[Vector2i(1,0),2],[Vector2i(2,0),1]]:
		var destination := spawn_yard()
		var record: Dictionary = fake.records[spec[0]][0]
		PIECES.apply(destination,changes)
		PIECES.filter_record(destination,record)
		check(PIECES.collect(destination).size() == spec[1],"Destination receives exactly its requested subset of pieces")
		destination.free()
	fake.free()
