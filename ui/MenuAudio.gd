class_name MenuAudio
extends RefCounted

## Gerador Procedural de Áudio para Menus (SFX & Música)
## Sintetiza ondas PCM 16-bit diretamente em AudioStreamWAV em tempo de execução.
## Roteia sons de interface para o bus "SFX" e trilha ambiente para o bus "Music".
## Totalmente compatível com execução headless (sem crashes por falta de dispositivo de áudio).

static var _cached_hover: AudioStreamWAV = null
static var _cached_click: AudioStreamWAV = null
static var _cached_music: AudioStreamWAV = null

# ==============================================================================
# RESOLUÇÃO SEGURA DE BARRAMENTO DE ÁUDIO
# ==============================================================================

static func get_sfx_bus_name() -> String:
	if AudioServer.get_bus_index("SFX") != -1:
		return "SFX"
	return "Master"

static func get_music_bus_name() -> String:
	if AudioServer.get_bus_index("Music") != -1:
		return "Music"
	return "Master"

# ==============================================================================
# SÍNTESE DE EFEITOS SONOROS (SFX)
# ==============================================================================

## Retorna stream de áudio para o efeito de "hover" (botão ganha foco / mouse entra)
static func get_hover_stream() -> AudioStreamWAV:
	if _cached_hover != null:
		return _cached_hover

	var sample_rate := 22050
	var duration := 0.045 # 45ms (curto e sutil)
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Ataque suave de 2ms para eliminar estalo de descontinuidade DC
		var attack := clampf(t / 0.002, 0.0, 1.0)
		# Decaimento exponencial rápido
		var env := attack * exp(-t * 90.0)
		# Tom suave em 580 Hz com leve chirp ascendente (+60 Hz)
		var freq := 240.0 - 40.0 * (t / duration)
		var sample := sin(2.0 * PI * freq * t) * env * 0.28
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_hover = stream
	return stream

## Retorna stream de áudio para o efeito de "clique" (botão pressionado)
static func get_click_stream() -> AudioStreamWAV:
	if _cached_click != null:
		return _cached_click

	var sample_rate := 22050
	var duration := 0.14 # 65ms (snappy e satisfatório)
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var attack := clampf(t / 0.0015, 0.0, 1.0)
		var env := attack * exp(-t * 28.0)
		# Transiente descendente de 840 Hz para 420 Hz
		var pitch := 120.0 + 110.0 * exp(-t * 35.0)
		var tone_fund := sin(2.0 * PI * pitch * t)
		var tone_harm := sin(2.0 * PI * (pitch * 2.0) * t) * 0.20
		var sample := (tone_fund + tone_harm) * env * 0.40
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_click = stream
	return stream

# ==============================================================================
# SÍNTESE DE MÚSICA DE FUNDO (AMBIENT SYNTH LOOP)
# ==============================================================================

## Original urban suspense instrumental, pre-rendered to avoid synthesis on menu open.
static func get_music_stream() -> AudioStreamWAV:
	if _cached_music == null:
		_cached_music = load("res://audio/menu/harbor_night_menu.wav").duplicate() as AudioStreamWAV
		_cached_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_cached_music.loop_begin = 0
		_cached_music.loop_end = _cached_music.data.size() / 4
	return _cached_music

# ==============================================================================
# REPRODUÇÃO E VINCULAÇÃO DE BOTÕES (HOOKS)
# ==============================================================================

## Executa som de hover no contexto do host_node informado
static func play_hover(host_node: Node) -> void:
	_play_sfx(host_node, "__MenuHoverPlayer", get_hover_stream(), -10.0)

## Executa som de clique no contexto do host_node informado
static func play_click(host_node: Node) -> void:
	_play_sfx(host_node, "__MenuClickPlayer", get_click_stream(), -6.0)

static func _play_sfx(context_node: Node, player_name: String, stream: AudioStream, volume_db: float) -> void:
	var tree: SceneTree = null
	if context_node and is_instance_valid(context_node) and context_node.is_inside_tree():
		tree = context_node.get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	
	if not tree or not tree.root:
		return

	var player: AudioStreamPlayer = tree.root.get_node_or_null(player_name)
	if not player or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		player.name = player_name
		player.bus = get_sfx_bus_name()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		# Initial focus may fire while the root is adding the menu scene.
		# Queue insertion and playback in that order; reuse the pending player
		# when several focus events arrive in the same frame.
		var pending: Variant = tree.root.get_meta(player_name) if tree.root.has_meta(player_name) else null
		if is_instance_valid(pending):
			player.free()
			player = pending
		else:
			tree.root.set_meta(player_name, player)
			tree.root.add_child.call_deferred(player)

	player.stream = stream
	player.volume_db = volume_db
	player.play.call_deferred()

## Vincula sinais focus_entered, mouse_entered e pressed em um botão individual
static func hook_button(btn: BaseButton, host_node: Node) -> void:
	if not btn or not is_instance_valid(btn):
		return
	if btn.has_meta("__menu_audio_hooked"):
		return
	btn.set_meta("__menu_audio_hooked", true)

	btn.focus_entered.connect(func(): play_hover(host_node))
	btn.mouse_entered.connect(func():
		if not btn.disabled: btn.grab_focus())
	btn.pressed.connect(func(): play_click(host_node))
	if btn is OptionButton:
		btn.get_popup().id_focused.connect(func(_id): play_hover(host_node))
		btn.item_selected.connect(func(_id): play_click(host_node))

## Vincula recursivamente todos os BaseButtons filhos de container ao host_node
static func hook_buttons(container: Node, host_node: Node = null) -> void:
	if not container or not is_instance_valid(container):
		return
	var target_host := host_node if host_node != null else container
	var buttons := container.find_children("", "BaseButton", true, false)
	for btn in buttons:
		if btn is BaseButton:
			hook_button(btn, target_host)
