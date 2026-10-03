extends SceneTree
const CAR := preload("res://gameplay/digo/DigoCar.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	check(not FLEET.spec("digo_gol_1993").is_empty(),"cold catalogue knows Digo before construction")
	var car := CAR.new()
	root.add_child(car)
	car.set_physics_process(false)
	check(car.archetype == "digo_gol_1993" and car.is_in_group("drivable"),"unique driveable car")
	check(car.wheels.size() == 4,"four animated wheel pivots")
	check(car.shape.shape.size.is_equal_approx(Vector3(1.72,1.43,3.80)),"collision fits compact hatch")
	check(car.max_forward_speed > 30 and car.handling.drivetrain == "fwd","turbo performance and front wheel drive")
	check(bool(FLEET.spec(car.archetype).get("turbo_audio",false)),"existing turbo sound path enabled")
	check(car.visual.get_meta("body_doors",0) == 2,"long two-door body")
	check(car.visual.get_meta("rim_inches",0) == 15,"15-inch alloy wheels")
	check(intersects_panel(car.visual,"paint",Vector3(0,2,0),Vector3(0,1.3,0)),"roof contains a solid rendered center panel")
	check(intersects_panel(car.visual,"glass",Vector3(0,1.15,-2),Vector3(0,1.15,0)),"windshield contains actual indexed triangles")
	check(car.stereo.max_distance <= 45 and not car.stereo.playing,"stereo remains silent without listener")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,2,5)
	camera.make_current()
	car._update_stereo()
	check(car.stereo.playing,"nearby listener hears stereo")
	car.stereo_enabled = false
	check(not car.stereo.playing,"stereo can be muted immediately")
	car.stereo_enabled = true
	check(car.stereo.playing,"stereo can resume nearby")
	check(CAR.install_stereo(car) == car.stereo and car.stereo.get_child_count() == 1,"restored stereo attachment is idempotent")
	camera.position = Vector3(0,2,100)
	car._update_stereo()
	check(not car.stereo.playing,"distant stereo stops playback")
	camera.position = Vector3(0,2,5)
	car.health = 0
	car._update_stereo()
	check(not car.stereo.playing,"destroyed car stops stereo")
	check(not car.door_layout(-1).is_empty(),"custom long door supports boarding")
	car.free()
	camera.free()
	await process_frame
	print("DIGO_CAR_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func intersects_panel(model: Node3D,key: String,a: Vector3,b: Vector3) -> bool:
	for part in model.get_children():
		if not part is MeshInstance3D or part.get_meta("coupe_damage_material_key","") != key: continue
		var faces: PackedVector3Array = part.mesh.get_faces()
		for i in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(a,b,faces[i],faces[i+1],faces[i+2]) != null: return true
	return false
