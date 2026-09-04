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
		var freq := 580.0 + 60.0 * (t / duration)
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
	var duration := 0.065 # 65ms (snappy e satisfatório)
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var attack := clampf(t / 0.0015, 0.0, 1.0)
		var env := attack * exp(-t * 55.0)
		# Transiente descendente de 840 Hz para 420 Hz
		var pitch := 420.0 + 420.0 * exp(-t * 80.0)
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

## Retorna stream em loop contínuo de 6 segundos com progressão de acordes ambiente
static func get_music_stream() -> AudioStreamWAV:
	if _cached_music != null:
		return _cached_music

	var sample_rate := 22050
	var duration := 6.0 # 6 segundos loopable
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Frequências dos 4 acordes (Dm -> Bb -> C -> Am), 1.5s cada
	var chords := [
		[146.83, 174.61, 220.00, 261.63], # Dm: D3, F3, A3, C4
		[116.54, 174.61, 233.08, 293.66], # Bb: Bb2, F3, Bb3, D4
		[130.81, 164.81, 196.00, 261.63], # C: C3, E3, G3, C4
		[110.00, 164.81, 220.00, 261.63]  # Am: A2, E3, A3, C4
	]

	# Arpeggio sutil em cima (16 passos de 0.375s)
	var arp_notes := [
		440.0, 349.23, 293.66, 349.23,
		466.16, 349.23, 293.66, 349.23,
		523.25, 392.00, 329.63, 392.00,
		440.0, 329.63, 261.63, 329.63
	]

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		
		# Determinar acorde atual e próximo com interpolação suave
		var chord_idx := int(t / 1.5) % 4
		var next_chord_idx := (chord_idx + 1) % 4
		var chord_phase := fmod(t, 1.5) / 1.5
		
		# Peso de transição entre acordes (curva cosseno suave)
		var blend := 0.5 - 0.5 * cos(chord_phase * PI)
		
		# Somar notas do acorde atual
		var c1 = chords[chord_idx]
		var pad1 := 0.0
		for f in c1:
			# Mistura de onda senoidal suave com segundo harmônico sutil
			pad1 += sin(2.0 * PI * f * t) * 0.18 + sin(4.0 * PI * f * t) * 0.05
		
		# Somar notas do próximo acorde
		var c2 = chords[next_chord_idx]
		var pad2 := 0.0
		for f in c2:
			pad2 += sin(2.0 * PI * f * t) * 0.18 + sin(4.0 * PI * f * t) * 0.05
		
		var pad_mix := lerpf(pad1, pad2, blend)
		
		# LFO de tremolo sutil (0.5 Hz)
		var lfo := 0.88 + 0.12 * sin(2.0 * PI * 0.5 * t)
		pad_mix *= lfo
		
		# Arpeggio agudo (plucky)
		var arp_step := int(t / 0.375) % 16
		var arp_freq = arp_notes[arp_step]
		var arp_time := fmod(t, 0.375)
		var arp_env := exp(-arp_time * 9.0)
		var arp_sample := sin(2.0 * PI * arp_freq * t) * arp_env * 0.09
		
		# Mixagem final com ganho seguro para não clipar
		var total := (pad_mix * 0.45 + arp_sample) * 0.85
		var int_sample := clampi(int(total * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_music = stream
	return stream

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
		tree.root.add_child(player)

	player.stream = stream
	player.volume_db = volume_db
	player.play()

## Vincula sinais focus_entered, mouse_entered e pressed em um botão individual
static func hook_button(btn: BaseButton, host_node: Node) -> void:
	if not btn or not is_instance_valid(btn):
		return
	if btn.has_meta("__menu_audio_hooked"):
		return
	btn.set_meta("__menu_audio_hooked", true)

	btn.focus_entered.connect(func(): play_hover(host_node))
	btn.mouse_entered.connect(func(): play_hover(host_node))
	btn.pressed.connect(func(): play_click(host_node))

## Vincula recursivamente todos os BaseButtons filhos de container ao host_node
static func hook_buttons(container: Node, host_node: Node = null) -> void:
	if not container or not is_instance_valid(container):
		return
	var target_host := host_node if host_node != null else container
	var buttons := container.find_children("", "BaseButton", true, false)
	for btn in buttons:
		if btn is BaseButton:
			hook_button(btn, target_host)
