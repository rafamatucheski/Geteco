extends SceneTree
## Corrida lateral em palco limpo: Actor do jogador + WeaponRigPose (como o Gameplay alimenta).
## Args: weapon=knuckles tag=antes
const ACTOR := preload("res://scripts/Actor.gd")
const POSE := preload("res://gameplay/WeaponRigPose.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var weapon := "knuckles"; var tag := "antes"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weapon="): weapon = a.trim_prefix("weapon=")
		if a.begins_with("tag="): tag = a.trim_prefix("tag=")
	var stage := Node3D.new(); root.add_child(stage)
	var fl := StaticBody3D.new(); var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(200, 0.2, 40); sh.shape = bx; sh.position.y = -0.1; fl.add_child(sh); stage.add_child(fl)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45, 0.5, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.8, 0.8, 0.8); stage.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); stage.add_child(sun)
	var actor = ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true; actor.speed = 6.5
	stage.add_child(actor)
	var cam := Camera3D.new(); stage.add_child(cam); cam.fov = 26.0; cam.current = true
	var rig := POSE.new()
	for i in 20: await physics_frame
	actor.automatic_direction = Vector3.RIGHT
	var n := 0
	for i in 80:
		var frame: Dictionary = rig.update(weapon, 1.0 / 60.0, false, false, 0.0, true, true, actor.phase)
		actor.set_combat_weapon_pose(weapon, frame)
		if i == 70: print("FC ", frame.get("follow_clip"), " armed ", frame.get("armed"), " rs ", frame.get("right_solve"))
		await physics_frame
		cam.global_position = actor.global_position + Vector3(0, 1.1, 7.0)
		cam.look_at(actor.global_position + Vector3(0, 0.95, 0))
		if i >= 50 and (i - 50) % 3 == 0 and n < 8:
			await process_frame
			root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/game/stage_%s_%s_%d.png" % [weapon, tag, n]))
			n += 1
	print("OK phase ", actor.phase, " vel ", actor.velocity.length())
	quit()
