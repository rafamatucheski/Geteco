extends SceneTree
## Captura o Dante tocando clipes retargetados da UAL, para conferir a deformação.
const CLIPS := {"Pistol_Idle": 0.3, "Pistol_Aim_Up": 0.3, "Pistol_Aim_Down": 0.3, "Pistol_Shoot": 0.1, "Pistol_Reload": 0.6, "Sword_Idle": 0.3, "Sword_Attack": 0.4, "Punch_Cross": 0.2}
func _init() -> void:
	var dante: Node3D = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dante)
	var ap := dante.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.add_animation_library("ual", load("res://assets/animation_library/dante_ual.res"))
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); root.add_child(sun)
	var cam := Camera3D.new(); root.add_child(cam); cam.current = true
	root.size = Vector2i(640, 640)
	for clip in CLIPS:
		ap.play("ual/" + clip); ap.seek(CLIPS[clip], true); ap.advance(0.0)
		for i in 3: await process_frame
		var box := AABB(); var first := true
		for m in dante.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = bb if first else box.merge(bb); first = false
		var c := box.get_center()
		for view in [["front", Vector3(0, 0, 1)], ["side", Vector3(1, 0, 0)]]:
			cam.global_position = c + view[1] * (box.get_longest_axis_size() * 1.6)
			cam.look_at(c)
			await process_frame; await process_frame
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/ual-dante/%s_%s.png" % [clip, view[0]]))
	quit()
