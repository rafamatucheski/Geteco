extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const FACTORY := preload("res://world/editing/WorldPropFactory.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func find_props(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if node is Node3D and str(node.get_meta("editor_id", "")).begins_with("new/props_test_"): result.append(node)
	for child in node.get_children(): result.append_array(find_props(child))
	return result

func find_id(node: Node, id: String) -> Node3D:
	for prop in find_props(node):
		if prop.get_meta("editor_id") == id: return prop
	return null

func passive(node: Node) -> bool:
	if node.is_processing() or node.is_physics_processing() or node is Light3D: return false
	for child in node.get_children():
		if not passive(child): return false
	return true

func hit_body(point: Vector3, body: Node) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 1
	for hit in root.world_3d.direct_space_state.intersect_point(query):
		if hit.collider == body: return true
	return false

func cell(point: Array) -> Vector2i:
	return Vector2i(floori(float(point[0])/64),floori(float(point[1])/64))

func ensure_props(region: Node, rows: Dictionary) -> void:
	for row in rows.values(): region._ensure_chunk(cell(row.position))

func run() -> void:
	var doc := DATA.empty_document()
	for index in DATA.PROP_TYPES.size():
		var model: String = DATA.PROP_TYPES[index]
		var row := DATA.new_entity("prop",Vector2(2500+index*5,2500))
		row.id = "new/props_test_"+model
		row.model = model
		row.scale = 2.0 if model == "barrier" else 1.5
		row.rotation = 90.0 if model == "barrier" else 37.0
		var size: Vector2 = FACTORY.SIZES[model]
		row.size = [size.x,size.y]
		doc.regions.harbor[row.id] = row
		check(DATA.validate_entity(row).is_empty(), "Compatible prop accepted: "+model)
	var invalid: Dictionary = doc.regions.harbor["new/props_test_pallet"].duplicate(true)
	invalid.model = "unknown_scene"
	check(not DATA.validate_entity(invalid).is_empty(), "Unknown prop model rejected")
	invalid.model = "pallet"
	invalid.scale = 0
	check(not DATA.validate_entity(invalid).is_empty(), "Zero scale rejected")
	invalid.scale = 4
	check(not DATA.validate_entity(invalid).is_empty(), "Scale outside supported range rejected")
	var path := "res://evidence/world-editor-20260925/props_persistence_"+str(OS.get_process_id())+".json"
	check(DATA.save_document(doc,"",path).is_empty(), "All props save to dedicated test document")
	var loaded := DATA.read_document(path)
	check(loaded.error.is_empty() and loaded.document.regions.harbor.size() == 8, "All eight models survive disk reload")
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var region := REGION.build_region("harbor",Vector3(2500,0,2500))
	root.add_child(region)
	region.set_process(false)
	ensure_props(region,loaded.document.regions.harbor)
	check(find_props(region).size() == 8, "Production region instantiates eight saved props exactly once")
	await physics_frame
	await process_frame
	for row in loaded.document.regions.harbor.values():
		var prop := find_id(region,row.id)
		check(prop != null and prop.global_position.is_equal_approx(DATA.xyz(row.position)), "Saved prop exists at authored position: "+row.model)
		if prop == null: continue
		check(prop.find_children("*","MeshInstance3D",true,false).size() > 0, "Prop has real mesh geometry: "+row.model)
		var bodies := prop.find_children("*","StaticBody3D",true,false)
		check(bodies.size() > 0, "Prop has physical solid: "+row.model)
		check(passive(prop), "Prop has no frame processing or lights: "+row.model)
		check(prop.scale.is_equal_approx(Vector3.ONE*float(row.scale)) and is_equal_approx(prop.rotation.y,deg_to_rad(float(row.rotation))), "Saved scale and rotation reach physical root: "+row.model)
		if not bodies.is_empty():
			var collider := bodies[0].get_child(0) as CollisionShape3D
			check(hit_body(collider.global_position,bodies[0]), "Physical query hits prop at transformed solid center: "+row.model)
	var barrier := find_id(region,"new/props_test_barrier")
	var barrier_body := barrier.find_children("*","StaticBody3D",true,false)[0]
	var along_rotated_axis := barrier.global_transform*Vector3(.85,.46,0)
	check(hit_body(along_rotated_axis,barrier_body), "Rotated and doubled barrier collides along its scaled long axis")
	check(not hit_body(barrier.global_position+Vector3(1.7,.92,0),barrier_body), "Barrier collision follows rotation rather than old world axis")
	region.release_chunks()
	await process_frame
	check(find_props(region).is_empty(), "Props leave scene when their chunks unload")
	ensure_props(region,loaded.document.regions.harbor)
	check(find_props(region).size() == 8, "Props reconstruct once each after streaming reload")
	region.free()
	var moved: Dictionary = loaded.document.regions.harbor["new/props_test_barrier"]
	var old_position := DATA.xyz(moved.position)
	moved.position = [old_position.x+160,old_position.z+80]
	loaded.document.regions.harbor["new/props_test_crate"].deleted = true
	check(DATA.save_document(loaded.document,DATA.disk_hash(path),path).is_empty(), "Moved prop and removal save correctly")
	loaded = DATA.read_document(path)
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var reloaded := REGION.build_region("harbor",DATA.xyz(moved.position))
	root.add_child(reloaded)
	reloaded.set_process(false)
	ensure_props(reloaded,loaded.document.regions.harbor)
	check(find_props(reloaded).size() == 7 and find_id(reloaded,"new/props_test_crate") == null, "Saved deletion does not instantiate a hidden stale prop")
	barrier = find_id(reloaded,"new/props_test_barrier")
	check(barrier != null and barrier.global_position.is_equal_approx(DATA.xyz(moved.position)), "Moved prop reloads in destination chunk")
	barrier_body = barrier.find_children("*","StaticBody3D",true,false)[0]
	await physics_frame
	await process_frame
	check(hit_body(barrier.global_transform*Vector3(.85,.46,0),barrier_body), "Reloaded prop collision follows saved position across chunks")
	check(not hit_body(old_position+Vector3(0,.92,0),barrier_body), "No ghost collider at previous chunk position")
	reloaded.free()
	Engine.remove_meta("geteco_world_edit_document")
	print("WORLD_EDITOR_PROPS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
