extends Node
## Controlador do visual urbano em tempo de jogo.
##
## - Converte a hora do Weather em um fator de noite e repassa aos materiais
##   compartilhados (janelas, postes, manchas de luz, neon).
## - Liga o glow do Environment para as luzes "estourarem" à noite.
## - Mantém a silhueta de oclusão no Dante e no carro que ele dirige.
##
## Não mexe em cor de sol/ambiente/céu: isso continua com Weather e
## RegionalAtmosphere3D. Aqui entra apenas o que eles não cobrem.

const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const ATMOSPHERE := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
const SILHOUETTE_SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")

const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var controller
## Um material por alvo. Quem dirige compartilha a caixa do conjunto
## piloto/veículo para não confundir a própria carroceria com um prédio.
var _silhouettes := {}
var _silhouette_targets: Array = []
var _silhouette_reference: Node3D
var _silhouette_player_id := 0
var _silhouette_vehicle_id := 0
var _silhouette_transition_id := 0
var _silhouette_player_visible := false
var _silhouette_inside := false
var _clock := 0.0
var _last_night := -1.0
var _pools_visible := false
var _grade: GradientTexture1D
var _blink := 0.0
var _blink_on := false
var _beacon_on := false
var _strobe_on := false
var _tv_clock := 0.0
var _tv_rng := RandomNumberGenerator.new()
var _neon_night := -1.0


func _ready() -> void:
	name = "CityLook"
	# Depois do Weather/atmosfera no quadro: a direção do sol é ajustada aqui.
	process_priority = 100
	var local_lighting := preload("res://world/city_look/CityLocalLighting.gd").new()
	local_lighting.controller = controller
	add_child(local_lighting)
	_update(true)


func _process(delta: float) -> void:
	_blink += delta
	var phase := fposmod(_blink, 1.1) < .6
	if phase != _blink_on:
		_blink_on = phase
		MATERIALS.set_signal_phase(phase)
	# O controlador só percorre as lentes quando alguma fase muda ou há registro.
	# A verificação por quadro evita atraso visual em relação aos motoristas.
	JUNCTIONS.update_lenses()
	# Giroflex da delegacia: alterna 3x por segundo, mais nervoso que o semáforo.
	var strobe := fposmod(_blink, .34) < .17
	if strobe != _strobe_on:
		_strobe_on = strobe
		MATERIALS.set_police_phase(strobe)
	# Balizamento de prédio alto: lampejo curto a cada 1,5 s.
	var beacon := fposmod(_blink, 1.5) < .28
	if beacon != _beacon_on:
		_beacon_on = beacon
		MATERIALS.set_beacon_phase(beacon)
	# TV nas janelas: troca de cena a cada 80–250 ms, como TV de verdade.
	_tv_clock -= delta
	if _tv_clock <= 0.0:
		_tv_clock = _tv_rng.randf_range(.08, .25)
		MATERIALS.flicker_tv(_tv_rng)
	_follow_silhouettes()
	_orient_sun()
	_clock += delta
	# A hora anda devagar (um dia = 10 min); 4 Hz é mais que suficiente.
	if _clock < .25: return
	_clock = 0.0
	_update(false)


func _update(force: bool) -> void:
	if controller == null: return
	var night := _night_factor()
	if force or absf(night - _last_night) > .004:
		_last_night = night
		MATERIALS.set_night(night)
		_update_neon_labels(night)
		var visible := night > .01
		if force or visible != _pools_visible:
			_pools_visible = visible
			get_tree().call_group(DRESSING.NIGHT_GROUP, "set", "visible", visible)
	_apply_glow(night)
	_apply_grade()
	_refresh_silhouette()


func _night_factor() -> float:
	var session = controller.get("session")
	if session == null or not is_instance_valid(session.get("weather")): return 0.0
	var inside: bool = not String(controller.state.place_id).is_empty()
	if inside: return 0.0
	var daylight: float = ATMOSPHERE.daylight_at(float(session.weather.time_of_day))
	# Postes acendem no fim da tarde, antes do escuro total, como na rua real.
	return 1.0 - smoothstep(.18, .62, daylight)


