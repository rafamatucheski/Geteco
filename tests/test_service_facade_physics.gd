extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const SERVICES := preload("res://world/editing/WorldServiceBuildings.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var failed := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failed += 1; push_error(label)
func run() -> void:
	var original := preload("res://world/regions/NativeRegion.gd").build_region("harbor")
	original.prepare_data()
	var rows := DATA.catalog(original)
	original.free()
	var document := DATA.empty_document()
	for id in SERVICES.PLACES:
		var row: Dictionary = rows["building/"+str(id)].duplicate(true)
		row.position[0] += 3
		row.size = [row.size[0]*1.1,row.size[1]*1.15]
		row.height *= 1.1
		row.rotation = 25
		row.color = "728496"
		document.regions.harbor[row.id] = row
	Engine.set_meta("geteco_world_edit_document",document)
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var chunk := Node3D.new()
	root.add_child(chunk)
	var entrance := preload("res://runtime/WeaponShopEntrance.gd").new()
	root.add_child(entrance)
	for building in region.buildings:
		if not SERVICES.PLACES.has(building.id): continue
		var count := chunk.get_child_count()
		region._building(chunk,building)
		check(chunk.get_child_count() == count+1,"Authored facade survives: "+str(building.id))
		if chunk.get_child_count() == count: continue
		var art: Node3D = chunk.get_child(count)
		var tinted := false
		for mesh in art.find_children("*","MeshInstance3D",true,false):
			if mesh.material_override is StandardMaterial3D and mesh.material_override.albedo_color.is_equal_approx(Color("728496")): tinted = true
		check(tinted,"Facade color reaches actual model: "+str(building.id))
		var door_art: Node3D = art.get_node("WalkupDoor") if art.has_node("WalkupDoor") else art
		if door_art.has_method("set_open_amount"): door_art.set_open_amount(1.0)
		for tick in 3: await physics_frame
		var place_id: String = SERVICES.PLACES[building.id]
		var definition := PLACES.get_definition(place_id)
		var door := entrance._door_position(place_id,definition)
		var inward := entrance._inward(place_id)
		var capsule := CapsuleShape3D.new()
		capsule.radius = .30
		capsule.height = 1.7
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1
		query.transform.origin = door+inward*.12+Vector3.UP*1.0
		var hits := chunk.get_world_3d().direct_space_state.intersect_shape(query,8)
		check(hits.is_empty(),"Full actor fits rotated enlarged entrance: "+str(building.id))
		if not hits.is_empty():
			for hit in hits: print("DOOR_COLLISION ",building.id," ",hit.collider.get_path())
		var rigid := true
		for body in art.find_children("*","CollisionObject3D",true,false):
			rigid = rigid and body.global_basis.get_scale().is_equal_approx(Vector3.ONE)
		check(rigid,"Collision bodies remain rigid: "+str(building.id))
	region.free()
	chunk.free()
	entrance.free()
	Engine.remove_meta("geteco_world_edit_document")
	print("SERVICE_PHYSICS ",checks," checks ",failed," failures")
	quit(1 if failed else 0)
