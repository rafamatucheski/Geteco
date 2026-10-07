extends SceneTree
## Escada em palco limpo: lateral, `ladder/Ladder_Descend` e `Fast_Ladder_Climb`, mais a emenda do ciclo.
const ACTOR := preload("res://scripts/Actor.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var stage := Node3D.new(); root.add_child(stage)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45, 0.5, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.8, 0.8, 0.8); stage.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); stage.add_child(sun)
	# degraus como no bueiro: largura 0,56, espaçados 0,10, em z = 0; o corpo encara -Z
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color("8b927f")
	for r in 22:
		var m := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.56, 0.018, 0.025); m.mesh = b; m.material_override = steel; m.position = Vector3(0, 1.2 - r * 0.10, 0); stage.add_child(m)
	for x in [-0.27, 0.27]:
		var m := MeshInstance3D.new(); var c := CylinderMesh.new(); c.top_radius = 0.018; c.bottom_radius = 0.018; c.height = 2.4; m.mesh = c; m.material_override = steel; m.position = Vector3(x, 0.1, 0); stage.add_child(m)
	var actor = ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true; stage.add_child(actor)
	actor.set_physics_process(false)
	actor.global_position = Vector3(0, 0, 0.30)
	actor.visual.rotation.y = 0.0
	var cam := Camera3D.new(); stage.add_child(cam); cam.fov = 26.0; cam.current = true
	cam.global_position = Vector3(7.0, 0.9, 0.3); cam.look_at(Vector3(0, 0.85, 0.3))
	for i in 3: await process_frame
	var seam := {}
	for clip in ["ladder/Ladder_Descend", "Fast_Ladder_Climb"]:
		var length: float = actor.animation.get_animation(clip).length
		actor._pose_clip(clip, 0.0)
		var first: Array = actor._capture_pose()
		actor._pose_clip(clip, length)
		var last: Array = actor._capture_pose()
		var worst := 0.0
		for b in mini(first.size(), last.size()): worst = maxf(worst, (first[b][1] as Quaternion).angle_to(last[b][1] as Quaternion))
		print("EMENDA ", clip, " len=", snapped(length, 0.01), " maior giro de osso entre fim e início = ", snapped(rad_to_deg(worst), 0.1), "°")
		for s in 8:
			actor._pose_clip(clip, length * s / 8.0)
			await process_frame; await process_frame
			root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/sewer/stage_%s_%d.png" % [clip.replace("/", "_"), s]))
	# emenda com a mistura da apresentação do bueiro
	var presentation: Node = preload("res://gameplay/SewerHatchDescent.gd").new()
	presentation.actor = actor
	for clip in ["ladder/Ladder_Descend", "Fast_Ladder_Climb"]:
		var length: float = actor.animation.get_animation(clip).length
		presentation._ladder_pose(clip, length - 0.001)
		var near_end: Array = actor._capture_pose()
		presentation._ladder_pose(clip, length)
		var start: Array = actor._capture_pose()
		var worst := 0.0
		for b in mini(near_end.size(), start.size()): worst = maxf(worst, (near_end[b][1] as Quaternion).angle_to(start[b][1] as Quaternion))
		print("EMENDA_MISTURADA ", clip, " ", snapped(rad_to_deg(worst), 0.1), "°")
	quit()
