extends SceneTree
## Inventário visual V1 com a mesma ordem, câmera e dois estados do atlas V2.

const IDS := [
	"fists", "knuckles", "knife", "bat",
	"axe", "pistol", "magnum", "smg",
	"shotgun", "sawed_off", "ak47", "m4a1",
	"hunting_rifle", "rpg", "flamethrower", "grenade",
]
const CELL := Vector2i(448, 448)
const COLUMNS := 4

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var out_dir := "D:/geteco/game/artifacts/combat-parity/arsenal-v1/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): out_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = preload("res://characters/Player.gd").new()
	var camera_2d := Camera2D.new()
	camera_2d.name = "Camera"
	player.add_child(camera_2d)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.viewport_3d.size = CELL
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = player.viewport_3d.get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.position = Vector3(2.1, 1.18, -3.0)
	camera.look_at(Vector3(0, 0.9, 0))
	var rows := ceili(float(IDS.size()) / COLUMNS)
	var ready := Image.create(CELL.x * COLUMNS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	var action := Image.create(ready.get_width(), ready.get_height(), false, Image.FORMAT_RGBA8)
	for index in IDS.size():
		var id: String = IDS[index]
		player._cancel_reload()
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		player.combat_pose.weapon_id = ""
		await _settle(player, id, false)
		var image_ready: Image = player.viewport_3d.get_texture().get_image()
		var at := Vector2i((index % COLUMNS) * CELL.x, (index / COLUMNS) * CELL.y)
		ready.blit_rect(image_ready, Rect2i(Vector2i.ZERO, CELL), at)
		image_ready.save_png(out_dir.path_join("%02d_%s_ready.png" % [index + 1, id]))
		player.combat_pose.on_attack(id)
		await _settle(player, id, true)
		var image_action: Image = player.viewport_3d.get_texture().get_image()
		action.blit_rect(image_action, Rect2i(Vector2i.ZERO, CELL), at)
		image_action.save_png(out_dir.path_join("%02d_%s_action.png" % [index + 1, id]))
	var ready_path := out_dir.path_join("arsenal-v1-ready.png")
	var action_path := out_dir.path_join("arsenal-v1-action.png")
	var ready_error := ready.save_png(ready_path)
	var action_error := action.save_png(action_path)
	print("ARSENAL_V1_CAPTURE ready=%s error=%d action=%s error=%d order=%s" % [
		ready_path, ready_error, action_path, action_error, IDS,
	])
	quit(0 if ready_error == OK and action_error == OK else 1)

func _settle(player, _id: String, acting: bool) -> void:
	var frames := 10 if acting else 48
	for frame in frames:
		player.walk_clock = float(frame) * 0.18
		player._update_locomotion(1.0 / 60.0, false, false)
		player.combat_pose.update(player, 1.0 / 60.0, true, false, player._gait_arm_swing())
		await process_frame
	await RenderingServer.frame_post_draw
