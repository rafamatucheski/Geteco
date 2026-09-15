extends "res://tests/test_medical_work_zone_lifecycle.gd"
var approaching_bus: CharacterBody2D
var bus_clear := true
var bus_stopped := false
var bus_resumed := false
var stopped_at := Vector2.ZERO
var picture_taken := false
var picture_pending := false

func run() -> void:
	physics_frame.connect(_approach_rescue)
	await super.run()

func _approach_rescue() -> void:
	if not is_instance_valid(world): return
	var sequence: Node
	for unit in get_nodes_in_group("emergency_vehicle"):
		if unit.has_meta("medical_sequence"):
			sequence = unit.get_meta("medical_sequence")
			break
	if not is_instance_valid(sequence): return
	if approaching_bus == null and sequence.phase == "treat" and not sequence.hospital_delivery:
		var lane := Path2D.new()
		lane.name = "BusAlongWorkingCrew"
		lane.curve = Curve2D.new()
		lane.curve.add_point(Vector2(700, 50))
		# Continue south on a separate street, away from the hospital's unloading bay.
		lane.curve.add_point(Vector2(130, 50), Vector2.ZERO, Vector2(-39, 0))
		lane.curve.add_point(Vector2(60, 120), Vector2(0, -39), Vector2.ZERO)
		lane.curve.add_point(Vector2(60, 900))
		world.add_child(lane)
		var follow := PathFollow2D.new()
		follow.loop = false
		lane.add_child(follow)
		approaching_bus = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
		approaching_bus.set_script(preload("res://world/harbor/HarborTransitBus.gd"))
		follow.add_child(approaching_bus)
		approaching_bus.dwelling = false
		approaching_bus.speed = 140
		approaching_bus.set_process(false)
		approaching_bus.set_physics_process(false)
		var camera := world.get_viewport().get_camera_2d()
		camera.position = Vector2(200, 25)
		camera.zoom = Vector2.ONE * 1.8
	if not is_instance_valid(approaching_bus): return
	approaching_bus.advance_on_lane(Engine.time_scale / Engine.physics_ticks_per_second)
	approaching_bus._update_3d_orientation(Engine.time_scale / Engine.physics_ticks_per_second)
	var overlapping := preload("res://emergency/MedicalRescueWorkZone.gd").blocks_hull(approaching_bus, approaching_bus.collision.shape, approaching_bus.collision.global_transform)
	bus_clear = bus_clear and not overlapping
	if not sequence.hospital_delivery and sequence.phase != "transport" and approaching_bus.global_position.x < 500 and approaching_bus._lane_motion_speed < 2:
		bus_stopped = true
		stopped_at = approaching_bus.global_position
		if render and not picture_pending and not picture_taken and sequence.phase in ["return_with_patient", "align_to_load", "load_patient"]:
			picture_pending = true
			_capture.call_deferred()
	if bus_stopped and (sequence.phase == "transport" or sequence.hospital_delivery):
		bus_resumed = bus_resumed or approaching_bus.global_position.x < stopped_at.x - 100

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/medical-bus-stopped-for-crew.png")
	picture_taken = true
	picture_pending = false

func check(ok: bool, label: String) -> void:
	if label.begins_with("Parked ambulance survives"):
		super.check(bus_clear, "A real local bus never overlaps the moving rescue crew or cot")
		super.check(bus_stopped, "A real local bus stops beside the active medical sequence")
		super.check(bus_resumed, "The same bus resumes after the last medic actually boards")
		print("MEDICAL_BUS_INTEGRATION clear=", bus_clear, " stopped=", bus_stopped, " resumed=", bus_resumed, " captured=", picture_taken)
	super.check(ok, label)
