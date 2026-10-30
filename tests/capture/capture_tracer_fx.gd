extends SceneTree
## Fotos do traçado da bala (pedido de 29/10: "parece tudo muito simples") numa cena mínima com o
## ambiente do jogo (céu de cor, Filmic, sol de ProductionWorld e glow de CityLook de dia e de noite).
## Mesmo roteiro antes e depois: pistola, submetralhadora, fuzil, escopeta, fuzil de caça, polícia
## vindo na direção da câmera (passa a ~0,6 m) e um tiroteio misturado. Rodar COM janela:
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_tracer_fx.gd -- --label=antes
## Imagens em evidence/combat-fx-20261029/tracer/ (fora do Git). Não mede desempenho.
const OUT := "res://evidence/combat-fx-20261029/tracer/"
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const MUZZLE := Vector3(0.28, 1.38, -0.45)

## Dono do CombatEffects no jogo é o Gameplay; aqui só a arma em mão importa.
class Host extends Node3D:
	var weapon_id := "pistol"
	func equipped() -> String: return weapon_id

var _label := "antes"
var _host: Host
var _fx: Node3D
var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
var _police: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("captura do traçado precisa de janela"); quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): _label = argument.trim_prefix("--label=")
	create_timer(120.0).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	_build_scene()
	for i in 20: await process_frame
	for night in [false, true]:
		_set_time(night)
		await _scenario("pistola", night, func(): await _fire("pistol", 1, 0.0), 0.16)
		await _scenario("submetralhadora", night, func(): await _fire("smg", 5, 0.11), 0.05)
		await _scenario("fuzil", night, func(): await _fire("ak47", 4, 0.15), 0.07)
		await _scenario("escopeta", night, func(): await _fire("shotgun", 1, 0.0), 0.10)
		await _scenario("fuzil_caca", night, func(): await _fire("hunting_rifle", 1, 0.0), 0.12)
		await _scenario("policia_rente", night, func(): _incoming(3), 0.0, true)
		await _scenario("tiroteio", night, _firefight, 0.06, true)
	print("TRACER_CAPTURE label=", _label, " ok")
	quit(0)

func _firefight() -> void:
	_incoming(4)
	await _fire("m4a1", 3, 0.12)
	await _fire("shotgun", 1, 0.0)

func _build_scene() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var holder := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.glow_hdr_scale = 2.0
	_env.glow_bloom = 0.0
	_env.set_glow_level(0, 0.0)
	_env.set_glow_level(1, 1.0)
	_env.set_glow_level(2, 1.0)
	_env.set_glow_level(3, .6)
	_env.set_glow_level(4, .3)
	holder.environment = _env
	world.add_child(holder)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -30, 0)
	_sun.light_color = Color("fffdf5")
	_sun.shadow_enabled = true
	world.add_child(_sun)
	# Chão de concreto claro e paredes laterais: o pior caso do dia é traçado contra fundo claro.
	_box(world, Vector3(0, -0.05, -40), Vector3(60, 0.1, 100), Color(0.52, 0.51, 0.48))
	_box(world, Vector3(-7, 2.5, -30), Vector3(1, 5, 50), Color(0.62, 0.58, 0.52))
	_box(world, Vector3(8, 3.5, -30), Vector3(1, 7, 50), Color(0.35, 0.37, 0.40))
	_box(world, Vector3(0, 4, -62), Vector3(30, 8, 1), Color(0.70, 0.68, 0.64))
	for index in 4:
		_box(world, Vector3(-3.5 + index * 2.6, 0.6, -18 - index * 7), Vector3(1.4, 1.2, 0.6), Color(0.25, 0.27, 0.3))
	_camera = Camera3D.new()
	_camera.fov = 70.0
	world.add_child(_camera)
	_camera.look_at_from_position(Vector3(-0.45, 1.85, 2.6), Vector3(0.6, 1.25, -14.0))
	_camera.current = true
	_host = Host.new()
	world.add_child(_host)
	# `--effects-source=<arquivo>`: CombatEffects congelado antes da mudança (cópia do arquivo de trabalho),
	# compilado aqui. Assim o "antes" sai do mesmo código de antes sem trocar o arquivo do projeto.
	var effects_script: GDScript = EFFECTS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--effects-source="):
			effects_script = GDScript.new()
			effects_script.source_code = FileAccess.get_file_as_string(argument.trim_prefix("--effects-source="))
			if effects_script.reload() != OK: push_error("fonte do CombatEffects não compilou"); quit(4); return
	_fx = effects_script.new()
	_host.add_child(_fx)

