extends SceneTree
## Fixture física de oficina/trabalhador. Os menus da FullSession e a viagem são cobertos
## pela checagem de integração do encontro; esta fixture não certifica FPS renderizado.
const ROUTINE := preload("res://runtime/desert/DesertDigoRoutine.gd")
const WORKER := preload("res://runtime/desert/DesertDigoWorker.gd")
const SHOP := preload("res://world/desert/drag_meet/DesertDigoWorkshop.gd")
const PLAYER := preload("res://scripts/Actor.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var checks := 0
var failures: Array[String] = []

class TestState extends RefCounted:
	var region_id := "desert"
	var place_id := ""
class TestDriving extends RefCounted:
	var occupied := false
class TestGameplay extends RefCounted:
	var health := 100.0
class TestWorld extends Node3D:
	var player: CharacterBody3D
	var driving := TestDriving.new()
	var gameplay := TestGameplay.new()
class TestSession extends Node:
	var state := TestState.new()
	var world: Node3D
	var desert: Node
	var ready_for_play := true
	var modal := false
	var transitioning := false
	func is_transition_blocked() -> bool: return transitioning
	func position_clear(at: Vector3) -> bool:
		var space := world.get_world_3d().direct_space_state
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius=.31
		capsule.height=1.76
		query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.90)
		query.collision_mask=7
		if not space.intersect_shape(query,8).is_empty(): return false
		return not space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.2,at-Vector3.UP*.4,1)).is_empty()

