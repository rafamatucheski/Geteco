extends "res://world/mountain_pass/MountainStaticModelView.gd"

const BOARD_INTERACTION := Vector3(4.7, 0, 3.4)
const BOARD_POSITION := Vector3(4.7, 0, 2.5)

const ART := preload("res://world/harbor/art/monaliza_workshop/MonalizaWorkshopProps3D.gd")
var display_car: Node3D
var display_car_body: StaticBody2D
var delivery_active := false
var delivery_done := false
var delivery_mechanic: Node3D
var mechanic_working := false
var work_clock := 0.0

func build_workshop() -> void:
	build_view(ART, 15.0, 20.0, Vector3(1.2, 0.8, 0.3), Vector3(0, 18, 15), Vector2i(2048, 1024))
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	for node in viewport_3d.get_children():
		if node is DirectionalLight3D:
			node.shadow_enabled = true
			node.light_energy = 1.25
		elif node is WorldEnvironment:
			node.environment.ambient_light_energy = 0.45
	# Cut away foreground masonry and overhead fittings for the gameplay camera.
	# Physical footprints stay intact; actors cannot walk through these walls.
	for child in model.get_children():
		if child is MeshInstance3D:
			if child.mesh is BoxMesh and child.position.z > 4.5 and child.mesh.size.y > 3.0:
				# A faint full-height wall still painted the office floor grey
				# over the board's approach. Cut only this instance down to a
				# low sill; its mesh still supplies the same solid ground footprint.
				child.mesh = child.mesh.duplicate()
				child.mesh.size.y = .22
				child.position.y = .11
			elif child.mesh is BoxMesh and child.position.y > 3.3 and child.mesh.size.z > 3.0:
				child.hide() # Ceiling fluorescent strips obscure the bay in this camera.
			elif child.position.z > 4.4 and child.position.y > 2.6:
				child.hide() # Open roller gate: do not draw a beam over the approach.
	preload("res://world/harbor/interiors/WorkshopDetails3D.gd").build(model)
	display_car = preload("res://world/harbor/monaliza/MonalizaModel.gd").new()
	display_car.name = "MonalizaAwaitingKeys"
	display_car.rotation.y = PI
	model.add_child(display_car)
	for side in [-0.94, 0.94]:
		for axle in [-1.28, 1.22]:
			display_car.add_wheel(side, .34, axle, .34, .23, .23, 6)
	for mesh in display_car.find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("interior_solid_id", &"DisplayCar")
	var car_bounds := preload("res://world/shared/interiors/InteriorSolidProjection.gd").mesh_bounds(display_car)
	var car_rect: Rect2 = car_bounds[&"DisplayCar"]
	display_car_body = add_solid(Rect2(-car_rect.end,car_rect.size), "MonalizaDisplayBody")
	# Separate body follows the display car's visibility lifecycle.
	for mesh in display_car.find_children("*", "MeshInstance3D", true, false): mesh.remove_meta("interior_solid_id")
	var state := get_node_or_null("/root/CampaignState")
	if state != null:
		_sync_display_car()
	set_process(true)
	var board := preload("res://world/harbor/interiors/HarborMissionBoardModel3D.gd").new()
	board.name = "MissionBoard3D"
	board.position = BOARD_POSITION
	model.add_child(board)
	for mesh in board.find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("interior_solid_id", &"MissionBoard")
	# Furniture footprints follow the final, visible geometry (including cutaways).
	var mesh_body := StaticBody2D.new()
	mesh_body.name = "WorkshopMeshSolids"
	mesh_body.collision_layer = 1
	mesh_body.collision_mask = 0
	add_child(mesh_body)
	preload("res://world/shared/interiors/InteriorSolidProjection.gd").build(model,mesh_body,project_floor)

func _process(_delta: float) -> void:
	_sync_display_car()
	if delivery_active or mechanic_working or int(viewport_3d.get_meta("interior_actor_count",0)) > 0:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if mechanic_working and is_instance_valid(delivery_mechanic):
		work_clock += _delta
		delivery_mechanic.limbs[1].rotation.x = -0.9 + sin(work_clock * 5.0) * 0.18
		delivery_mechanic.limbs[3].rotation.x = -0.75 + sin(work_clock * 5.0 + 1.0) * 0.12

