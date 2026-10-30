extends SceneTree
## Fotos do tiro saindo da arma (pedido de 29/10: "parece tudo muito simples em iluminação, impacto,
## tudo") numa cena mínima com o ambiente do jogo (céu de cor, Filmic, sol e glow de CityLook de dia e
## de noite). O anfitrião imita só o que o Gameplay faz no disparo (`_flash_muzzle`: clarão de 6 raios
## com escala e duração por arma, luz do cano, `effects.muzzle_smoke` e `effects.weapon_shot`); a
## polícia imita `police_shoot` (esfera do PoliceModel + `muzzle_smoke`). Mesmo roteiro antes e depois.
## Duas câmeras: a do jogo (ortográfica a 45°, tamanho do V1 a pé) com recorte 3× no atirador, e uma
## perspectiva de perto. Rodar COM janela:
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_muzzle_fx.gd -- --label=antes
## A/B no mesmo código: GETECO_MUZZLE_FX=0 volta ao clarão antigo.
## Imagens em evidence/combat-fx-20261029/muzzle/ (fora do Git). Não mede desempenho.
const OUT := "res://evidence/combat-fx-20261029/muzzle/"
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
## Tamanho vertical da câmera a pé no jogo (CameraRig: 720 px / (16 px/m × zoom 2,072)).
const GAME_CAMERA_SIZE := 21.7
const HAND := Vector3(0.0, 1.25, 0.0)

## O mínimo do Gameplay que o disparo do jogador usa: arma na mão, clarão e luz presos no cano.
class Host extends Node3D:
	const HEAVY := ["magnum", "shotgun", "sawed_off", "rpg"]
	var weapon_id := "pistol"
	var player: Node3D
	var gun: Node3D
	var effects: Node3D
	var _muzzle_flash: MeshInstance3D
	var _muzzle_light: OmniLight3D
	var _muzzle_material: StandardMaterial3D
	var _muzzle_timer := 0.0
	func equipped() -> String: return weapon_id
	func attack_allowed() -> bool: return true
	func _ready() -> void:
		player = Node3D.new()
		add_child(player)
		gun = Node3D.new()
		add_child(gun)
		# Cópia do material de `Gameplay._muzzle_material`.
		_muzzle_material = StandardMaterial3D.new()
		_muzzle_material.albedo_color = Color(1.0, 0.85, 0.2)
		_muzzle_material.emission_enabled = true
		_muzzle_material.emission = Color(1.0, 0.6, 0.1)
		_muzzle_material.emission_energy_multiplier = 4.5
		_muzzle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	func equip(id: String, aim: Vector3) -> void:
		weapon_id = id
		for child in gun.get_children():
			gun.remove_child(child)
			child.free()
		gun.global_transform = Transform3D(Basis.looking_at(aim, Vector3.UP), HAND)
		var tip := ARSENAL.build_cached(gun, id)
		# Cópia de `Gameplay._build_muzzle_flash` (sem acessórios).
		_muzzle_flash = MeshInstance3D.new()
		_muzzle_flash.mesh = _flash_mesh()
		_muzzle_flash.material_override = _muzzle_material
		_muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle_flash.position = tip
		_muzzle_flash.visible = false
		gun.add_child(_muzzle_flash)
		_muzzle_light = OmniLight3D.new()
		_muzzle_light.light_color = Color(1.0, 0.7, 0.2)
		_muzzle_light.light_energy = 2.8
		_muzzle_light.omni_range = 2.5
		_muzzle_light.shadow_enabled = false
		_muzzle_light.position = tip
		_muzzle_light.visible = false
		gun.add_child(_muzzle_light)
	## Cópia de `Gameplay._directional_flash_mesh`.
	func _flash_mesh() -> ArrayMesh:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ray in 6:
			var angle := TAU * float(ray) / 6.0
			var tangent := Vector3(cos(angle), sin(angle), 0.0)
			var side := Vector3(-sin(angle), cos(angle), 0.0)
			var root := tangent * 0.018
			var width := 0.032 if ray % 2 == 0 else 0.022
			var length := 0.26 if ray % 2 == 0 else 0.17
			var point := tangent * (0.035 if ray % 2 == 0 else 0.022) + Vector3(0, 0, -length)
			for vertex in [root - side * width, point, root + side * width]: surface.add_vertex(vertex)
			for vertex in [Vector3.ZERO, root + side * width, point]: surface.add_vertex(vertex)
		return surface.commit()
	## Cópia de `Gameplay._flash_muzzle` + a chamada de `weapon_shot` de `_stall_fire_at`.
	func shoot() -> void:
		var id := weapon_id
		var heavy := id in HEAVY or id == "shotgun_auto"
		var suppressed := bool(CATALOG.WEAPONS.get(id, {}).get("suppressed", false))
		var scale_value := Vector3.ONE * (1.0 if heavy else 0.62)
		if id == "smg_compact": scale_value *= 0.80
		elif id == "smg_tactical": scale_value *= 0.92
		elif id == "shotgun_auto": scale_value *= 0.85
		if suppressed: scale_value *= 0.22
		_muzzle_flash.scale = scale_value
		_muzzle_flash.visible = true
		_muzzle_light.visible = not suppressed
		_muzzle_timer = 0.065 if heavy else 0.035
		var aim := -gun.global_basis.z
		effects.muzzle_smoke(_muzzle_flash.global_position, aim)
		effects.weapon_shot(id, gun.to_global(Vector3(0.025, 0.05, -0.025)), Vector3(aim.x, 0.0, aim.z).normalized(), 5)
	func _physics_process(delta: float) -> void:
		if is_instance_valid(effects): effects.update_weapon_feedback(self, delta)
		if _muzzle_timer > 0.0:
			_muzzle_timer -= delta
			if _muzzle_timer <= 0.0:
				_muzzle_flash.hide()
				_muzzle_light.hide()
	var reload_timer := 0.0
	var _reload_total := 1.0
	var state := AmmoState.new()