func _apply_glow(night: float) -> void:
	var holder = controller.get("environment")
	if holder == null or not is_instance_valid(holder): return
	var env: Environment = holder.environment
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# De dia, pintura branca ao sol passa de 1.0 e ganhava halo; o limiar sobe
	# de dia e desce à noite, quando só as luzes passam dele.
	env.glow_hdr_threshold = lerpf(2.4, 1.0, night)
	env.glow_hdr_scale = 2.0
	env.glow_intensity = lerpf(.25, .85, night)
	env.glow_bloom = 0.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, .6)
	env.set_glow_level(4, .3)


## LUT 1D de assinatura de Harbor: preto levemente azul-petróleo, meios-tons
## neutros e altas luzes puxadas para o creme, com curva S suave. É o "filme"
## de cidade de jogo sem mexer na paleta autorada da V1 (que continua em
## RegionalAtmosphere3D via saturação/contraste).
func _apply_grade() -> void:
	var holder = controller.get("environment")
	if holder == null or not is_instance_valid(holder): return
	if _grade == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.8, 1.0])
		gradient.colors = PackedColorArray([
			Color(0.015, 0.03, 0.05), Color(0.15, 0.17, 0.2), Color(0.5, 0.5, 0.49),
			Color(0.83, 0.82, 0.79), Color(1.0, 0.98, 0.95)])
		_grade = GradientTexture1D.new()
		_grade.gradient = gradient
		_grade.width = 256
	var env: Environment = holder.environment
	if env.adjustment_color_correction != _grade: env.adjustment_color_correction = _grade


func _refresh_silhouette() -> void:
	if controller == null: return
	var world = controller.get("world")
	if not is_instance_valid(world): return
	var player: Node3D = world.get("player")
	var vehicle := _silhouette_vehicle(world)
	_silhouette_inside = _uses_interior_depth()
	_silhouette_player_id = player.get_instance_id() if is_instance_valid(player) else 0
	_silhouette_vehicle_id = vehicle.get_instance_id() if is_instance_valid(vehicle) else 0
	_silhouette_transition_id = _silhouette_transition(world)
	_silhouette_player_visible = is_instance_valid(player) and player.is_visible_in_tree()
	_silhouette_reference = vehicle if is_instance_valid(vehicle) else player
	var targets: Array = []
	# Interior furniture must occlude actors by real depth, including their feet.
	if not _silhouette_inside:
		if is_instance_valid(player): targets.append(player)
		if is_instance_valid(vehicle): targets.append(vehicle)
	var inverse := Transform3D.IDENTITY
	if is_instance_valid(_silhouette_reference): inverse = _silhouette_reference.global_transform.affine_inverse()
	var box := AABB()
	var has_box := false
	for target in targets:
		var material: ShaderMaterial = _silhouettes.get(target)
		if material == null:
			material = ShaderMaterial.new()
			material.shader = SILHOUETTE_SHADER
			_silhouettes[target] = material
		# Modelos são reconstruídos (arma, roupa, dano); reaplicar é barato
		# porque só toca instâncias que ainda não têm o overlay.
		for node in target.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if not geometry.is_visible_in_tree() or geometry is Label3D or geometry is GPUParticles3D or geometry is CPUParticles3D: continue
			var part: AABB = (inverse * geometry.global_transform) * geometry.get_aabb()
			box = box.merge(part) if has_box else part
			has_box = true
			if geometry.material_overlay == null:
				geometry.material_overlay = material
	# One box encloses all visible pieces, so the rider cannot light up through
	# the motorcycle and the motorcycle cannot light up through its rider.
	box = box.grow(.08)
	for target in targets:
		var material: ShaderMaterial = _silhouettes[target]
		material.set_shader_parameter("box_min", box.position)
		material.set_shader_parameter("box_max", box.end)
		material.set_shader_parameter("minimum_occluder_height", -1000.0 if is_instance_valid(vehicle) else 1.2)
	for previous in _silhouette_targets:
		if is_instance_valid(previous) and previous not in targets:
			var material = _silhouettes.get(previous)
			for node in previous.find_children("*", "GeometryInstance3D", true, false):
				if node.material_overlay == material: node.material_overlay = null
	for key in _silhouettes.keys():
		if not is_instance_valid(key) or key not in targets: _silhouettes.erase(key)
	_silhouette_targets = targets
	_follow_silhouettes()