func _sync_display_car() -> void:
	var state := get_node_or_null("/root/CampaignState")
	var show_car: bool = delivery_active
	if is_instance_valid(display_car) and display_car.visible != show_car:
		display_car.visible = show_car
		display_car_body.collision_layer = 1 if show_car else 0
		display_car_body.position = project_floor(Vector2(display_car.position.x,display_car.position.z)) - project_floor(Vector2.ZERO)
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(display_car_body):
		display_car_body.collision_layer = 1 if show_car else 0
		display_car_body.position = project_floor(Vector2(display_car.position.x,display_car.position.z)) - project_floor(Vector2.ZERO)

func deliver_monaliza() -> void:
	delivery_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	display_car.position = Vector3(0, 0, 8.0)
	_sync_display_car()
	delivery_mechanic = preload("res://world/harbor/monaliza/WorkshopMechanicModel.gd").new()
	delivery_mechanic.name = "DeliveryMechanic"
	delivery_mechanic.hide()
	display_car.add_child(delivery_mechanic)
	delivery_mechanic.set_process(false)
	delivery_mechanic.scale = Vector3.ONE
	delivery_mechanic.position = Vector3(-0.43, -0.25, -0.15)
	delivery_mechanic.rotation.y = PI
	for i in [0, 2]: delivery_mechanic.limbs[i].rotation.x = -PI / 2
	for i in [1, 3]: delivery_mechanic.limbs[i].rotation.x = -1.1
	var arrival := create_tween()
	arrival.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	arrival.tween_property(display_car, "position:z", 0.0, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await arrival.finished
	var door := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
	display_car.add_child(door)
	door.configure(display_car, -1.0)
	door.play(2.0)
	await get_tree().create_timer(0.3, true).timeout
	# Keep the seated actor concealed behind the opaque cabin. Reveal him only
	# in the open doorway, crouched below the roof, then stand outside the sill.
	delivery_mechanic.reparent(model, false)
	delivery_mechanic.position = Vector3(-0.82, -0.64, door.entry_center_z)
	delivery_mechanic.rotation = Vector3(0, -PI / 2, -0.18)
	delivery_mechanic.show()
	var slide := create_tween()
	slide.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	slide.tween_property(delivery_mechanic, "position", Vector3(1.34, -0.40, -door.entry_center_z), 0.55)
	await slide.finished
	var exit := create_tween().set_parallel(true)
	exit.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	exit.tween_property(delivery_mechanic, "position", Vector3(1.60, 0, -door.entry_center_z), 0.65)
	exit.tween_property(delivery_mechanic, "rotation:z", 0.0, 0.65)
	for limb in delivery_mechanic.limbs:
		exit.tween_property(limb, "rotation:x", 0.0, 0.9)
	await exit.finished
	delivery_mechanic.rotation.y = PI / 2
	delivery_mechanic.limbs[3].rotation.x = -1.0
	var speech := Label3D.new()
	speech.text = "Here you go, boss." if TranslationServer.get_locale().begins_with("en") else "Toma aqui, chefe."
	speech.position = Vector3(0, 2.15, 0)
	speech.font_size = 42
	speech.pixel_size = 0.006
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.no_depth_test = true
	delivery_mechanic.add_child(speech)
	await get_tree().create_timer(2.2, true).timeout
	speech.queue_free()
	delivery_mechanic.set_process(true)
	delivery_mechanic.walking = true
	var walk := create_tween()
	walk.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Walk around the rear of the car, then approach the actual engine bench.
	delivery_mechanic.rotation.y = PI
	walk.tween_property(delivery_mechanic, "position", Vector3(1.55, 0, -2.8), 2.3)
	walk.tween_callback(func(): delivery_mechanic.rotation.y = -PI / 2)
	walk.tween_property(delivery_mechanic, "position", Vector3(-0.95, 0, -2.8), 1.8)
	await walk.finished
	delivery_mechanic.walking = false
	delivery_mechanic.set_process(false)
	delivery_mechanic.rotation.y = PI
	mechanic_working = true
	delivery_mechanic.part(delivery_mechanic.limbs[3], Vector3(0, -0.49, 0.08), Vector3(0.045, 0.04, 0.28), Color("b8c2cc"))
	delivery_active = false
	delivery_done = true
	_sync_display_car()
