extends SceneTree
## Tira de quadros dos golpes corpo a corpo e das recargas no rig real do Dante,
## com a mesma pose procedural do jogo (`WeaponRigPose` + `Actor`). Cada linha é
## uma ação; cada coluna, um instante. Serve para julgar antecipação, impacto e
## recuperação a olho — o teste de continuidade só mede velocidade angular.
##
## Uso (precisa de renderização real; em headless a imagem sai vazia):
##   Godot --path . --script res://tests/capture/capture_melee_filmstrip.gd -- mode=melee
##   Godot --path . --script res://tests/capture/capture_melee_filmstrip.gd -- mode=reload
## Saída: evidence/combat/filmstrip/<mode>.png (fica fora do Git).

const CELL := Vector2i(220, 300)
const ACTOR = preload("res://scripts/Actor.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")
## [arma, golpes antes do capturado (sequência de combo), rótulo]
const MELEE_ROWS := [
	["fists", 0], ["fists", 1], ["fists", 2], ["fists", 3],
	["knuckles", 0], ["knuckles", 1], ["knuckles", 2], ["knuckles", 3],
	["bat", 0], ["bat", 1], ["bat", 2],
	["axe", 0], ["axe", 1], ["axe", 2],
]
const RELOAD_ROWS := ["pistol", "magnum", "smg", "ak47", "shotgun", "hunting_rifle", "rpg"]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var mode := "melee"
	var out_dir := "res://evidence/combat/filmstrip/"
	var columns := 14
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
		if arg.begins_with("out_dir="): out_dir = arg.trim_prefix("out_dir=").path_join("")
		if arg.begins_with("columns="): columns = int(arg.trim_prefix("columns="))
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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.75
	# Perfil pela direita, um pouco à frente e acima: golpes para a frente se leem
	# como deslocamento lateral na imagem (de frente, vinham na direção da câmera).
	var angle := "side"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("view="): angle = arg.trim_prefix("view=")
	camera.position = Vector3(3.0, 1.9, -1.4) if angle == "side" else Vector3(1.6, 2.4, -3.0)
	view.add_child(camera)
	camera.look_at(Vector3(0, 1.05, -0.35))
	var rows: Array = MELEE_ROWS if mode == "melee" else RELOAD_ROWS
	var sheet := Image.create(CELL.x * columns, CELL.y * rows.size(), false, Image.FORMAT_RGBA8)
	for row in rows.size():
		var id: String = rows[row][0] if mode == "melee" else rows[row]
		var actor = ACTOR.new()
		actor.is_player = true
		view.add_child(actor)
		actor.set_physics_process(false)
		await process_frame
		var gun := Node3D.new()
		view.add_child(gun)
		if id != "fists": ARSENAL.build(gun, id)
		var pose = POSE.new()
		# Prontidão estável antes da ação.
		for frame in 40: _step(actor, pose, gun, id, false, 0.0)
		var duration := 0.90
		if mode == "melee":
			# Golpes anteriores da sequência, cada um disparado no tempo de encadeamento.
			for previous in int(rows[row][1]):
				pose.attack(id)
				for frame in int(ceil(_chain(pose, id) * 60.0)): _step(actor, pose, gun, id, false, 0.0)
			pose.attack(id)
			print("FILMSTRIP row=%d %s combo_step=%d" % [row, id, pose.combo_step])
		else:
			duration = 1.6
		var total := int(round(duration * 60.0))
		var captured := 0
		for frame in total + 1:
			var progress := float(frame) / float(total)
			_step(actor, pose, gun, id, mode == "reload", progress)
			if captured < columns and frame >= int(round(float(captured) * float(total) / float(columns - 1))):
				await RenderingServer.frame_post_draw
				var image: Image = view.get_texture().get_image()
				image.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(captured * CELL.x, row * CELL.y))
				captured += 1
		actor.queue_free()
		gun.queue_free()
		await process_frame
	var path := out_dir.path_join(mode + ".png")
	var error := sheet.save_png(path)
	print("FILMSTRIP mode=%s path=%s error=%d" % [mode, ProjectSettings.globalize_path(path), error])
	quit(0 if error == OK else 1)

func _step(actor, pose, gun: Node3D, id: String, reloading: bool, progress: float) -> void:
	actor._pose_locomotion(Vector3.ZERO, 3.5, Vector3.ZERO, 1.0 / 60.0)
	var result: Dictionary = pose.update(id, 1.0 / 60.0, true, reloading, progress, false, false, actor.phase)
	actor.combat_facing = 0.0
	actor.set_combat_weapon_pose(id, result)
	actor._apply_combat_weapon_pose()
	gun.visible = bool(result.visible)
	if id != "fists": gun.global_transform = actor.combat_weapon_transform(DATA.GRIPS.get(id, Vector3.ZERO))

## Próximo golpe da sequência no primeiro instante que o jogo aceita: a cadência
## da arma (`fire_interval`), como quem segura o botão.
func _chain(_pose, id: String) -> float:
	return float(preload("res://gameplay/WeaponCatalog.gd").WEAPONS[id].fire_interval)
