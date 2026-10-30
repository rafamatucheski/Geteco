extends SceneTree
## Fotos do impacto de bala por superfície (pedido de 29/10: "parece tudo muito simples em iluminação,
## impacto") numa cena mínima com o ambiente do jogo (céu de cor, Filmic, sol e glow como o
## capture_tracer_fx.gd), de dia e de noite com um poste. Mesmo roteiro antes e depois:
##   GETECO_IMPACT_FX=0 tools/run_godot_locked.sh --path . --script res://tests/capture/capture_impact_fx.gd -- --label=antes
##   tools/run_godot_locked.sh --path . --script res://tests/capture/capture_impact_fx.gd -- --label=depois
## Rodar COM janela. Imagens em evidence/combat-fx-20261029/impact/ (fora do Git). Não mede desempenho.
const OUT := "res://evidence/combat-fx-20261029/impact/"
const EFFECTS := preload("res://gameplay/CombatEffects.gd")

## Contrato de NativeLake/FishingSite (grupo native_water_surface + contains_water).
class Pond extends Node3D:
	func _ready() -> void: add_to_group("native_water_surface")
	func contains_water(point: Vector3) -> bool:
		var local := point - global_position
		return absf(local.x) < 1.6 and absf(local.z) < 1.6

var _label := "antes"
var _fx: Node3D
var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _lamp: OmniLight3D
var _shooter: Node3D
var _world: Node3D
## Superfície: ponto atingido, normal, material, câmera (posição) e alvo do olhar.
var _targets := {
	"metal": {"point": Vector3(-3.0, 0.9, 1.0), "normal": Vector3.BACK, "material": "metal", "eye": Vector3(-2.3, 1.25, 2.6)},
	"concreto": {"point": Vector3(0.0, 0.0, 1.0), "normal": Vector3.UP, "material": "concrete", "eye": Vector3(0.7, 0.9, 2.5)},
	"parede": {"point": Vector3(3.0, 1.1, 0.25), "normal": Vector3.BACK, "material": "concrete", "eye": Vector3(3.6, 1.4, 1.9)},
	"madeira": {"point": Vector3(6.0, 1.0, 0.25), "normal": Vector3.BACK, "material": "wood", "eye": Vector3(6.6, 1.3, 1.9)},
	"vidro": {"point": Vector3(9.0, 1.2, 0.25), "normal": Vector3.BACK, "material": "glass", "eye": Vector3(9.7, 1.4, 1.9)},
	"terra": {"point": Vector3(-3.0, 0.02, 6.0), "normal": Vector3.UP, "material": "dirt", "eye": Vector3(-2.3, 0.9, 7.6)},
	"areia": {"point": Vector3(0.0, 0.02, 6.0), "normal": Vector3.UP, "material": "sand", "eye": Vector3(0.7, 0.9, 7.6)},
	"neve": {"point": Vector3(3.0, 0.02, 6.0), "normal": Vector3.UP, "material": "snow", "eye": Vector3(3.7, 0.9, 7.6)},
	"agua": {"point": Vector3(7.0, -0.35, 6.0), "normal": Vector3.UP, "material": "dirt", "eye": Vector3(7.7, 0.9, 7.8)},
}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("captura do impacto precisa de janela"); quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): _label = argument.trim_prefix("--label=")
	create_timer(240.0).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	seed(29102026)
	_build_scene()
	for i in 30: await process_frame
	print("IMPACT_CAPTURE label=", _label, " impact_fx=", is_instance_valid(_fx.get("_impact_fx")))
	for night in [false, true]:
		_set_time(night)
		for name: String in _targets:
			await _scenario(name, night)
		await _burst(night)
	print("IMPACT_CAPTURE label=", _label, " ok")
	quit(0)

