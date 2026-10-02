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
			var head:=actor.visual.find_child("head_node",true,false) as Node3D
			var forward: Vector3=-head.global_basis.z.normalized()
			for side in ["left","right"]:
				var upper:=actor.visual.find_child(side+"_upper_arm",true,false) as Node3D
				var lower:=actor.visual.find_child(side+"_lower_arm",true,false) as Node3D
				var palm:=lower.get_node("Palm") as Node3D
				check(palm.rotation.is_zero_approx(),"Forearm mesh follows elbow: %d %s %s"%[tier,side,aiming])
				var hand:=lower.to_global(Vector3(0,-.2,0))
				check((hand-upper.global_position).dot(forward)>0,"Hands in front of face direction: %d %s %s"%[tier,side,aiming])
			var weapon:=actor.visual.find_child("WeaponMount",true,false) as Node3D
			if aiming: check((-weapon.global_basis.z.normalized()).dot(forward)>.97,"Weapon points with face: %d"%tier)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6
	camera.position=Vector3(7,5,-9)
	stage.add_child(camera)
	camera.look_at(Vector3(1.4,.7,-.5))
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/cobra-neighborhood-1002/pose-corrected.png")
	print("COBRA_POSE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
