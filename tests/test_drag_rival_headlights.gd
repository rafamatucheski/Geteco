extends SceneTree
## Productive vehicle/equipment + shared budget. A framed racer must keep its
## existing pair beyond normal traffic range, without leaking into free roam.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
var checks := 0
var failures: Array[String] = []

class State extends RefCounted:
	var world_state := {"time":.9,"weather":0}
class Production extends RefCounted:
	var state := State.new()
class World extends Node3D:
	var production := Production.new()
	var player := Node3D.new()

func _initialize() -> void:
	create_timer(40).timeout.connect(func(): push_error("DRAG_HEADLIGHT timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("DRAG_HEADLIGHT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func spawn(world: World,point: Vector3,controlled: bool,external: bool):
	var car := VEHICLE.new()
	car.archetype = "union_sedan"
	car.position = point
	world.add_child(car)
	car.set_physics_process(false)
	car.controlled = controlled
	car.external_input = external
	car.traffic = not controlled
	car.ensure_equipment(world)
	car.equipment.headlights_on = true
	return car

func settle() -> void:
	for i in 20:
		await process_frame
		BUDGET.refresh(true)

func lit_pair(car) -> bool:
	if car.equipment.lamps.size()!=2: return false
	for item in car.equipment.lamps:
		if not item.lamp.visible or item.lamp.light_energy<1.0: return false
	return true

func run() -> void:
	Engine.max_fps = 60
	var world := World.new()
	root.add_child(world)
	world.add_child(world.player)
	var camera := Camera3D.new()
	camera.name = "DesertDragSideCamera"
	camera.fov = 100
	world.add_child(camera)
	camera.position = Vector3(17,8,-18)
	camera.look_at(Vector3(0,.7,-18))
	camera.make_current()
	var player = spawn(world,Vector3.ZERO,true,false)
	var rival = spawn(world,Vector3(0,0,-35),true,true)
	var traffic = spawn(world,Vector3(0,0,-6),false,false)
	await settle()
	check(not lit_pair(rival) and traffic.equipment.npc_beam.visible,"ordinary distant traffic stays outside its 25 m budget")
	rival.set_meta("desert_drag_physics",true)
	for distance in [30.0,35.0,40.0]:
		rival.position.z = -distance
		await settle()
		check(camera.is_position_in_frustum(rival.global_position+Vector3.UP*.7) and lit_pair(rival),"framed physical rival keeps both real beams at %.0f m"%distance)
	check(lit_pair(player),"rival priority never replaces the player's pair")
	check(not traffic.equipment.npc_beam.visible and BUDGET.counts().active_lights==4,"steady NPC cap remains two and total cap remains eight")
	rival.position.z = -120
	await settle()
	check(not lit_pair(rival) and traffic.equipment.npc_beam.visible,"out-of-frustum rival releases the same NPC slots")
	rival.position.z = -35
	await settle()
	rival.remove_meta("desert_drag_physics")
	await settle()
	check(not lit_pair(rival) and traffic.equipment.npc_beam.visible,"race cleanup restores normal distance eligibility")
	rival.set_meta("desert_drag_physics",true)
	var normal_camera := Camera3D.new()
	world.add_child(normal_camera)
	normal_camera.global_transform = camera.global_transform
	normal_camera.fov = camera.fov
	normal_camera.make_current()
	await settle()
	check(not lit_pair(rival),"changing away from the race camera removes its exception")
	camera.make_current()
	await settle()
	rival.equipment.broken_left = true
	await settle()
	var lit := 0
	for item in rival.equipment.lamps:
		if item.lamp.visible: lit += 1
	check(lit==1,"the scoped priority still respects a broken headlight")
	world.free()
	await process_frame
	BUDGET.refresh(true)
	check(BUDGET.counts().registered==0,"teardown releases every budget owner")
	print("DRAG_HEADLIGHT_DONE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
