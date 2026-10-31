extends Node3D
## WeaponPickup da V1: giro de 1.6 rad/s, balanço de 3.2 rad/s, halo pulsante
## e absorção de um quarto de segundo. Só a arte se move; a âncora no chão fica parada.
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const PROXIMITY_RADIUS := 9.0
const PROXIMITY_POLL_SECONDS := .2
const PROXIMITY_CUE_SECONDS := 4.0
const PROXIMITY_VOLUME_DB := -16.0
var art: Node3D
var ring: MeshInstance3D
var material: StandardMaterial3D
var consumed := false
var age := 0.0
var phase := 0.0
var _tween: Tween
## Ajustes para peças grandes (baú): sem giro/flutuação, halo maior. Padrões = V1.
var spin_speed := 1.6
var bob_height := .045
var lift := .09
var halo_scale := 1.0
## Sinal opcional de exploração. Recompensas ainda tocam o som de dinheiro/arma na
## transação que concede; reconciliar um save nunca toca som de coleta aqui.
var proximity_audio_enabled := false
var proximity_voice: AudioStreamPlayer
var _proximity_listener: Node3D
var _proximity_poll := 0.0
var _proximity_wait := 0.0

func set_proximity_audio(enabled: bool, listener: Node3D = null) -> void:
	proximity_audio_enabled = enabled
	_proximity_listener = listener
	_proximity_poll = 0.0
	_stop_proximity_audio()

func _proximity_initial_delay() -> float:
	# Recompensas próximas começam em batidas diferentes e permitem à reconciliação do save
	# esconder as já coletadas antes do primeiro aviso de aproximação.
	return .65 + phase / TAU * .8

func _stop_proximity_audio() -> void:
	if is_instance_valid(proximity_voice) and proximity_voice.playing: proximity_voice.stop()
	_proximity_wait = _proximity_initial_delay()

func _update_proximity_audio(delta: float) -> void:
	if not proximity_audio_enabled: return
	if consumed or not is_visible_in_tree():
		_stop_proximity_audio()
		return
	_proximity_poll -= delta
	if _proximity_poll > 0.0: return
	_proximity_poll = PROXIMITY_POLL_SECONDS
	var camera := get_viewport().get_camera_3d()
	var listener := _proximity_listener
	if not is_instance_valid(listener) and camera != null:
		# A câmera ortográfica fica bem acima do Dante. Usa o ator/carro seguido por ela
		# para alcance e volume em vez de atenuar pela altitude da câmera.
		# Troca de alvo/embarque é observada a cada consulta; só ouvintes explícitos persistem.
		listener = camera.get("target") as Node3D
	if not is_instance_valid(listener) or not listener.is_visible_in_tree():
		_stop_proximity_audio()
		return
	var distance := global_position.distance_to(listener.global_position)
	if distance >= PROXIMITY_RADIUS:
		_stop_proximity_audio()
		return
	_proximity_wait -= PROXIMITY_POLL_SECONDS
	if is_instance_valid(proximity_voice):
		proximity_voice.volume_db = PROXIMITY_VOLUME_DB + linear_to_db(maxf(.02, 1.0 - distance / PROXIMITY_RADIUS))
	if _proximity_wait > 0.0: return
	if not is_instance_valid(proximity_voice):
		proximity_voice = AudioStreamPlayer.new()
		proximity_voice.name = "PickupProximityAudio"
		proximity_voice.stream = REWARD_AUDIO.stream("collectible")
		proximity_voice.bus = REWARD_AUDIO.AUDIO.SFX_BUS_NAME
		add_child(proximity_voice)
		proximity_voice.volume_db = PROXIMITY_VOLUME_DB + linear_to_db(maxf(.02, 1.0 - distance / PROXIMITY_RADIUS))
	if proximity_voice.stream != null:
		proximity_voice.set_meta("cue_count", int(proximity_voice.get_meta("cue_count", 0)) + 1)
		proximity_voice.play()
	_proximity_wait = PROXIMITY_CUE_SECONDS

