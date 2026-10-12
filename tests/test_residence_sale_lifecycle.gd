extends SceneTree
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("SALE_LIFECYCLE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	# Prewarming frees facades in the same frame; queued work must be cancelled.
	var temporary: Node3D = FACTORY.build_building({"id":"CanalHomesWest","position":Vector3.ZERO})
	root.add_child(temporary)
	temporary.free()
	await process_frame
	await process_frame
	check(get_nodes_in_group("residence_sale_marker").is_empty(),"prewarming leaves no marker")
	for id in ["westgate_garden","quayside_house","CanalHomesWest"]:
		var facade: Node3D = FACTORY.build_building({"id":id,"position":Vector3.ZERO})
		root.add_child(facade)
		await process_frame
		await process_frame
		var markers := get_nodes_in_group("residence_sale_marker")
		check(markers.size()==1,id+" mounts exactly one marker")
		if markers.size()==1:
			check(markers[0].property_id==("canal_north" if id=="CanalHomesWest" else id),id+" maps property identity")
			check(markers[0].find_children("*","CollisionObject3D",true,false).is_empty(),id+" cue never blocks movement")
		facade.free()
		await process_frame
		check(get_nodes_in_group("residence_sale_marker").is_empty(),id+" unloading releases marker")
	print("SALE_LIFECYCLE_RESULT failures=",failures)
	quit(0 if failures==0 else 1)
