extends SceneTree
const Activities := preload("res://activities/Activities.gd")
const Motors := preload("res://activities/Motorsport.gd")
const Residence := preload("res://activities/Residence.gd")
const Definitions := preload("res://activities/ActivityDefinitions.gd")
const Dialogue := preload("res://systems/campaign/OriginalDialogue.gd")
const MissionWorld := preload("res://runtime/MissionWorld.gd")
var checks := 0
var failures: Array[String] = []

class TowControllerFixture extends RefCounted:
	var world: Node3D
	var vehicles: Array = []
	func spawn_vehicle(id: String, point: Vector3, yaw: float):
		var car = preload("res://scripts/Vehicle.gd").new()
		car.archetype = id
		car.position = point
		car.rotation.y = yaw
		world.add_child(car)
		vehicles.append(car)
		return car

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_motorsport()
	_restore()
	_sources()
	_tow_persistence()
	for message in failures: push_error(message)
	print("%s activities: %d checks"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _tow_persistence() -> void:
	var empty := {"version":1,"job":{},"loaded":false,"unloaded_at_bay":false,"truck":{},"cargo":{}}
	_check(MissionWorld.validate_snapshot(empty),"Empty tow state is valid")
	var data := empty.duplicate(true)
	data.job = preload("res://data/catalogs/TowJobs.gd").JOBS[0].duplicate(true)
	data.job.merge({"index":0,"token":"tow_1"})
	data.truck = {"archetype":"towmaster","position":[-37.0,.1,61.0],"yaw":PI,"health":100,"paint":"ffffffff"}
	data.cargo = {"archetype":"ranch_single","position":[217.5,.1,260.0],"yaw":0.0,"health":100,"paint":"983f43ff"}
	_check(MissionWorld.validate_snapshot(data),"Tow vehicle IDs transforms and damage survive schema")
	_check(MissionWorld.validate_ownership(data,"",data.job),"Activity contract owns corresponding tow cargo")
	var different: Dictionary = data.job.duplicate(true)
	different.token = "tow_2"
	_check(not MissionWorld.validate_ownership(data,"",different),"A different contract cannot collect the cargo")
	_check(not MissionWorld.validate_ownership(empty,"",data.job),"New saves cannot silently lose active cargo")
	data.loaded = true
	_check(MissionWorld.validate_snapshot(data),"Loaded cargo is persistable")
	data.unloaded_at_bay = true
	_check(not MissionWorld.validate_snapshot(data),"Cannot be loaded and delivered at once")
	data.unloaded_at_bay = false
	data.cargo.position[0] = NAN
	_check(not MissionWorld.validate_snapshot(data),"Reject nonfinite physical position")
	data.cargo.position[0] = 217.5
	data.job.reward += 1
	_check(not MissionWorld.validate_snapshot(data),"Reject forged job reward")
	data.job = {"story":true,"kind":"local"}
	_check(MissionWorld.validate_ownership(data,"cobra_contact",{}),"Narrative tow ownership restores with campaign")
	_check(not MissionWorld.validate_ownership(data,"cobra_race",{}),"Reject orphan narrative cargo")
	_check(not MissionWorld.validate_ownership(data,"cobra_contact",different),"Narrative and side tow cannot overlap")
	var runtime := MissionWorld.new()
	_check(not runtime.restore_snapshot({}),"Invalid restore fails before touching scene")
	runtime.free()
	var world := Node3D.new()
	root.add_child(world)
	var controller := TowControllerFixture.new()
	controller.world = world
	runtime = MissionWorld.new()
	runtime.session = {"world":world,"controller":controller,"state":{"region_id":"harbor"},"ready_for_play":false}
	world.add_child(runtime)
	_check(runtime.restore_snapshot(JSON.parse_string(JSON.stringify(data))),"Restore actual native tow bodies from JSON")
	_check(controller.vehicles.size()==2,"Restore creates exactly one truck and one cargo")
	_check(runtime.cargo.collision_layer==0 and not runtime.cargo.is_physics_processing(),"Carried restore disables independent collision and physics")
	_check(runtime.truck.health==100 and runtime.cargo.health==100,"Restore preserves vehicle damage")
	_check(runtime.cargo.global_position.is_equal_approx(runtime.truck.to_global(Vector3(0,1.05,1.3))),"Restored cargo sits on restored flatbed")
	var roundtrip: Dictionary = runtime.snapshot()
	_check(MissionWorld.validate_ownership(roundtrip,"cobra_contact",{}),"Runtime snapshot remains valid after native restoration")
	_check(runtime.restore_snapshot(roundtrip) and controller.vehicles.size()==2,"Identical restoration is idempotent")
	_check(not runtime.begin_tow_job(different),"Side contract cannot steal live narrative cargo")
	world.free()

func _countdown(run) -> void:
	for i in 31: run.update(.1,Vector3.ZERO,Vector3.ZERO,Vector3.FORWARD,true)

func _motorsport() -> void:
	var run := Motors.new()
	_check(run.begin_race("sprint_doca",Vector3.ZERO,PackedVector3Array([Vector3(10,0,0)]),Vector3.ZERO),"Race accepted at physical start")
	_check(not run.begin_race("sprint_doca",Vector3.ZERO,PackedVector3Array([Vector3(10,0,0)]),Vector3.ZERO),"Cannot begin two activities")
	_countdown(run)
	_check(run.countdown == 0,"Original three-second countdown")
	for x in range(1,11): run.update(.1,Vector3(x,0,0),Vector3(10,0,0),Vector3.RIGHT,true)
	_check(run.gate == 1 and not run.finished,"Checkpoint requires physical crossing then return")
	for x in range(9,-1,-1): run.update(.1,Vector3(x,0,0),Vector3(-10,0,0),Vector3.LEFT,true)
	_check(run.finished and run.mode == "","Physical route and return finish race")
	var early := Motors.new()
	early.begin_race("sprint_doca",Vector3.ZERO,PackedVector3Array([Vector3(10,0,0)]),Vector3.ZERO)
	early.update(.1,Vector3(5,0,0),Vector3.RIGHT*50,Vector3.RIGHT,true)
	_check(early.cancelled,"Early departure cancels countdown")
	var teleport := Motors.new()
	teleport.begin_race("sprint_doca",Vector3.ZERO,PackedVector3Array([Vector3(100,0,0)]),Vector3.ZERO)
	_countdown(teleport)
	teleport.update(.1,Vector3(100,0,0),Vector3.ZERO,Vector3.RIGHT,true)
	_check(teleport.cancelled and not teleport.finished,"Teleport does not complete checkpoint")
	var driver := Motors.new()
	driver.begin_drift("test",Vector3.ZERO,20,Vector3.ZERO)
	driver.update(.1,Vector3.ZERO,Vector3.ZERO,Vector3.FORWARD,false)
	_check(driver.cancelled,"Leaving or breaking car cancels activity")
	var straight := Motors.new()
	straight.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in range(1,11): straight.update(.1,Vector3(0,0,-i),Vector3(0,0,-10),Vector3.FORWARD,true)
	_check(straight.score == 0,"Driving straight does not score drift")
	var wall := Motors.new()
	wall.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in 10: wall.update(.1,Vector3.ZERO,Vector3(6,0,-10),Vector3.FORWARD,true)
	_check(wall.score == 0,"Pushing against a wall cannot score desired velocity")
	var drift := Motors.new()
	drift.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in range(1,11): drift.update(.1,Vector3(.4*i,0,-.7*i),Vector3(4,0,-7),Vector3.FORWARD,true)
	_check(drift.score > 0 and drift.combo > 1,"Real forward lateral slide scores and builds combo")
	var reverse := Motors.new()
	reverse.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in range(1,11): reverse.update(.1,Vector3(.4*i,0,.7*i),Vector3(4,0,7),Vector3.FORWARD,true)
	_check(reverse.score == 0,"Reverse spins do not count as controlled drift")
	var slow := Motors.new()
	slow.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in range(1,11): slow.update(.1,Vector3(.1*i,0,-.1*i),Vector3(1,0,-1),Vector3.FORWARD,true)
	_check(slow.score == 0,"Original minimum speed/lateral thresholds preserved")
	var expired := Motors.new()
	expired.begin_drift("test",Vector3.ZERO,100,Vector3.ZERO)
	for i in 251: expired.update(.1,Vector3.ZERO,Vector3.ZERO,Vector3.FORWARD,true)
	_check(expired.finished,"Original drift duration 25 seconds")

func _restore() -> void:
	var activities := Activities.new()
	var original := activities.snapshot()
	_check(Activities.validate_snapshot(original),"Initial activities state valid")
	_check(activities.restore_snapshot(JSON.parse_string(JSON.stringify(original))),"Activities JSON restore")
	for patch in [{"version":2},{"tow_taken_today":4},{"day_clock":600},{"race_best":{"invented":1}},{"drift_best":{"harbor_westgate":-5}},{"tow_contract":{"index":0,"reward":9999}},{"day":0}]:
		var invalid := original.duplicate(true)
		invalid.merge(patch,true)
		_check(not activities.restore_snapshot(invalid),"Invalid activity snapshot rejected: "+str(patch))
	activities.free()
	var home := Residence.new()
	_check(Residence.validate_snapshot(home.snapshot()),"Original residence state schema")
	var properties: Dictionary = Definitions.HOMES.PROPERTIES
	var offer := Residence.Rules.purchase_quote(properties,"westgate_garden","quayside_house",25000)
	_check(offer.refund == 7000 and offer.due == 18000,"Original 70 percent property trade-in")
	_check(not Residence.Rules.purchase_quote(properties,"westgate_garden","westgate_garden",25000).valid,"Cannot buy active home again")
	var invalid := home.snapshot()
	invalid.active_home = "invented"
	_check(not home.restore_snapshot(invalid),"Unknown home rejected")

func _sources() -> void:
	_check(Definitions.races("harbor").is_empty(),"Legacy routes not falsely placed in Harbor")
	_check(Definitions.races("legacy").size() == 5,"All five original legacy races retained")
	_check(Definitions.drifts("harbor").size() == 2,"Both production Harbor drift yards")
	_check(Definitions.drifts("legacy").size() == 3,"Three legacy drift zones retained separately")
	var points := Definitions.collectibles()
	_check(points.size() == 10,"Ten original collectible IDs")
	var ids := {}
	for row in points: ids[row.id] = true
	_check(ids.size() == 10,"No duplicated collectible identity")
	_check(points[0].point == Vector3(-340.0/16,0,2032.0/16),"Memorial letter includes cemetery parent transform")
	_check(points[7].point == Definitions.at(Vector2(6200,-320),"mountain")+Vector3(3.2,0,3.8),"Mountain pack uses regional offset and native local metres")
	var dialogue := Dialogue.new()
	for id in ["ferrugem_met","neco_repair_received","ferrugem_work_order_received","resident_met","resident_saved","supply_records_collected","transfer_document_collected","cobra_race_begin","cobra_finale_clue"]:
		_check(not dialogue.lines(id).is_empty(),"Verbatim original dialogue exists: "+id)
