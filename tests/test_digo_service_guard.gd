extends SceneTree
## Real room, real vehicle and physical doorway blockers; no Main/save/UI fixture.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

class ServiceSession extends RefCounted:
	var room: Node3D
	var state := {"place_id":"desert_digo"}
	var ready_for_play := false
	var message := ""
	func show_message(value: String) -> void: message = value

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	print("DIGO_SERVICE_GUARD ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _frames(count: int) -> void:
	for frame in count: await physics_frame

func _run() -> void:
	root.size = Vector2i(1280,720)
	var world := Node3D.new()
	root.add_child(world)
	var session := ServiceSession.new()
	session.room = PLACES.create_place("desert_digo")
	session.room.position = Vector3(0,0,-2400)
	world.add_child(session.room)
	var gameplay_camera := Camera3D.new()
	world.add_child(gameplay_camera)
	gameplay_camera.make_current()
	var car := VEHICLE.new()
	car.archetype = "desert_coyote"
	car.vehicle_id = "test_service_guard"
	world.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	car.place(session.room.to_global(Vector3(0,.12,0)),PI)
	var helper := DRIVE.new()
	world.add_child(helper)
	helper.configure(session)
	helper.set_physics_process(false)
	await _frames(3)
	_check(helper.service_admission_reason(car).is_empty(),"centred outward-facing vehicle is admitted")
	car.place(session.room.to_global(Vector3(2,.12,0)),PI)
	_check(not helper.service_admission_reason(car).is_empty(),"vehicle outside authored bay cannot open service")
	car.place(session.room.to_global(Vector3(0,.12,0)),0.0)
	_check(not helper.service_admission_reason(car).is_empty(),"vehicle facing away from exit must align without teleport")
	car.place(session.room.to_global(Vector3(0,.12,0)),PI)
	var blocker := CharacterBody3D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	blocker.add_child(shape)
	world.add_child(blocker)
	blocker.global_position = session.room.to_global(Vector3(0,.04,8.9))
	await _frames(2)
	_check(not helper.open_service_view(car),"occupied doorway refuses shutter closure")
	_check(helper._service_shutter == null and helper._service_walls.is_empty() and gameplay_camera.current,"refusal does not mutate wall, camera or doorway")
	_check(session.message.contains("passagem"),"refusal explains blocked passage")
	blocker.global_position = session.room.to_global(Vector3(5,.04,6))
	await _frames(2)
	_check(helper.open_service_view(car),"cleared doorway opens service normally")
	# Para as checagens de vida da câmera; esta fixture fornece de propósito só o contrato da sala.
	helper.set_process(false)
	await _frames(2)
	var shutter: StaticBody3D = helper._service_shutter.get_node("Collision")
	_check(shutter.collision_layer == 1 and helper._service_walls.size() == 2,"active service has a physical shutter and full front walls")
	helper.camera_action("reset",0.0)
	helper._yaw = 0.0
	_check(helper._update_camera(false) and is_equal_approx(helper._yaw,0.0) and helper.car_fits_preview() and helper._camera.fov <= 50.0,"real padded Coyote bounds fit the frontal centre within fifty degrees")
	helper.camera_action("reset",0.0)
	helper._rotate = true
	var continuous := true
	var stays_inside := true
	var minimum_yaw := helper._yaw
	var maximum_yaw := helper._yaw
	var moved := 0
	for sample in 720:
		var prior: Vector3 = helper._camera.global_position
		helper._process(1.0/30.0)
		var movement: float = prior.distance_to(helper._camera.global_position)
		if movement > .25: continuous = false
		if movement > .001: moved += 1
		if not helper.car_fits_preview(): stays_inside = false
		minimum_yaw = minf(minimum_yaw,helper._yaw)
		maximum_yaw = maxf(maximum_yaw,helper._yaw)
	_check(continuous and moved > 700,"720 continuous orbit updates never jump more than twenty-five centimetres or freeze")
	_check(stays_inside,"all 720 actual projected padded car volumes stay above footer and beside sidebar")
	_check(minimum_yaw <= -.94 and maximum_yaw >= .94,"automatic orbit retains the complete authored frontal arc")
	helper._rotate = false
	helper.camera_action("reset",0.0)
	var accepted_pose: Transform3D = helper._camera.global_transform
	var accepted_fov: float = helper._camera.fov
	var accepted_yaw: float = helper._yaw
	# Um palco impossível força cada candidato a passar por uma falha real de projeção.
	# O código antigo vazava a pose final de ângulo zero em vez de reverter.
	root.size = Vector2i(40,720)
	helper._yaw = -.8
	_check(not helper._update_camera(),"impossible preview stage rejects every fallback candidate")
	_check(helper._camera.global_transform.is_equal_approx(accepted_pose) and is_equal_approx(helper._camera.fov,accepted_fov) and is_equal_approx(helper._yaw,accepted_yaw),"rejected fallback never replaces the last accepted pose, FOV or logical angle")
	helper._rotate = true
	var attempted_direction: float = helper._orbit_direction
	helper._process(1.0/30.0)
	_check(helper._camera.global_transform.is_equal_approx(accepted_pose) and helper._orbit_direction == -attempted_direction,"automatic orbit reverses safely at a real fit boundary")
	helper.orbit_by(Vector2(.2,0))
	_check(helper._camera.global_transform.is_equal_approx(accepted_pose) and is_equal_approx(helper._yaw,accepted_yaw),"invalid manual drag preserves the accepted physical view")
	root.size = Vector2i(1280,720)
	helper.close_service_view()
	_check(helper._service_shutter == null and helper._service_walls.is_empty() and shutter.collision_layer == 0,"closing releases all temporary geometry immediately")
	_check(gameplay_camera.current and helper._camera == null,"closing restores previous camera")
	await _frames(2)
	_check(not is_instance_valid(shutter),"closing frees shutter collider")
	world.free()
	print("DIGO_SERVICE_GUARD checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
