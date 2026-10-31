extends SceneTree
## Checagens de mobília física e orçamento na sala nativa real do Digo.
## Oclusão renderizada, materiais e cronometragem são conferidos à parte no Main.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("DIGO_PROPS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var room := PLACES.create_place("desert_digo")
	stage.add_child(room)
	for frame in 3: await physics_frame
	var details := room.model.get_node_or_null("DigoFurnitureDetails") as MeshInstance3D
	if not _require(is_instance_valid(details),"real Digo room uses refined static furniture"):
		stage.free(); return
	_check(details.mesh.get_surface_count() <= 8,"all refined furniture uses at most eight material surfaces")
	var triangles := 0
	for surface in details.mesh.get_surface_count():
		var arrays: Array = details.mesh.surface_get_arrays(surface)
		var count: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		triangles += count/3
	_check(triangles <= 12000,"refined furniture stays within twelve thousand triangles: "+str(triangles))
	var proxies := {"Workbench":Vector3(4.1,1.3,1.2),"ToolChest":Vector3(1.8,1.2,1),"TuningDesk":Vector3(3.2,1.3,1.5),"Computer":Vector3(.75,.64,.25),"DeskChair":Vector3(.75,.9,.75)}
	for side in [-1.0,1.0]:
		proxies["LiftPost%s"%side] = Vector3(.48,3.6,.65)
		proxies["LiftFoot%s"%side] = Vector3(.9,.16,1.1)
	for shelf in 3: proxies["PartsShelf%d"%shelf] = Vector3(1.8,2.2,.9)
	for id in proxies:
		var proxy: MeshInstance3D
		for child in room.model.get_children():
			if child is MeshInstance3D and str(child.get_meta("interior_solid_id","")) == str(id): proxy = child; break
		_check(is_instance_valid(proxy) and proxy.mesh is BoxMesh and proxy.mesh.size.is_equal_approx(proxies[id]) and proxy.get_meta("interior_solid_id","") == id and not proxy.visible,"original reserved solid envelope survives refinement: "+str(id))
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		for frame in 3: await physics_frame
		var who := "player" if player else "npc"
		for probe in [
			{"id":"workbench","at":Vector3(-9.7,.04,-3.5),"motion":Vector3(0,0,-3)},
			{"id":"tool chest","at":Vector3(-10.4,.04,0),"motion":Vector3(0,0,-3)},
			{"id":"tuning desk","at":Vector3(8.4,.04,2.1),"motion":Vector3(0,0,-3)},
			{"id":"chair","at":Vector3(8.4,.04,-3.5),"motion":Vector3(0,0,2)},
			{"id":"parts shelf","at":Vector3(5,.04,-6),"motion":Vector3(0,0,-3)},
			{"id":"lift post","at":Vector3(3.5,.04,-3.5),"motion":Vector3(-2,0,0)}]:
			actor.position = probe.at
			_check(actor.test_move(actor.global_transform,probe.motion),who+" swept body is blocked by "+str(probe.id))
			_check(actor.test_move(actor.global_transform,probe.motion*5.0),who+" long swept body cannot tunnel through "+str(probe.id))
		actor.position = Vector3(0,.04,6.7)
		_check(not actor.test_move(actor.global_transform,Vector3(0,0,-8)),who+" central vehicle bay and pedestrian aisle remain clear")
		actor.free()
	var car := VEHICLE.new()
	car.archetype = "desert_coyote"
	stage.add_child(car)
	car.set_process(false)
	car.set_physics_process(false)
	car.place(Vector3(0,.12,0),PI)
	for frame in 2: await physics_frame
	_check(car.move_and_collide(Vector3(0,0,6),true) == null,"real Coyote hull clears central bay and garage approach")
	var exit_gate: Node3D = room.model.get_node("InteriorVehicleGate")
	_check(not exit_gate.is_open() and not exit_gate.set_vehicle_access(true),"interior shutter stays physically closed without an owned admission")
	_check(car.move_and_collide(Vector3(0,0,25),true) != null,"closed interior shutter blocks full hull at high-speed sweep before room void")
	_check(exit_gate.set_vehicle_access(true,func() -> bool: return true),"authorized interior admission raises actual visible shutter")
	for frame in 2: await physics_frame
	_check(car.move_and_collide(Vector3(0,0,10),true) == null,"raised interior shutter clears authorized exit hull")
	exit_gate.set_vehicle_access(false)
	_check(exit_gate._barrier.collision_layer == 1 and not exit_gate.is_open(),"interior gate cleanup restores physical barrier")
	stage.free()
	print("DIGO_PROPS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _require(ok: bool, label: String) -> bool:
	_check(ok,label)
	if not ok: quit(1)
	return ok