func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	node.position = center

func _set_time(night: bool) -> void:
	_env.background_color = Color(0.02, 0.03, 0.05) if night else Color("829da6")
	_env.ambient_light_color = Color(0.32, 0.38, 0.5) if night else Color("c0d0e2")
	_env.ambient_light_energy = 0.18 if night else 0.65
	_sun.light_energy = 0.05 if night else 1.6
	var amount := 1.0 if night else 0.0
	_env.glow_hdr_threshold = lerpf(2.4, 1.0, amount)
	_env.glow_intensity = lerpf(.25, .85, amount)

func _scenario(name: String, night: bool, action: Callable, settle: float, police := false) -> void:
	# Espera os traçados anteriores acabarem em vez de `clear()`: o clear() do CombatEffects reinicia
	# os emissores (restart) e soltava poeira, vidro e fumaça na origem, dentro da foto.
	_police.clear()
	_rng.seed = hash(name)
	for i in int(1.8 * Engine.physics_ticks_per_second): await physics_frame
	await action.call()
	var waited := 0.0
	while waited < settle or (police and not _police.is_empty() and not _near_camera()):
		await physics_frame
		_advance_police(1.0 / Engine.physics_ticks_per_second)
		waited += 1.0 / Engine.physics_ticks_per_second
		if waited > 2.0: break
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var file := "%s_%s_%s.png" % [_label, "noite" if night else "dia", name]
	image.save_png(ProjectSettings.globalize_path(OUT + file))
	# Recorte 2× do primeiro terço da trajetória, onde a cabeça do traçado costuma estar.
	var crop := image.get_region(Rect2i(Vector2i(420, 200), Vector2i(560, 315)))
	crop.resize(1120, 630, Image.INTERPOLATE_LANCZOS)
	crop.save_png(ProjectSettings.globalize_path(OUT + file.replace(".png", "_zoom.png")))
	print("CAPTURE ", file)

## Tiro do jogador como o Gameplay chama: velocidade do catálogo / 16, cor e dano por chumbo.
func _fire(id: String, shots: int, interval: float) -> void:
	_host.weapon_id = id
	var data: Dictionary = CATALOG.WEAPONS[id]
	for shot in shots:
		for pellet in int(data.get("pellets", 1)):
			var spread := float(data.get("spread", 0.0)) * 0.6
			var direction := Vector3(0.05 + _rng.randf_range(-spread, spread), -0.012 + _rng.randf_range(-spread, spread) * 0.4, -1.0).normalized()
			_fx.tracer(MUZZLE, MUZZLE + direction * 58.0, float(data.projectile_speed) / 16.0, data.tracer_color, float(data.damage))
		if shot < shots - 1:
			var elapsed := 0.0
			while elapsed < interval:
				await physics_frame
				_advance_police(1.0 / Engine.physics_ticks_per_second)
				elapsed += 1.0 / Engine.physics_ticks_per_second

## Balas da polícia vindo do fundo em direção à câmera, passando rente (o "zunido").
func _incoming(count: int) -> void:
	for index in count:
		var origin := Vector3(-4.5 + index * 2.2, 1.45, -34.0 - index * 3.0)
		var pass_by := _camera.global_position + Vector3(0.55 - index * 0.35, -0.25, 0.4)
		var direction := origin.direction_to(pass_by)
		var token: Dictionary = _fx.police_tracer(origin, direction, 45.0)
		_police.append({"token": token, "point": origin, "direction": direction, "speed": 45.0, "left": origin.distance_to(pass_by) + 6.0})

func _advance_police(delta: float) -> void:
	for index in range(_police.size() - 1, -1, -1):
		var round_data: Dictionary = _police[index]
		var step := float(round_data.speed) * delta
		round_data.point = (round_data.point as Vector3) + (round_data.direction as Vector3) * step
		round_data.left = float(round_data.left) - step
		var finished := float(round_data.left) <= 0.0
		_fx.move_police_tracer(round_data.token, round_data.point, finished)
		if finished: _police.remove_at(index)

func _near_camera() -> bool:
	for round_data in _police:
		if (round_data.point as Vector3).distance_to(_camera.global_position) < 3.2: return true
	return false