class AmmoState extends RefCounted:
	func get_ammo(_id: String) -> Dictionary: return {"magazine": 5, "reserve": 30}

## Atirador NPC como `Gameplay.police_shoot`: esfera do PoliceModel no cano e `muzzle_smoke`.
class Shooter extends Node3D:
	var flash: MeshInstance3D
	var flash_time := 0.0
	func _ready() -> void:
		flash = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		flash.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.85, 0.2)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.6, 0.1)
		material.emission_energy_multiplier = 4.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash.material_override = material
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		add_child(flash)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.24
		capsule.height = 1.75
		body.mesh = capsule
		body.position = Vector3(0, 0.88, 0)
		add_child(body)
	func shoot(effects: Node3D, target: Vector3) -> void:
		var muzzle := global_position + Vector3.UP * 1.3 + global_position.direction_to(target) * 0.45
		flash.global_position = muzzle
		var direction := muzzle.direction_to(target + Vector3.UP)
		effects.muzzle_smoke(muzzle, direction)
		flash.show()
		flash_time = 0.05
	func _physics_process(delta: float) -> void:
		flash_time = maxf(0.0, flash_time - delta)
		flash.visible = flash_time > 0.0

var _label := "antes"
var _host: Host
var _fx: Node3D
var _camera: Camera3D
var _close: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _shooters: Array[Shooter] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("captura do cano precisa de janela"); quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): _label = argument.trim_prefix("--label=")
	create_timer(300.0).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	_build_scene()
	for i in 20: await process_frame
	for night in [false, true]:
		_set_time(night)
		for view in ["jogo", "perto"]:
			_use_view(view)
			await _scenario("pistola", night, view, "pistol", 1, 0.0)
			await _scenario("submetralhadora", night, view, "smg", 5, 0.09)
			await _scenario("fuzil", night, view, "ak47", 3, 0.12)
			await _scenario("escopeta", night, view, "shotgun", 1, 0.0)
			await _scenario("magnum", night, view, "magnum", 1, 0.0)
		_use_view("jogo")
		await _scenario("tiroteio", night, "jogo", "m4a1", 4, 0.1, true)
	print("MUZZLE_CAPTURE label=", _label, " fx=", OS.get_environment("GETECO_MUZZLE_FX"), " ok")
	quit(0)

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
	# Calçada de concreto, parede atrás do atirador e caixotes: onde a luz do cano tem que aparecer.
	_box(world, Vector3(0, -0.05, 0), Vector3(60, 0.1, 60), Color(0.46, 0.45, 0.42))
	_box(world, Vector3(0, 2.0, -2.6), Vector3(14, 4, 0.4), Color(0.58, 0.55, 0.50))
	_box(world, Vector3(2.4, 0.45, -1.2), Vector3(0.9, 0.9, 0.9), Color(0.36, 0.28, 0.2))
	_box(world, Vector3(-1.8, 0.35, 0.9), Vector3(0.7, 0.7, 0.7), Color(0.30, 0.32, 0.35))
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = GAME_CAMERA_SIZE
	_camera.far = 200.0
	world.add_child(_camera)
	_camera.look_at_from_position(HAND + Vector3(0, 25.3, 25.3), HAND)
	_close = Camera3D.new()
	_close.fov = 55.0
	world.add_child(_close)
	_close.look_at_from_position(HAND + Vector3(0.9, 0.55, 2.4), HAND + Vector3(0.7, -0.1, 0.0))
	_host = Host.new()
	world.add_child(_host)
	_fx = EFFECTS.new()
	_host.add_child(_fx)
	_host.effects = _fx
	for index in 6:
		var shooter := Shooter.new()
		world.add_child(shooter)
		var angle := lerpf(-0.9, 0.9, float(index) / 5.0)
		shooter.global_position = Vector3(sin(angle) * 6.5 + 1.5, 0.0, -cos(angle) * 4.0 + 4.5)
		shooter.visible = false
		_shooters.append(shooter)

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

