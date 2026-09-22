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

var controller
## Um material por alvo: cada um carrega a caixa do próprio dono para o
## shader distinguir auto-oclusão (teto do ônibus) de prédio na frente.
var _silhouettes := {}
var _silhouette_targets: Array = []
var _clock := 0.0
var _last_night := -1.0
var _pools_visible := false
var _grade: GradientTexture1D
var _blink := 0.0
var _blink_on := false


func _ready() -> void:
	name = "CityLook"
	_update(true)


func _process(delta: float) -> void:
	_blink += delta
	var phase := fposmod(_blink, 1.1) < .6
	if phase != _blink_on:
		_blink_on = phase
		MATERIALS.set_signal_phase(phase)
	_follow_silhouettes()
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
			Color(0.83, 0.81, 0.76), Color(1.0, 0.97, 0.9)])
		_grade = GradientTexture1D.new()
		_grade.gradient = gradient
		_grade.width = 256
	var env: Environment = holder.environment
	if env.adjustment_color_correction != _grade: env.adjustment_color_correction = _grade


func _refresh_silhouette() -> void:
	var world = controller.get("world")
	if world == null: return
	var targets: Array = []
	if is_instance_valid(world.get("player")): targets.append(world.player)
	var driving = world.get("driving")
	if driving != null and driving.get("occupied") and is_instance_valid(driving.get("car")):
		targets.append(driving.car)
	for target in targets:
		var material: ShaderMaterial = _silhouettes.get(target)
		if material == null:
			material = ShaderMaterial.new()
			material.shader = SILHOUETTE_SHADER
			_silhouettes[target] = material
		# Modelos são reconstruídos (arma, roupa, dano); reaplicar é barato
		# porque só toca instâncias que ainda não têm o overlay.
		var inverse: Transform3D = target.global_transform.affine_inverse()
		var box := AABB()
		var has_box := false
		for node in target.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			if not geometry.visible or geometry is Label3D or geometry is GPUParticles3D or geometry is CPUParticles3D: continue
			var part: AABB = (inverse * geometry.global_transform) * geometry.get_aabb()
			box = box.merge(part) if has_box else part
			has_box = true
			if geometry.material_overlay == null:
				geometry.material_overlay = material
		# Margem pequena: o depth buffer tem precisão finita e a borda do teto
		# não pode cair "fora" da própria caixa.
		box = box.grow(.08)
		material.set_shader_parameter("box_min", box.position)
		material.set_shader_parameter("box_max", box.end)
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
	for target in _silhouettes:
		if is_instance_valid(target):
			_silhouettes[target].set_shader_parameter("target_inverse", Projection(target.global_transform.affine_inverse()))
