extends SceneTree
## Real vehicle input, ground/obstacle collision, rider grips and recovery.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DIRT_BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const DRIVING := preload("res://scripts/Driving.gd")
class Fixture extends Node3D:
	var player
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("MOTORCYCLE_WHEELIE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	shape.shape = geometry
	body.position = at
	body.add_child(shape)
	parent.add_child(body)

func run() -> void:
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_STICK
	check(InputMap.event_is_action(key,"motorcycle_wheelie") and InputMap.event_is_action(pad,"motorcycle_wheelie"),"Shift and L3 lift, independent from accelerator and brake")
	check(controls.rebind("motorcycle_wheelie",key).is_empty() and controls.rebind_gamepad("motorcycle_wheelie",pad).ok,"wheelie and on-foot sprint can share configurable bindings")
	controls.import_bindings({"move_up":[{"key":KEY_UP}]})
	controls.import_gamepad_bindings({"accelerate":[{"axis":JOY_AXIS_TRIGGER_RIGHT,"direction":1}]},2)
	check(InputMap.event_is_action(key,"motorcycle_wheelie") and InputMap.event_is_action(pad,"motorcycle_wheelie"),"old settings retain new default")
	controls.reset_bindings()
	var world := Fixture.new()
	root.add_child(world)
	box(world,Vector3(0,-.5,0),Vector3(300,1,300))
	world.player = ACTOR.new()
	world.player.is_player = true
	world.add_child(world.player)
	world.player.set_physics_process(false)
	var driving := DRIVING.new()
	driving.world = world
	for id in ["bike_urban","bike_sport","bike_cruiser"]:
		var bike = VEHICLE.new()
		bike.archetype = id
		bike.controlled = true
		world.add_child(bike)
		await frames(5)
		Input.action_press("motorcycle_wheelie")
		await frames(15)
		check(bike.visual.rotation.x == 0,"%s cannot lift at rest"%id)
		Input.action_press("move_up")
		await frames(180)
		check(bike.visual.rotation.x > .3 and bike.visual.rotation.x < .7,"%s accelerates into a bounded sustained wheelie"%id)
		check(bike.is_on_floor() and absf(bike.position.y) < .05,"%s keeps ground support"%id)
		check(bike.manual_wheelie.steering_scale() < .8,"%s has reduced steering response while lifted"%id)
		for wheel in bike.wheels:
			if not wheel.get_meta("front"):
				check(wheel.global_position.y >= .2,"%s rear wheel stays above ground"%id)
			else: check(wheel.global_position.y > .7,"%s front wheel visibly rises"%id)
		driving.car = bike
		driving._update_mounted_player()
		check(world.player.visual.global_basis.orthonormalized().is_equal_approx(bike.visual.global_basis.orthonormalized()),"%s rider follows pitched motorcycle"%id)
		var holds: Dictionary = bike.motorcycle_handholds()
		for side in ["Left","Right"]:
			check(world.player.combat_palm_position(side).distance_to(holds[side].origin) < .035,"%s %s hand remains on raised handlebar"%[id,side])
		var raised: float = bike.visual.rotation.x
		Input.action_release("motorcycle_wheelie")
		await frames(2)
		check(bike.visual.rotation.x > 0 and bike.visual.rotation.x < raised,"%s release begins smooth descent"%id)
		await frames(35)
		check(absf(bike.visual.rotation.x) < .001 and bike.visual.position.is_zero_approx(),"%s release restores riding pose"%id)
		Input.action_press("motorcycle_wheelie")
		await frames(45)
		Input.action_press("handbrake")
		await frames(15)
		check(bike.visual.rotation.x < .001,"%s brake promptly lowers front"%id)
		Input.action_release("handbrake")
		await frames(80)
		bike.input_locked = true
		await frames(2)
		check(bike.visual.rotation.x == 0,"%s modal/input lock cancels wheelie"%id)
		bike.input_locked = false
		await frames(40)
		bike.place(Vector3(0,0,0),0)
		check(bike.visual.rotation.x == 0 and bike.visual.position.is_zero_approx(),"%s teleport clears wheelie immediately"%id)
		bike.controlled = false
		await frames(2)
		check(bike.visual.rotation.x == 0,"%s dismount clears wheelie"%id)
		Input.action_release("move_up")
		bike.controlled = true
		bike.place(Vector3(0,0,0),0)
		Input.action_press("move_down")
		await frames(30)
		check(bike.speed < 0 and bike.visual.rotation.x == 0,"%s cannot wheelie in reverse"%id)
		Input.action_release("move_down")
		Input.action_release("motorcycle_wheelie")
		bike.free()
	var bike = VEHICLE.new()
	bike.archetype = "bike_urban"
	bike.controlled = true
	world.add_child(bike)
	box(world,Vector3(0,1,-12),Vector3(20,2,.5))
	Input.action_press("move_up")
	Input.action_press("motorcycle_wheelie")
	await frames(250)
	check(bike.position.z > -12,"wheelie cannot pass through solid wall")
	bike.free()
	var car = VEHICLE.new()
	world.add_child(car)
	car.controlled = true
	await frames(100)
	check(car.visual.rotation.x == 0,"cars ignore wheelie input")
	car.free()
	Input.action_release("move_up")
	Input.action_release("motorcycle_wheelie")
	var dirt = DIRT_BIKE.new()
	dirt.is_player = true
	world.add_child(dirt)
	await frames(10)
	dirt.drive(1,0,false,true)
	await frames(80)
	check(dirt.visual.rotation.x > .3 and dirt.is_on_floor(),"dirt bike sustains manual wheelie with ground support")
	check(dirt.rider.transform.basis.is_equal_approx(dirt.visual.transform.basis),"dirt rider follows wheelie")
	dirt.drive(1,0,true,true)
	await frames(15)
	check(absf(dirt.visual.rotation.x) < .001,"dirt rear brake lowers wheelie")
	dirt.drive(1,0,false,true)
	await frames(70)
	dirt.drive(0,0,false,true)
	await frames(30)
	check(dirt.manual_wheelie.pitch == 0,"releasing throttle lowers front even with lift held")
	dirt.drive(1,0,false,true)
	await frames(70)
	dirt.crash(.4)
	check(dirt.manual_wheelie.pitch == 0,"fall clears manual wheelie")
	dirt.reset_to(Transform3D.IDENTITY)
	await frames(10)
	check(dirt.manual_wheelie.pitch == 0,"checkpoint reset clears request and pitch")
	dirt.drive(1,0,false,true)
	await frames(80)
	dirt.global_position.y = 4
	dirt.floor_snap_length = 0
	await frames(3)
	check(dirt.manual_wheelie.pitch == 0,"airborne bike leaves wheelie for jump attitude control")
	dirt.reset_to(Transform3D.IDENTITY)
	dirt.floor_snap_length = .28
	await frames(10)
	dirt.launch("wheelie")
	await frames(12)
	check(dirt.visual.rotation.x > .15,"existing over-rev start wheelie still works")
	dirt.reset_to(Transform3D.IDENTITY)
	dirt.is_player = false
	dirt.drive(1,0,false,true)
	await frames(90)
	check(dirt.manual_wheelie.pitch == 0,"AI does not consume manual wheelie")
	dirt.free()
	driving.free()
	world.free()
	print("MOTORCYCLE_WHEELIE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
