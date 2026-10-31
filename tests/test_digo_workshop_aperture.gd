extends SceneTree
## Geometria externa real e cascos reais de Vehicle. As checagens físicas da abertura
## complementam a fixture de entrar dirigindo no Main; não certificam a oclusão renderizada.
const ARCH := preload("res://world/desert/DesertArchitecture.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("DIGO_APERTURE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var definition: Dictionary
	for building in LAYOUT.buildings():
		if building.id == "desert_digo": definition = building; break
	if definition.is_empty(): push_error("Digo building missing"); quit(1); return
	world.add_child(ARCH.building(definition))
	G.box(world,"FixtureGround",definition.position-Vector3(0,.1,0),Vector3(50,.2,50),Color.GRAY,true)
	for frame in 3: await physics_frame
	var gates: Array[Node] = get_nodes_in_group("digo_vehicle_gate")
	if gates.size() != 1: _check(false,"one real Digo gate exists"); world.free(); quit(1); return
	var gate: Node3D = gates[0]
	_check(not gate.is_open() and not gate.set_vehicle_access(true),"default gate stays closed without an admission capability")
	_check(not gate.set_vehicle_access(true,func() -> bool: return false),"rejected admission capability cannot open physical shutter")
	for archetype in ["sport_coupe","monaliza","desert_faisca","supra_a80"]:
		var car := VEHICLE.new()
		car.archetype = archetype
		world.add_child(car)
		car.set_physics_process(false)
		car.set_process(false)
		var front: float = definition.position.z+definition.size.z*.5
		var start := Vector3(definition.position.x,.12,front+car.half_length+1.0)
		var motion := Vector3(0,0,-(car.half_length*2.0+2.0))
		car.global_position = start
		for frame in 2: await physics_frame
		_check(car.move_and_collide(motion,true) != null,archetype+" closed gate blocks complete vehicle hull")
		_check(car.move_and_collide(motion*8.0,true) != null,archetype+" closed gate blocks long high-speed sweep")
		_check(gate.set_vehicle_access(true,func() -> bool: return true),archetype+" authorized admission raises real shutter")
		_check(gate._panel.get_parent() == gate and gate._panel.scale.y < .1,archetype+" dynamic raised mesh remains outside static batching")
		for frame in 2: await physics_frame
		_check(car.move_and_collide(motion,true) == null,archetype+" full body sweeps through open garage, no recess/plinth barrier")
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = car.shape.shape
		query.transform = Transform3D(Basis.IDENTITY,start+car.shape.position)
		query.motion = motion
		query.collision_mask = 1
		query.exclude = [car.get_rid()]
		var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
		_check(sweep.size() == 2 and is_equal_approx(sweep[0],1.0),archetype+" independent swept hull clears portal")
		for side in [-1.0,1.0]:
			car.global_position = start+Vector3(side*2.75,0,0)
			_check(car.move_and_collide(motion,true) != null,archetype+" garage column blocks offset "+str(side))
		car.free()
		gate.set_vehicle_access(false)
		_check(not gate.is_open() and gate._barrier.collision_layer == 1,"admission cleanup closes real gate again")
		await physics_frame
	world.free()
	print("DIGO_APERTURE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
