extends SceneTree
## Inventário visual de todas as armas produtivas no mesmo rig, luz, câmera e
## enquadramento. Gera um atlas de prontidão e outro no quadro de ação.

const IDS := [
	"fists", "knuckles", "knife", "bat",
	"axe", "pistol", "magnum", "smg",
	"shotgun", "sawed_off", "ak47", "m4a1",
	"hunting_rifle", "rpg", "flamethrower", "grenade",
]
const CELL := Vector2i(448, 448)
const COLUMNS := 4
const ACTOR = preload("res://scripts/Actor.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var out_dir := "res://evidence/combat/arsenal/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): out_dir = arg.trim_prefix("out_dir=").path_join("")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var view := SubViewport.new()
	view.size = CELL
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273039")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cad4df")
	environment.environment.ambient_light_energy = 0.72
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_energy = 1.35
	view.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(24, 145, 0)
	fill.light_energy = 0.65
	view.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.position = Vector3(2.1, 1.18, -3.0)
	view.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var ready := Image.create(CELL.x * COLUMNS, CELL.y * ceili(float(IDS.size()) / COLUMNS), false, Image.FORMAT_RGBA8)
	var action := Image.create(ready.get_width(), ready.get_height(), false, Image.FORMAT_RGBA8)
	for index in IDS.size():
		var id: String = IDS[index]
		var actor = ACTOR.new()
		actor.is_player = true
		view.add_child(actor)
		actor.set_physics_process(false)
		await process_frame
		var gun := Node3D.new()
		gun.name = "Weapon"
		view.add_child(gun)
		if id != "fists": ARSENAL.build(gun, id)
		var pose = POSE.new()
		await _settle(actor, pose, gun, id, false)
		var image_ready: Image = view.get_texture().get_image()
		image_ready.convert(Image.FORMAT_RGBA8)
		var at := Vector2i((index % COLUMNS) * CELL.x, (index / COLUMNS) * CELL.y)
		ready.blit_rect(image_ready, Rect2i(Vector2i.ZERO, CELL), at)
		image_ready.save_png(out_dir.path_join("%02d_%s_ready.png" % [index + 1, id]))
		pose.attack(id)
		await _settle(actor, pose, gun, id, true)
		var image_action: Image = view.get_texture().get_image()
		image_action.convert(Image.FORMAT_RGBA8)
		action.blit_rect(image_action, Rect2i(Vector2i.ZERO, CELL), at)
		image_action.save_png(out_dir.path_join("%02d_%s_action.png" % [index + 1, id]))
		actor.queue_free()
		gun.queue_free()
		await process_frame
	var ready_path := out_dir.path_join("arsenal-ready.png")
	var action_path := out_dir.path_join("arsenal-action.png")
	var ready_error := ready.save_png(ready_path)
	var action_error := action.save_png(action_path)
	print("ARSENAL_CAPTURE ready=%s error=%d action=%s error=%d order=%s" % [
		ProjectSettings.globalize_path(ready_path), ready_error,
		ProjectSettings.globalize_path(action_path), action_error, IDS,
	])
	quit(0 if ready_error == OK and action_error == OK else 1)

func _settle(actor, pose, gun: Node3D, id: String, acting: bool) -> void:
	var frames := 10 if acting else 48
	for frame in frames:
		actor.animation.play("Walking")
		actor.animation.seek(0.067, true)
		var result: Dictionary = pose.update(id, 1.0 / 60.0, true, false, 0.0, false, false, float(frame % 30) / 30.0)
		actor.combat_facing = 0.0
		actor.set_combat_weapon_pose(id, result)
		actor._apply_combat_weapon_pose()
		gun.visible = bool(result.visible)
		if id != "fists": gun.global_transform = actor.combat_weapon_transform(DATA.GRIPS.get(id, Vector3.ZERO))
		await process_frame
	await RenderingServer.frame_post_draw