## O transform muda todo frame (carro andando); a caixa local só muda quando
## o modelo é reconstruído, por isso fica no refresh de 4 Hz.
func _follow_silhouettes() -> void:
	if controller == null: return
	var world = controller.get("world")
	if not is_instance_valid(world): return
	var player: Node3D = world.get("player")
	var vehicle := _silhouette_vehicle(world)
	var player_id := player.get_instance_id() if is_instance_valid(player) else 0
	var vehicle_id := vehicle.get_instance_id() if is_instance_valid(vehicle) else 0
	var transition_id := _silhouette_transition(world)
	var player_visible := is_instance_valid(player) and player.is_visible_in_tree()
	var inside := _uses_interior_depth()
	# Context changes refresh once immediately; ordinary frames only update
	# uniforms. Mesh scans remain at 4 Hz while the context stays the same.
	# Boarding can hide, pose and show the same player without changing IDs.
	# Its completion must include the seated body in the self-occlusion box.
	if inside != _silhouette_inside or player_id != _silhouette_player_id or vehicle_id != _silhouette_vehicle_id or player_visible != _silhouette_player_visible or transition_id != _silhouette_transition_id:
		_refresh_silhouette()
		return
	if not is_instance_valid(_silhouette_reference): return
	var inverse := Projection(_silhouette_reference.global_transform.affine_inverse())
	for target in _silhouettes:
		if is_instance_valid(target):
			_silhouettes[target].set_shader_parameter("target_inverse", inverse)


func _uses_interior_depth() -> bool:
	if not String(controller.state.place_id).is_empty(): return true
	# Continuous underground rooms keep the outdoor place id. Their active
	# camera owns depth presentation, so the street outline must also yield.
	var camera := get_viewport().get_camera_3d()
	return is_instance_valid(camera) and bool(camera.get_meta("uses_interior_depth",false))


func _silhouette_vehicle(world: Node) -> Node3D:
	var driving = world.get("driving")
	if driving != null and driving.get("occupied") and is_instance_valid(driving.get("car")):
		return driving.car
	return null


func _silhouette_transition(world: Node) -> int:
	var driving = world.get("driving")
	var transition = driving.get("transition") if driving != null else null
	return transition.get_instance_id() if is_instance_valid(transition) else 0


## Letreiros de neon (Label3D, sem sombreamento): de dia cor chapada, à noite
## cor em HDR acima de 1 para o glow pegar.
func _update_neon_labels(night: float) -> void:
	if absf(night - _neon_night) < .02: return
	_neon_night = night
	# Acima de ~1,6 o tonemap estoura para branco e a cor some; o glow faz o resto.
	var boost := lerpf(1.0, 1.55, night)
	for label in get_tree().get_nodes_in_group(&"city_neon_label"):
		var color: Color = label.get_meta("neon_color", Color.WHITE)
		label.modulate = Color(color.r * boost, color.g * boost, color.b * boost, 1.0)


## O Weather mantém o relógio e a energia da luz. Cada exterior define o rumo
## e a altura máxima para que as sombras alcancem o chão visível pela câmera.
func _orient_sun() -> void:
	var sun = controller.get("sun") if controller != null else null
	if sun == null or not is_instance_valid(sun): return
	if not String(controller.state.place_id).is_empty(): return
	sun.rotation_degrees.y = -135.0
	if controller.state.region_id == "harbor":
		sun.rotation_degrees.x = maxf(sun.rotation_degrees.x, -35.0)
	elif controller.state.region_id == "mountain":
		sun.rotation_degrees.x = maxf(sun.rotation_degrees.x, -42.0)
