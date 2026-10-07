extends SceneTree
## Soco em palco limpo, vista lateral: simula o que o Gameplay faz (combat_clip da UAL + rig com clip_punch).
## Args: weapon=fists|knuckles side=left|right mode=clip|proc
const ACTOR := preload("res://scripts/Actor.gd")
const POSE := preload("res://gameplay/WeaponRigPose.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var weapon := "knuckles"; var side := "left"; var mode := "clip"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weapon="): weapon = a.trim_prefix("weapon=")
		if a.begins_with("side="): side = a.trim_prefix("side=")
		if a.begins_with("mode="): mode = a.trim_prefix("mode=")
	var stage := Node3D.new(); root.add_child(stage)
	var fl := StaticBody3D.new(); var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(200, 0.2, 40); sh.shape = bx; sh.position.y = -0.1; fl.add_child(sh); stage.add_child(fl)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45, 0.5, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.8, 0.8, 0.8); stage.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); stage.add_child(sun)
	var actor = ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true; stage.add_child(actor)
	var cam := Camera3D.new(); stage.add_child(cam); cam.fov = 24.0; cam.current = true
	cam.global_position = Vector3(-7.5 if side == "left" else 7.5, 1.2, 0); cam.look_at(Vector3(0, 1.0, 0))
	var rig := POSE.new()
	for i in 20: await physics_frame
	# prepara o golpe do lado pedido
	var tries := 0
	while true:
		rig.attack(weapon)
		if rig.punch_left == (side == "left") or tries > 6: break
		tries += 1
	var spec := {"left": ["ual/Punch_Jab", 0.17], "right": ["ual/Punch_Cross", 0.20]}[side] as Array
	var contact := float(POSE.MELEE_CONTACT.get(weapon, 0.14))
	var start := maxf(0.0, float(spec[1]) - contact)
	actor.combat_facing = 0.0 # visual.rotation.y; o corpo olha para a frente do eixo
	var age := 0.0
	var n := 0
	for i in 60:
		age += 1.0 / 60.0
		if mode == "clip":
			actor.combat_clip = spec[0]; actor.combat_clip_time = start + age
		var frame: Dictionary = rig.update(weapon, 1.0 / 60.0, true, false, 0.0, false, false, actor.phase, {"clip_punch": mode == "clip"})
		actor.set_combat_weapon_pose(weapon, frame)
		await physics_frame
		if i % 5 == 4 and n < 8:
			await process_frame
			root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/game/punch_%s_%s_%s_%d.png" % [weapon, side, mode, n]))
			n += 1
	print("OK")
	quit()
