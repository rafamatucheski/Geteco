extends RefCounted
## Efeitos de rua que só nascem no jogo, desenhados sob a cortina (22/10, 3ª rodada de desempenho).
##
## A sonda de pipelines (GETECO_PIPELINE_PROBE=1) no estresse com cache frio viu, com a partida jogável:
## estouro de vidro (CPUParticles3D com a lasca e o vidro alfa: quadro de 48 ms), gêiser de hidrante
## (WaterJet3D: gotas em billboard de partícula e a poça em cilindro, 132 ms) e poça de sangue (12 ms a
## quente). O VehicleMaterialVariantPrewarm desenhava esses materiais numa caixa comum: o shader ficava
## pronto, mas a partícula (multimesh com cor e dado custom) e a malha do sangue são outros pipelines.
## Aqui cada efeito é montado com as mesmas peças do jogo (malhas e materiais compartilhados da
## StreetPhysics, do GroundBlood3D e do WaterJet3D), alguns quadros diante da câmera, e liberado antes de a
## cortina sair. Sem física, som, dano ou RNG do jogo. GETECO_STREET_FX_PREWARM=0 desliga.
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const JET := preload("res://gameplay/fx/WaterJet3D.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 30
const DISTANCE := 8.0
static var _drawn := false

static func enabled() -> bool:
	return OS.get_environment("GETECO_STREET_FX_PREWARM") != "0"

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not enabled() or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var tree := host.get_tree()
	var visual := Node3D.new()
	visual.name = "StreetEffectsPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	host.add_child(visual)
	visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * DISTANCE)
	# Estouro de vidro: mesmas opções visuais de StreetPhysics._stall_spawn_glass, emitindo sem parar.
	var burst := CPUParticles3D.new()
	burst.amount = 26
	burst.lifetime = .9
	burst.mesh = STREET.glass_shard_mesh()
	burst.material_override = STREET.glass_shard_material()
	burst.direction = Vector3.UP
	burst.spread = 55.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 5.0
	burst.gravity = Vector3(0, -12, 0)
	burst.preprocess = .2
	burst.position = Vector3(-1.5, 0, 0)
	visual.add_child(burst)
	burst.emitting = true
	# Gêiser: o WaterJet3D do jogo (gotas, névoa, respingo) e a poça de StreetPhysics.spawn_geyser.
	var jet: Node3D = JET.new()
	jet.flight_time = 1.0
	visual.add_child(jet)
	jet.aim(visual.global_position + Vector3.UP * .3, visual.global_position + camera.global_basis.x * 1.2)
	jet.set_active(true)
	var puddle := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = .005
	disc.radial_segments = 18
	puddle.mesh = disc
	puddle.material_override = STREET.puddle_material()
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.position = Vector3(1.5, -.8, 0)
	puddle.rotation.x = PI * .5
	visual.add_child(puddle)
	# Poça de sangue: malha e material-modelo do GroundBlood3D da sessão (o material de cada mancha tem as
	# mesmas flags do modelo).
	var street: Node = host.get_node_or_null("StreetPhysics")
	var blood: Node = street.get_node_or_null("GroundBlood3D") if street != null else null
	if blood != null and blood.get("_meshes") is Array and not (blood.get("_meshes") as Array).is_empty() and blood.get("_shader_template") != null:
		var stain := MeshInstance3D.new()
		stain.mesh = (blood.get("_meshes") as Array)[0]
		stain.material_override = blood.get("_shader_template")
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stain.position = Vector3(0, -.6, 0)
		stain.rotation.x = PI * .5
		visual.add_child(stain)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(visual, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual): break
		if draws[0] >= DRAW_FRAMES:
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
