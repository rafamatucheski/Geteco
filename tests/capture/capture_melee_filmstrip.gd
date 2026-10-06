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

const CELL_DEFAULT := Vector2i(220, 300)
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
	# cell=LxA: células maiores para conferir o rig inteiro; only=arma: só as linhas dela.
	var CELL := CELL_DEFAULT
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cell="):
			var size := arg.trim_prefix("cell=").split("x")
			CELL = Vector2i(int(size[0]), int(size[1]))
		if arg.begins_with("only="): only = arg.trim_prefix("only=")
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
	# zoom=hands: câmera fechada nas palmas, seguindo as mãos quadro a quadro
	# (para julgar punho, pegada no cabo e o cabo passando pela cabeça).
	var hands := false
	var duration_override := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("view="): angle = arg.trim_prefix("view=")
		if arg == "zoom=hands": hands = true
		if arg.begins_with("duration="): duration_override = float(arg.trim_prefix("duration="))
	var view_offset := Vector3(3.0, 0.85, -1.05) if angle == "side" else Vector3(1.6, 1.35, -2.65)
	# left: perfil pelo lado esquerdo (braço de apoio); back: por trás, acima do ombro.
	if angle == "left": view_offset = Vector3(-3.0, 0.85, -1.05)
	if angle == "back": view_offset = Vector3(-1.2, 1.6, 2.6)
	camera.position = Vector3(0, 1.05, -0.35) + view_offset
	view.add_child(camera)
	camera.look_at(Vector3(0, 1.05, -0.35))
	if hands: camera.size = 0.6
	var rows: Array = MELEE_ROWS if mode == "melee" else RELOAD_ROWS
	if only != "": rows = rows.filter(func(entry): return (entry[0] if entry is Array else entry) == only)
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
		if duration_override > 0.0: duration = duration_override
		var total := int(round(duration * 60.0))
		var captured := 0
		for frame in total + 1:
			var progress := float(frame) / float(total)
			_step(actor, pose, gun, id, mode == "reload", progress)
			if captured < columns and frame >= int(round(float(captured) * float(total) / float(columns - 1))):
				if hands:
					var focus: Vector3 = (actor.combat_palm_position("Right") + actor.combat_palm_position("Left")) * 0.5
					camera.position = focus + view_offset.normalized() * 3.0
					camera.look_at(focus)
				await RenderingServer.frame_post_draw
				var image: Image = view.get_texture().get_image()
				image.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(captured * CELL.x, row * CELL.y))
				captured += 1
		actor.queue_free()
		gun.queue_free()
		await process_frame
	var path := out_dir.path_join(mode + ("_" + only if only != "" else "") + ("_" + angle if angle != "side" else "") + ".png")
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