func _initialize() -> void:
	create_timer(80).timeout.connect(func(): push_error("DIGO_ROUTINE bounded timeout"); quit(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks+=1
	print("DIGO_ROUTINE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("--no-save required"); quit(2); return
	var stage := TestWorld.new()
	root.add_child(stage)
	current_scene=stage
	var origin := ROUTINE.workshop_point()
	G.box(stage,"TestGround",origin+Vector3(0,-.15,0),Vector3(70,.3,70),Color("7e765f"),true)
	var shop := SHOP.new()
	shop.position=origin
	stage.add_child(shop)
	stage.player=PLAYER.new()
	stage.player.is_player=true
	stage.player.controlled_automatically=true
	stage.player.position=origin+Vector3(-8,.08,-6)
	stage.add_child(stage.player)
	var session := TestSession.new()
	session.world=stage
	stage.add_child(session)
	var routine := ROUTINE.new()
	stage.add_child(routine)
	routine.configure(session)
	await _frames(25)
	_check(is_instance_valid(routine.actor),"nearby shop admits one supported Digo")
	if not is_instance_valid(routine.actor): _finish(); return
	var worker: CharacterBody3D=routine.actor
	_check(worker.is_on_floor(),"worker settles on native floor")
	_check(worker.model.skeleton is Skeleton3D and worker.model.get_meta("desert_mechanic_clothes",false),"Digo keeps supplied skeleton with separate mechanic wardrobe")
	_check(worker.find_children("*","SubViewport",true,false).is_empty(),"worker shares native scene depth")
	_check(shop.solid_inventory.size()>=8,"workshop reserves complete furniture and car footprints")
	_check(shop.find_children("StrippedCarSolid","StaticBody3D",true,false).size()==1,"second project car retains its own physical supported shell")
	_check(shop.get_node("ServiceConcrete").material_override.albedo_texture!=null,"expanded service court uses a shared concrete texture")
	for probe in [
		{"label":"second project car","point":Vector3(-11,.08,-.7),"motion":Vector3(0,0,3)},
		{"label":"rear parts rack","point":Vector3(-9.5,.08,7.8),"motion":Vector3(0,0,3)},
		{"label":"engine workbench","point":Vector3(6.4,.08,4.6),"motion":Vector3(0,0,3)},
		{"label":"mobile tool cart","point":Vector3(-7.1,.08,-7.3),"motion":Vector3(0,0,2)},
		{"label":"oil drum","point":Vector3(12,.08,6.3),"motion":Vector3(0,0,2.5)},
		{"label":"relocated salvage bins","point":Vector3(-13,.08,-5.6),"motion":Vector3(0,0,3)}]:
		var pose := Transform3D(Basis.IDENTITY,origin+probe.point)
		_check(worker.test_move(pose,probe.motion),"worker sweep blocks "+str(probe.label))
		_check(stage.player.test_move(pose,probe.motion),"player sweep blocks "+str(probe.label))
	var at := worker.global_transform
	_check(worker.test_move(at,Vector3.RIGHT*5),"real worker capsule cannot cross repair car")
	var bench_pose := Transform3D(Basis.IDENTITY,origin+WORKER.BENCH_POINT)
	_check(worker.test_move(bench_pose,Vector3.BACK*3),"real worker capsule cannot cross workbench")
	_check(stage.player.test_move(bench_pose,Vector3.BACK*3),"real player capsule cannot cross workbench")
	var route := [WORKER.REPAIR_POINT,WORKER.AISLE[0],WORKER.AISLE[1],WORKER.BENCH_POINT]
	stage.player.add_collision_exception_with(worker)
	for i in route.size()-1:
		var start: Vector3=origin+route[i]+Vector3.UP*.04
		var movement: Vector3=route[i+1]-route[i]
		_check(not worker.test_move(Transform3D(Basis.IDENTITY,start),movement),"worker aisle segment %d stays physically free"%i)
		_check(not stage.player.test_move(Transform3D(Basis.IDENTITY,start),movement),"player aisle segment %d stays physically free"%i)
	stage.player.remove_collision_exception_with(worker)
	stage.player.teleport(worker.global_position+Vector3(-1,0,0))
	await _frames(2)
	_check(routine.nearest_action().get("target","")=="digo_workshop","on-foot player can interrupt Digo beside his car")
	var before_position := worker.global_position
	var before_remaining: float=worker.remaining
	var before_state: String=worker.state
	_check(routine.begin_conversation(),"conversation accepts proximity through controller")
	_check(worker.tool_audio!=null and not worker.tool_audio.playing,"conversation stops the real spatial tool source immediately")
	session.modal=true
	await _frames(30)
	_check(worker.global_position.distance_to(before_position)<.02,"conversation halts locomotion")
	_check(is_equal_approx(worker.remaining,before_remaining) and worker.state==before_state,"conversation preserves interrupted work state and clock")
	session.modal=false
	await _frames(8)
	_check(not worker.talking and worker.remaining<before_remaining,"closing conversation resumes same repair job")
	var paused_position := worker.global_position
	var paused_remaining: float=worker.remaining
	session.modal=true
	await _frames(15)
	_check(worker.global_position.distance_to(paused_position)<.02 and absf(worker.remaining-paused_remaining)<.035,"unrelated modal freezes worker and routine clock")
	_check(not worker.tool_audio.playing,"modal also stops workshop tool detail")
	session.modal=false
	stage.player.teleport(origin+Vector3(-8,.08,-6))
	# Observa um laço genuíno limitado; nenhum teleporte ou chegada falsa é injetado.
	var saw_bench := false
	var saw_return := false
	for i in 2100:
		await physics_frame
		if worker.state=="tools": saw_bench=true
		if saw_bench and worker.state=="repair": saw_return=true; break
	_check(saw_bench,"Digo walks around the car to his real workbench")
	_check(saw_return,"Digo returns from bench and resumes repairing")
	_check(worker.global_position.distance_to(origin+WORKER.REPAIR_POINT)<.12 and worker.is_on_floor(),"full loop returns supported beside car without prop overlap")
	stage.player.teleport(origin+Vector3(-1,0,0))
	session.transitioning=true
	routine.reconcile()
	await _frames(2)
	_check(not is_instance_valid(routine.actor) and get_nodes_in_group("desert_digo_mechanic").is_empty(),"transition removes worker rig and collision")
	session.transitioning=false
	stage.player.teleport(origin+Vector3(-8,.08,-6))
	routine.reconcile()
	await _frames(3)
	_check(is_instance_valid(routine.actor) and get_nodes_in_group("desert_digo_mechanic").size()==1,"reentry restores exactly one worker")
	stage.player.teleport(origin+Vector3(100,0,0))
	routine.reconcile()
	await _frames(2)
	_check(not is_instance_valid(routine.actor),"distance streaming releases worker")
	_finish()

func _finish() -> void:
	print("DIGO_ROUTINE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
