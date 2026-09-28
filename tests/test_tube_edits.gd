extends SceneTree
const TRANSIT := preload("res://runtime/UrbanTransitPresentation.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var original_hash := DATA.disk_hash()
	var source := TRANSIT.new()
	source.configure(null,false)
	root.add_child(source)
	var definition: Dictionary = source.definitions[2].duplicate(true)
	var original := source.build_geometry(source,definition)
	var station = original.get_child(0)
	var approach: Vector3 = station.get_boarding_approach()
	var shape: CollisionShape3D = original.find_children("*","CollisionShape3D",true,false)[0]
	var faces: PackedVector3Array = shape.shape.get_faces()
	var a := shape.global_transform*faces[0]
	var b := shape.global_transform*faces[1]
	var c := shape.global_transform*faces[2]
	original.free()
	var doc := DATA.empty_document()
	var id := "piece/transit/urban_station_2"
	var target: Vector3 = definition.position+Vector3(-2,0,20)
	var row := {"id":id,"type":"piece","position":[target.x,target.z],"rotation":15.0,"stretch":[1.2,1.1],"source_record":"transit/urban_station_2"}
	doc.regions.harbor[id] = row
	var deleted := "piece/transit/urban_station_3"
	doc.regions.harbor[deleted] = {"id":deleted,"type":"piece","deleted":true,"source_record":"transit/urban_station_3"}
	check(DATA.validate_document(doc).is_empty(),"Tube edits and deletion validate")
	Engine.set_meta("geteco_world_edit_document",doc)
	var edited := TRANSIT.new()
	edited.configure(null)
	root.add_child(edited)
	var changed: Dictionary = edited.definitions[2]
	var art := edited.build_geometry(edited,changed)
	check(art.get_meta("editor_id")==id,"Tube has selectable editor identity")
	check(art.global_position.is_equal_approx(target),"Runtime uses edited origin")
	var basis := Basis(Vector3.UP,deg_to_rad(15.0))*Basis.from_scale(Vector3(1.2,1,1.1))
	var warp := Transform3D(basis,target-basis*definition.position)
	check(changed.stop_point.is_equal_approx(warp*definition.stop_point),"Bus route target follows tube transform")
	check(art.get_child(0).get_boarding_approach().is_equal_approx(warp*approach),"Physical passenger approach follows tube transform")
	check(edited.definitions.size()==7 and edited.definitions[3].deleted,"Deletion preserves stable route indices")
	check(edited.definitions[6].position==source.definitions[6].position,"Coach terminal operation remains in place")
	await physics_frame
	await physics_frame
	var body = art.find_children("*","StaticBody3D",true,false)[0]
	var center := (a+b+c)/3
	# Godot front faces use clockwise winding; probe from the solid's exterior.
	var normal := (c-a).cross(b-a).normalized()
	var hit := art.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(warp*(center+normal*.2),warp*(center-normal*.2),1))
	check(not hit.is_empty() and hit.collider==body,"Edited structural collision is physically hittable")
	var old_hit := art.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center+normal*.2,center-normal*.2,1))
	check(old_hit.is_empty(),"Old location has no phantom collision")
	var player := Node3D.new()
	root.add_child(player)
	var transport := preload("res://runtime/PassengerTransport.gd").new()
	transport.configure({"controller":{"urban_transit":edited},"world":{"player":player}})
	player.position = target
	check(transport._station()==2,"Transport interaction follows moved tube")
	player.position = definition.position
	check(transport._station()!=2,"Old tube location no longer offers its service")
	check(transport._stop_point(2).is_equal_approx(changed.stop_point),"Line 510 reads edited destination")
	check(transport._next_stop(2)==4,"Line 510 skips deleted stop")
	for i in 6: edited.definitions[i].deleted = true
	check(transport._next_stop(2)==-1,"No active stops is handled without an invalid loop")
	transport.free()
	player.free()
	edited.free()
	source.free()
	Engine.remove_meta("geteco_world_edit_document")
	check(DATA.disk_hash()==original_hash,"Official world unchanged")
	print("TUBE_EDITS ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
