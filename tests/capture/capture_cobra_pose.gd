extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	root.size=Vector2i(1280,720)
	var stage:=Node3D.new()
	root.add_child(stage)
	current_scene=stage
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("303c42")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.7
	environment.environment=settings
	stage.add_child(environment)
	var lamp:=DirectionalLight3D.new()
	lamp.rotation_degrees=Vector3(-50,-40,0)
	stage.add_child(lamp)
	for tier in 3:
		for aiming in [false,true]:
			var actor:=preload("res://gameplay/urban_v1/CobraLocalGuard.gd").new()
			actor.tier=tier
			actor.position=Vector3(tier*1.5,0,-2 if aiming else 1)
			stage.add_child(actor)
			actor.set_physics_process(false)
			preload("res://gameplay/urban_v1/CobraAppearance.gd").arms(actor.visual,aiming)
			var body = actor.visual.body
			body._pose(0.0)
			check(body.get_script()==preload("res://assets/CivilianModel.gd"), "Shared pedestrian anatomy: %d"%tier)
			check(actor.visual.find_children("CobraInsignia*","MeshInstance3D",true,false).size()==2,"Front and back insignia: %d"%tier)
			var contacts: Array = actor.visual.weapon_hand_contacts()
			for side in 2:
				var hand: Vector3 = body.forearms[side].to_global(Vector3(0,-body.KIT.FOREARM-.06,0))
				if contacts[side] is Vector3:
					check(hand.distance_to(contacts[side])<.025,"Hand reaches weapon: %d %d %s"%[tier,side,aiming])
				if not aiming:
					check(hand.y<body.upper_arms[side].global_position.y-.14,"Resting hand below shoulder: %d %d"%[tier,side])
			if tier==0 and not aiming: check(contacts[1]==null,"Pistol leaves free arm relaxed")
			if aiming: check((-actor.visual.weapon.global_basis.z.normalized()).dot(-actor.visual.global_basis.z)>.97,"Weapon points forward: %d"%tier)
	var car := preload("res://scripts/Vehicle.gd").new()
	car.archetype = "cobra_v8"
	car.position = Vector3(10,0,0)
	stage.add_child(car)
	car.set_physics_process(false)
	var cabin: Dictionary = preload("res://gameplay/VehicleInterior.gd").spec(car)
	for index in 2:
		var crew := preload("res://gameplay/CobraModel.gd").new()
		crew.tier = index
		crew.seated = true
		crew.position = Vector3(cabin.sx if index==0 else -cabin.sx,cabin.floor,cabin.sz)
		car.add_child(crew)
		crew.fit_seat(car,cabin,index==0)
		var body = crew.body
		check(crew._seated_head_top(car)<float(cabin.roof)-.02,"Seated head fits below painted roof: %d"%index)
		check(car.to_local(body.pelvis.global_position).y>float(cabin.cush),"Seated hip stays above seat cushion: %d"%index)
		for side in 2:
			var hand: Vector3 = body.forearms[side].to_global(Vector3(0,-body.KIT.FOREARM-.06,0))
			check(hand.distance_to(body.hand_targets[side])<.025,"Seated hand reaches wheel or lap: %d %d"%[index,side])
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6
	camera.position=Vector3(7,5,-9)
	stage.add_child(camera)
	camera.look_at(Vector3(1.4,.7,-.5))
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/cobra-neighborhood-1002/native-pose.png")
	print("COBRA_POSE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