func _use_view(view: String) -> void:
	(_camera if view == "jogo" else _close).current = true

func _set_time(night: bool) -> void:
	_env.background_color = Color(0.02, 0.03, 0.05) if night else Color("829da6")
	_env.ambient_light_color = Color(0.32, 0.38, 0.5) if night else Color("c0d0e2")
	_env.ambient_light_energy = 0.18 if night else 0.65
	_sun.light_energy = 0.05 if night else 1.6
	var amount := 1.0 if night else 0.0
	_env.glow_hdr_threshold = lerpf(2.4, 1.0, amount)
	_env.glow_intensity = lerpf(.25, .85, amount)

func _scenario(name: String, night: bool, view: String, id: String, shots: int, interval: float, crowd := false) -> void:
	# Sem `_fx.clear()`: no Godot 4.7 o `restart()` de CPUParticles3D emite na hora, e o clear do
	# CombatEffects dispara todos os emissores (explosão, chama, sangue) onde estavam. Espera assentar.
	await create_timer(1.9).timeout
	seed(hash(name + view))
	for shooter in _shooters: shooter.visible = crowd
	# Arma apontando para a direita da tela, um pouco para a câmera: o perfil que a câmera do jogo vê.
	_host.equip(id, Vector3(1.0, 0.0, 0.35).normalized())
	for i in 6: await physics_frame
	for shot in shots:
		await physics_frame
		_host.shoot()
		if crowd:
			for index in _shooters.size():
				if (shot + index) % 2 == 0: _shooters[index].shoot(_fx, HAND)
		if shot < shots - 1:
			var elapsed := 0.0
			while elapsed < interval:
				await physics_frame
				elapsed += 1.0 / Engine.physics_ticks_per_second
	var stem := "%s_%s_%s_%s" % [_label, "noite" if night else "dia", view, name]
	await _save(stem + "_t0")
	await create_timer(0.22).timeout
	await _save(stem + "_t220ms")
	if view == "jogo" and not crowd:
		await create_timer(0.6).timeout
		await _save(stem + "_t820ms")

func _save(file_stem: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if _camera.current:
		# Recorte 3× em volta do atirador (no jogo a arma ocupa poucos pixels).
		var center := _camera.unproject_position(HAND + Vector3(0.5, 0.0, 0.0))
		var size := Vector2i(427, 240) if not file_stem.contains("tiroteio") else Vector2i(640, 360)
		var rect := Rect2i(Vector2i(center) - size / 2, size).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var crop := image.get_region(rect)
		crop.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		crop.save_png(ProjectSettings.globalize_path(OUT + file_stem + "_zoom.png"))
	else:
		image.save_png(ProjectSettings.globalize_path(OUT + file_stem + ".png"))
	print("CAPTURE ", file_stem)
