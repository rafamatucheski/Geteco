extends SceneTree
## Real Main/.NET, native jeep, boarding, session cancellation and isolated save/load.
## Staging teleports below are fixture setup; this does not certify a driven full lap.
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world
var fixture_path := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): check(false,"bounded integration timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-save: this test writes only its unique isolated fixture.")
		quit(2); return
	fixture_path="res://evidence/mountain-jeep-integration-%d/fixture.json" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_path.get_base_dir()))
	var state := STATE.new()
	var intro: Dictionary=state.intro.snapshot()
	intro.phase="complete"; intro.location_id="harbor_street"; intro.inventory={}
	intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	check(state.intro.restore_snapshot(intro),"fixture completes only the introduction")
	state.set_location("mountain","")
	state.world_state.time=.45
	var spawn := COURSE.start()+Vector3(1,.12,2)
	state.world_state.pedestrian={"region":"mountain","position":[spawn.x,spawn.y,spawn.z]}
	var store := STORE.new()
	store.path=fixture_path
	check(store.save(state)==OK,"production SaveStore accepts isolated mountain fixture")
	if not failures.is_empty(): await finish(); return
	if not await boot_world(): await finish(); return
	var pack := get_first_node_in_group("mountain_activities")
	check(pack!=null and pack.components.has("mountain_jeep"),"mountain pack installs jeep controller through production hook")
	if not failures.is_empty(): await finish(); return
	var activity=pack.components.mountain_jeep
	for i in 600:
		await physics_frame
		if is_instance_valid(activity.loan): break
	check(is_instance_valid(activity.loan),"native supplied jeep spawns on streamed supported paddock")
	if not failures.is_empty(): await finish(); return
	var car: CharacterBody3D=activity.loan
	var identity := car.get_instance_id()
	activity._ensure_loan()
	check(car.get_instance_id()==identity and owned_count()==1,"repeated proximity update cannot duplicate supplied jeep")
	check(world.production.vehicle_position_clear(car,car.position,car.rotation.y),"actual chassis fits with support under all wheels")
	world.player.teleport(car.driver_door_anchor(-1)+Vector3.UP*.08)
	await frames(3)
	check(world.driving.interact(),"ordinary Driving interaction boards supplied jeep")
	for i in 240:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	check(world.driving.occupied and world.driving.car==car,"boarding keeps same native vehicle body")
	if not failures.is_empty(): await finish(); return
	car.place(COURSE.start()+Vector3.UP*.12,COURSE.parking_yaw())
	await frames(4)
	check(activity.perform("start") and world.session.modal and not activity.active,"interaction explains rules before starting the timer")
	world.session.close_menu()
	check(not activity.active and not car.input_locked,"closing instructions keeps attempt idle and releases driving controls")
	check(activity.perform("start") and world.session.modal,"instructions can be reopened")
	check(activity._start_attempt() and activity.active and not world.session.modal,"confirming instructions starts timed jeep attempt")
	check(not world.session.save_game(true),"session blocks saving a moving attempt")
	paused=true
	var countdown: float=activity.run.countdown
	await process_frame
	await process_frame
	check(is_equal_approx(activity.run.countdown,countdown),"pause preserves countdown")
	paused=false
	check(world.driving.leave(),"ordinary door exit remains available during attempt")
	for i in 240:
		await physics_frame
		if not world.driving.occupied and not world.driving.is_body_transition_active(): break
	# O controlador cancela no próximo _physics_process depois da descida; dá alguns quadros.
	await frames(4)
	check(not activity.active and is_instance_valid(car),"leaving cancels without deleting the supplied jeep")
	check(activity.progress.data.finishes==0 and world.session.state.economy.balance==0,"cancel does not pay or count a finish")
	world.player.teleport(car.driver_door_anchor(-1)+Vector3.UP*.08)
	await frames(3)
	check(world.driving.interact(),"same parked jeep can be boarded again")
	for i in 240:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	car.place(COURSE.start()+Vector3.UP*.12,COURSE.parking_yaw())
	await frames(3)
	check(activity.perform("start") and world.session.modal,"retry opens instructions without consuming time")
	check(activity._start_attempt() and activity.run.countdown>0.0,"retry starts from fresh countdown")
	var token: int=world.session._begin_transition("jeep_integration_probe")
	await frames(2)
	check(not activity.active,"real session transition token cancels attempt")
	world.session._finish_transition(token)
	await frames(3)
	check(not car.input_locked and world.driving.occupied,"cancellation does not steal or leave driving controls locked")
	check(world.session.save_game(true),"normal session snapshot resumes after cancellation")
	check(store.save(world.session.state)==OK,"isolated save stores base fleet identity and jeep snapshot together")
	if not failures.is_empty(): await finish(); return
	world.queue_free()
	await frames(4)
	if not await boot_world(): await finish(); return
	pack=get_first_node_in_group("mountain_activities")
	activity=pack.components.mountain_jeep
	for i in 240:
		await physics_frame
		if is_instance_valid(activity.loan): break
	check(is_instance_valid(activity.loan) and owned_count()==1,"load adopts restored base-fleet jeep instead of creating duplicate")
	check(activity.progress.data.finishes==0 and not activity.active,"interrupted attempt is never revived by loading")
	check(world.production.store.path==fixture_path,"personal saves remain outside fixture storage")
	await finish()

func boot_world() -> bool:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",fixture_path)
	root.add_child(world)
	for i in 3600:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	var ready: bool=world.session!=null and world.session.ready_for_play
	check(ready,"real Main/.NET reaches ready-for-play")
	if ready: check(world.production.loaded_save and not world.production.save_invalid,"production loader accepts fixture")
	return ready and failures.is_empty()

func owned_count() -> int:
	var total := 0
	for car in world.production.vehicles:
		if is_instance_valid(car) and not car.is_queued_for_deletion() and car.vehicle_id==COURSE.LOAN_ID: total+=1
	return total

func frames(count: int) -> void:
	for i in count: await physics_frame

func finish() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await frames(3)
	print("MOUNTAIN_JEEP_INTEGRATION_RESULT checks=%d failures=%d fixture=%s" % [checks,failures.size(),fixture_path])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks+=1
	print("MOUNTAIN_JEEP_INTEGRATION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