func configure(model: Node3D, item: String) -> void:
	art = model
	art.name = "Visual"
	add_child(art)
	phase = float(hash(item) % 1000) / 1000.0 * TAU
	_stop_proximity_audio()
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	var material_started := STALL_WORK.begin()
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(.3,.85,1,.3) if item == "water" else Color(.95,.75,.25,.3)
	if item in ["apple","sandwich"]: material.albedo_color = Color(.3,.9,.45,.3)
	if material_started != 0:
		STALL_WORK.finish("pickup.configure.material", material_started, {"item":item})
	var torus_started := STALL_WORK.begin()
	ring = MeshInstance3D.new()
	ring.name = "PickupHalo"
	var mesh := TorusMesh.new()
	mesh.inner_radius = .29
	mesh.outer_radius = .35
	mesh.rings = 24
	mesh.ring_segments = 6
	if torus_started != 0:
		STALL_WORK.finish("pickup.configure.torus_create", torus_started, {"item":item})
	var bind_started := STALL_WORK.begin()
	var bind_step_started := STALL_WORK.begin()
	ring.mesh = mesh
	if bind_step_started != 0:
		STALL_WORK.finish("pickup.bind.mesh", bind_step_started, {"item":item})
	bind_step_started = STALL_WORK.begin()
	ring.material_override = material
	if bind_step_started != 0:
		STALL_WORK.finish("pickup.bind.material", bind_step_started, {"item":item})
	bind_step_started = STALL_WORK.begin()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = .015
	ring.scale.y = .08
	if bind_step_started != 0:
		STALL_WORK.finish("pickup.bind.properties", bind_step_started, {"item":item})
	bind_step_started = STALL_WORK.begin()
	add_child(ring)
	if bind_step_started != 0:
		STALL_WORK.finish("pickup.bind.add_child", bind_step_started, {"item":item})
	if bind_started != 0:
		STALL_WORK.finish("pickup.configure.torus_bind", bind_started, {"item":item})

func _process(delta: float) -> void:
	_update_proximity_audio(delta)
	if consumed or art == null or not is_visible_in_tree(): return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) > 6400: return
	age += delta
	art.rotation.y = age * spin_speed
	art.position.y = lift + sin(age * 3.2 + phase) * bob_height
	var pulse := 1.0 + sin(age * 2.5 + phase) * .12
	ring.scale = Vector3(pulse * halo_scale,.08,pulse * halo_scale)
	material.albedo_color.a = .25 + sin(age * 3.2 + phase) * .08

## `keep` deixa o nó vivo e escondido no fim da absorção: recompensas fixas do mundo
## voltam com `set_available(true)` (novo jogo, recibo removido) sem recriar o visual.
func collect(keep := false) -> void:
	if consumed: return
	consumed = true
	_stop_proximity_audio()
	set_process(false)
	var body := get_node_or_null("PickupBody") as StaticBody3D
	if body != null: body.collision_layer = 0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art,"scale",Vector3.ONE * .2,.25)
	_tween.tween_property(art,"position:y",art.position.y + .5,.25)
	_tween.tween_property(material,"albedo_color:a",0.0,.25)
	for mesh in art.find_children("*","GeometryInstance3D",true,false):
		_tween.tween_property(mesh,"transparency",1.0,.25)
	_tween.chain().tween_callback(_finish_collect.bind(keep))

func _finish_collect(keep: bool) -> void:
	if keep: visible = false
	else: queue_free()

## Interface das recompensas de mundo (`set_reward_available`): some com a animação
## de absorção quando `animate`, aparece de volta restaurando o estado do visual.
func set_available(available: bool, animate := false) -> void:
	if not available: _stop_proximity_audio()
	if available:
		if consumed:
			if _tween != null and _tween.is_valid(): _tween.kill()
			consumed = false
			art.scale = Vector3.ONE
			material.albedo_color.a = .25
			for mesh in art.find_children("*","GeometryInstance3D",true,false):
				mesh.transparency = 0.0
			set_process(true)
		visible = true
	elif _tween != null and _tween.is_running():
		return
	elif animate and visible and not consumed:
		collect(true)
	else:
		visible = false

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): _stop_proximity_audio()
