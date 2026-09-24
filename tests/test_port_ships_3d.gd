extends SceneTree
## Native harbor ship art must stream with the berths and leave access physical.
const REGION := preload("res://world/regions/NativeRegion.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func run() -> void:
	var region := REGION.build_region("harbor",Vector3(223,0,90))
	root.add_child(region)
	for i in 16: await process_frame
	var northstar := region.find_child("NorthstarShipDetail3D",true,false)
	check(northstar != null,"Northstar has native 3D ship finish")
	var northstar_rigs := region.find_children("NorthstarCraneRigging3D*","Node3D",true,false)
	check(northstar_rigs.size() == 3,"Northstar keeps three detailed cranes, found %d" % northstar_rigs.size())
	var northstar_hoists := region.find_children("NorthstarCargoHoist3D*","Node3D",true,false)
	check(northstar_hoists.size() == 3,"Northstar cranes have three moving hoists")
	if not northstar_hoists.is_empty():
		var hoist = northstar_hoists[0]
		hoist.clock = 0.0
		hoist._update_pose()
		var first_x: float = hoist.trolley.position.x
		hoist.clock = 15.0
		hoist._update_pose()
		check(absf(hoist.trolley.position.x-first_x) > 1.0,"Northstar hoist travels between cargo and quay")
	var northstar_booms := region.find_children("NorthstarCraneBoom*","MeshInstance3D",true,false)
	check(northstar_booms.size() == 3,"Northstar keeps three physical jibs")
	for boom in northstar_booms:
		var tip_x: float = boom.position.x+(boom.mesh as BoxMesh).size.z*.5
		check(tip_x >= 3460.0/16.0,"Northstar jib reaches the first cargo row")
		var aligned := false
		for row_z in [1052.0,1164.0,1276.0,1388.0,1500.0,1612.0]:
			if is_equal_approx(boom.position.z,row_z/16.0): aligned = true
		check(aligned,"Northstar jib is centered on a cargo row")
	var northstar_deck := region.find_child("NorthstarDeck",true,false) as MeshInstance3D
	check(northstar_deck != null and (northstar_deck.material_override as StandardMaterial3D).albedo_texture != null,"Northstar deck uses a real texture")
	if northstar != null:
		check(not northstar.find_children("*","MeshInstance3D",true,false).is_empty(),"Northstar finish contains meshes")
		check(northstar.find_children("*","StaticBody3D",true,false).is_empty(),"Northstar exterior scaffold does not add boarding collisions")
	region.set_focus(Vector3(299,0,183))
	for i in 16: await process_frame
	var santa := region.find_child("SantaMareShipDetail3D",true,false)
	check(santa != null,"Santa Mare has native 3D hull and scaffold")
	check(region.find_children("QuaysideCraneRigging3D","Node3D",true,false).size() == 3,"Santa Mare keeps three detailed quay cranes")
	var quayside_cranes := region.find_children("QuaysideCrane3D*","Node3D",true,false)
	check(quayside_cranes.size() == 3,"Santa Mare keeps three physical quayside cranes")
	for crane in quayside_cranes:
		var tip: Vector3 = crane.to_global(crane.hoist_end)
		check(Geometry2D.is_point_in_polygon(Vector2(tip.x,tip.z)*16.0,preload("res://world/regions/OriginalSouthPortLayout.gd").ship_hull()),"Quayside jib reaches the Santa Mare deck")
	if santa != null:
		check(santa.find_child("SantaMarePaintedDeck",true,false) != null,"Santa Mare has a painted 3D deck")
		var painted_deck := santa.find_child("SantaMarePaintedDeck",true,false) as MeshInstance3D
		check((painted_deck.material_override as StandardMaterial3D).albedo_texture != null,"Santa Mare deck uses a real texture")
		check(santa.find_children("*","StaticBody3D",true,false).is_empty(),"Santa Mare exterior scaffold does not add boarding collisions")
	check(region.find_children("*","SubViewport",true,false).is_empty(),"Harbor ships render as native 3D")
	var operations := preload("res://gameplay/urban_v1/PortCargoOperations.gd").new()
	root.add_child(operations)
	operations.set_process(false)
	var transfer: Dictionary = operations.cranes[0]
	transfer.clock = 12.0
	operations.active = true
	operations._sync_crane(0)
	var load_position: Vector3 = (transfer.visual as Node3D).global_position
	var cable_position: Vector3 = (transfer.cable as MeshInstance3D).global_position
	check(is_equal_approx(load_position.x,cable_position.x) and is_equal_approx(load_position.z,cable_position.z),"Moving quay crane cable stays over cargo")
	check((transfer.cable as MeshInstance3D).scale.y > .15,"Moving quay crane cable has visible length")
	print("PORT_SHIPS_3D failures=",failures)
	operations.free()
	region.free()
	await process_frame
	quit(1 if failures else 0)