func _build_scene() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
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
	_world.add_child(holder)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -30, 0)
	_sun.light_color = Color("fffdf5")
	_sun.shadow_enabled = true
	_world.add_child(_sun)
	# Poste da noite: a poeira sombreada e as marcas com relevo só aparecem onde há luz.
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.82, 0.55)
	_lamp.omni_range = 14.0
	_lamp.light_energy = 1.6
	_lamp.position = Vector3(3.0, 4.0, 3.5)
	_world.add_child(_lamp)
	# Chão de concreto e os alvos: lataria pintada, parede de concreto, tábuas, vidro, terra, areia, neve e lago.
	_solid(Vector3(0, -0.5, 3), Vector3(40, 1, 20), Color(0.5, 0.49, 0.46), "concrete")
	_solid(Vector3(-3.0, 0.75, 0.0), Vector3(2.2, 1.5, 2.0), Color(0.42, 0.05, 0.05), "metal", 0.6, 0.35)
	_solid(Vector3(3.0, 1.5, 0.0), Vector3(2.2, 3.0, 0.5), Color(0.66, 0.64, 0.6), "concrete")
	_solid(Vector3(6.0, 1.25, 0.0), Vector3(2.2, 2.5, 0.5), Color(0.5, 0.34, 0.2), "wood")
	_solid(Vector3(9.0, 1.5, -0.6), Vector3(2.2, 3.0, 0.3), Color(0.3, 0.32, 0.35), "concrete")
	_glass(Vector3(9.0, 1.3, 0.25), Vector2(1.6, 1.6))
	_solid(Vector3(-3.0, 0.0, 6.0), Vector3(2.6, 0.04, 2.6), Color(0.3, 0.22, 0.14), "dirt")
	_solid(Vector3(0.0, 0.0, 6.0), Vector3(2.6, 0.04, 2.6), Color(0.76, 0.64, 0.44), "sand")
	_solid(Vector3(3.0, 0.0, 6.0), Vector3(2.6, 0.04, 2.6), Color(0.92, 0.94, 0.97), "snow")
	_solid(Vector3(7.0, -0.38, 6.0), Vector3(3.4, 0.06, 3.4), Color(0.25, 0.22, 0.16), "dirt")
	var pond := Pond.new()
	_world.add_child(pond)
	pond.position = Vector3(7.0, 0.0, 6.0)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.2, 3.2)
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.12, 0.25, 0.3, 0.72)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.05
	plane.material = water_material
	water.mesh = plane
	_world.add_child(water)
	water.position = Vector3(7.0, 0.05, 6.0)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_world.add_child(_camera)
	_camera.current = true
	_shooter = Node3D.new()
	_world.add_child(_shooter)
	_fx = EFFECTS.new()
	_world.add_child(_fx)
	_fx.carry_source = _shooter

func _solid(center: Vector3, size: Vector3, color: Color, material: String, metallic := 0.0, roughness := 0.9) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.set_meta("impact_material", material)
	var mesh := BoxMesh.new()
	mesh.size = size
	var look := StandardMaterial3D.new()
	look.albedo_color = color
	look.metallic = metallic
	look.roughness = roughness
	mesh.material = look
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	_world.add_child(body)
	body.position = center

func _glass(center: Vector3, size: Vector2) -> void:
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.7, 0.85, 0.9, 0.25)
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.roughness = 0.05
	look.metallic_specular = 1.0
	quad.material = look
	pane.mesh = quad
	_world.add_child(pane)
	pane.position = center

func _set_time(night: bool) -> void:
	_env.background_color = Color(0.02, 0.03, 0.05) if night else Color("829da6")
	_env.ambient_light_color = Color(0.32, 0.38, 0.5) if night else Color("c0d0e2")
	_env.ambient_light_energy = 0.18 if night else 0.65
	_sun.light_energy = 0.05 if night else 1.6
	_lamp.visible = night
	var amount := 1.0 if night else 0.0
	_env.glow_hdr_threshold = lerpf(2.4, 1.0, amount)
	_env.glow_intensity = lerpf(.25, .85, amount)

## Três tiros perto do mesmo ponto; fotos no clarão, nos estilhaços e depois, com as marcas.
func _scenario(name: String, night: bool) -> void:
	var target: Dictionary = _targets[name]
	_fx.clear()
	var point: Vector3 = target.point
	var normal: Vector3 = target.normal
	_camera.look_at_from_position(target.eye, point + Vector3.UP * 0.12)
	# O "jogador" fica atrás da câmera: é a origem do tiro para o respingo e a referência do LightBudget.
	_shooter.global_position = target.eye + (target.eye - point).normalized() * 1.5 - Vector3.UP * 1.0
	for i in 6: await process_frame
	var side := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := normal.cross(side).normalized()
	for shot in 2:
		_fx.impact(point + side * (0.22 * float(shot) - 0.25) + up * 0.12 * float(shot), normal, str(target.material), 30.0)
		await _wait(0.12)
	_fx.impact(point, normal, str(target.material), 30.0)
	await _photo(name, night, "a_0.03s")
	await _wait(0.2)
	await _photo(name, night, "b_0.25s")
	await _wait(1.3)
	await _photo(name, night, "c_1.5s")

## Rajada de submetralhadora sobre a lataria e o chão ao lado (mistura de metal e concreto).
func _burst(night: bool) -> void:
	_fx.clear()
	_camera.look_at_from_position(Vector3(-1.2, 1.4, 3.6), Vector3(-2.4, 0.6, 0.8))
	_shooter.global_position = Vector3(-0.5, 0.0, 5.5)
	for i in 6: await process_frame
	for shot in 10:
		var on_car := shot % 3 != 2
		var point := Vector3(randf_range(-3.6, -2.4), randf_range(0.35, 1.3), 1.0) if on_car else Vector3(randf_range(-2.0, -1.0), 0.0, randf_range(1.3, 2.0))
		_fx.impact(point, Vector3.BACK if on_car else Vector3.UP, "metal" if on_car else "concrete", 19.0)
		await _wait(0.075)
	await _photo("rajada", night, "a_fim")
	await _wait(1.2)
	await _photo("rajada", night, "c_marcas")

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func _photo(name: String, night: bool, moment: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var file := "%s_%s_%s_%s.png" % [_label, "noite" if night else "dia", name, moment]
	image.save_png(ProjectSettings.globalize_path(OUT + file))
	print("CAPTURE ", file)
