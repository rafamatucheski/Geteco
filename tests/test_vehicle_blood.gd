extends SceneTree
const BLOOD := preload("res://gameplay/vehicle_effects/VehicleBlood.gd")
const FLEET := preload("res://runtime/FleetState.gd")
class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		blood = BLOOD.new()
		add_child(blood)
		set_physics_process(false)
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var car = preload("res://scripts/Vehicle.gd").new()
	car.archetype = "sport_coupe"
	stage.add_child(car)
	car.set_physics_process(false)
	var street := Street.new()
	stage.add_child(street)
	for kind in ["survivor", "protected", "dead"]:
		var actor = preload("res://scripts/Actor.gd").new()
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.set_meta("vehicle_blood_side", BLOOD.impact_side(car,Vector3.FORWARD))
		if kind == "protected": actor.set_meta("invulnerable", true)
		street.on_body_landed(actor, kind != "survivor", car, 20.0, Vector3.FORWARD)
		check(int(car.get_meta("blood_stains",0)) == (1 if kind == "dead" else 0), kind)
	car.restore_blood_stains(3)
	var saved := FLEET.capture(car,"harbor")
	var file := FileAccess.open("user://vehicle-blood-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(saved)); file.close()
	var decoded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://vehicle-blood-test.json"))
	check(FLEET.validate(decoded) and decoded.blood_stains == 3,"save JSON roundtrip")
	var restored = preload("res://scripts/Vehicle.gd").new()
	restored.archetype = "sport_coupe"
	stage.add_child(restored)
	restored.set_physics_process(false)
	restored.restore_blood_stains(int(decoded.blood_stains))
	var overlays := 0
	for part in restored.visual.find_children("*","MeshInstance3D",true,false):
		if part.material_overlay != null: overlays += 1
	check(overlays > 0,"restored visible overlays")
	for i in 30: restored.restore_blood_stains(3)
	var after := 0
	for part in restored.visual.find_children("*","MeshInstance3D",true,false):
		if part.material_overlay != null: after += 1
	check(after == overlays,"bounded repeated impacts")
	check(BLOOD.impact_side(car,Vector3.BACK)==2 and BLOOD.impact_side(car,Vector3.LEFT)==4,"reverse and lateral impacts")
	for invalid in [-1,16,1.5,"1",null]: check(not BLOOD.valid(invalid),"invalid state rejected")
	decoded.erase("blood_stains")
	check(FLEET.validate(decoded),"legacy save")
	# Exercise the real swept contact -> flight -> landing -> confirmed death chain.
	car.restore_blood_stains(0)
	car.position = Vector3(100, .04, 0)
	car.controlled = true
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40,.2,40)
	shape.shape = box
	ground.add_child(shape)
	stage.add_child(ground)
	ground.position = Vector3(100,-.1,0)
	var victim = preload("res://scripts/Actor.gd").new()
	stage.add_child(victim)
	victim.position = Vector3(100,.04,-2.9)
	victim.set_physics_process(false)
	for tick in 3: await physics_frame
	street._hit_people(car,Vector3(0,0,-20),Vector3(0,0,-1))
	check(victim.has_meta("street_flying"),"swept bumper starts flight")
	var deadline := Time.get_ticks_msec()+6000
	while not victim.dead and Time.get_ticks_msec()<deadline: await physics_frame
	check(victim.dead and int(car.get_meta("blood_stains",0))==1,"fatal swept collision stains front")
	car.repair()
	check(int(car.get_meta("blood_stains",0))==1,"repair does not wash blood")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://vehicle-blood-test.json"))
	stage.free()
	await process_frame
	quit(0 if failures == 0 else 1)
