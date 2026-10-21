extends SceneTree
const REVIEW := preload("res://tests/capture/capture_vehicle_blood_fleet.gd")
const BLOOD := preload("res://gameplay/vehicle_effects/VehicleBlood.gd")
const STATE := preload("res://runtime/FleetState.gd")
class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		blood=BLOOD.new()
		add_child(blood)
		set_physics_process(false)
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var street := Street.new()
	stage.add_child(street)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(100,.2,100)
	shape.shape=box
	ground.add_child(shape)
	stage.add_child(ground)
	ground.position.y=-.1
	var tested: Array = []
	for id in REVIEW.roster():
		var car = preload("res://gameplay/dispatch/DispatchVehicle.gd").new() if id.begins_with("police_") or id=="bike_police" else preload("res://scripts/Vehicle.gd").new()
		car.archetype=id
		car.vehicle_id="blood_test_"+id
		car.traffic=true
		stage.add_child(car)
		car.set_physics_process(false)
		for mask in [1,2,4,8,15]:
			car.restore_blood_stains(mask)
			var count := 0
			var fender := false
			for part in car.visual.find_children("*","MeshInstance3D",true,false):
				var overlay: Material = part.material_overlay
				if overlay is ShaderMaterial and overlay.shader==BLOOD.SHADER:
					count+=1
					check(int(overlay.get_shader_parameter("stains"))==mask,id+" side mask")
					check(BLOOD.eligible(part,car.visual),id+" no rider or spinning tire")
					if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true)==false: fender=true
			check(count>0,id+" has visible overlay meshes")
			if id.begins_with("bike_"): check(fender,id+" steering parts stained")
		var saved := STATE.capture(car,"harbor")
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
		check(STATE.validate(decoded) and int(decoded.get("blood_stains",0))==15,id+" save roundtrip")
		car.restore_blood_stains(0)
		car.restore_blood_stains(int(decoded.blood_stains))
		check(int(car.get_meta("blood_stains"))==15,id+" restored state")
		# Real swept contact with an uncontrolled NPC/service vehicle, including reverse.
		if id in ["sedan_classic","police_cruiser","police_suv","police_transport","bike_cruiser","bike_urban","bike_sport","bike_police"]:
			for reverse in [false,true]:
				car.restore_blood_stains(0)
				car.position=Vector3(0,.04,0)
				var direction := Vector3.BACK if reverse else Vector3.FORWARD
				var actor = preload("res://scripts/Actor.gd").new()
				stage.add_child(actor)
				actor.position=direction*(car.half_length+.45)+Vector3.UP*.04
				actor.set_physics_process(false)
				street._people_cache=[actor]
				for i in 3: await physics_frame
				street._hit_people(car,direction*20,direction)
				check(actor.has_meta("street_flying"),id+" NPC sweep "+str(reverse))
				var deadline := Time.get_ticks_msec()+6000
				while not actor.dead and Time.get_ticks_msec()<deadline: await physics_frame
				check(actor.dead and int(car.get_meta("blood_stains",0))==(2 if reverse else 1),id+" fatal NPC contact "+str(reverse))
				actor.free()
				await process_frame
		tested.append(id)
		print("BLOOD_FLEET_TEST ",id)
		car.free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/vehicle-blood-fleet"))
	FileAccess.open("res://artifacts/vehicle-blood-fleet/contracts.json",FileAccess.WRITE).store_string(JSON.stringify({"models":tested,"checks":checks,"failures":failures},"\t"))
	print("BLOOD_FLEET_TEST checks=",checks," failures=",failures.size())
	stage.free()
	quit(0 if failures.is_empty() else 1)
