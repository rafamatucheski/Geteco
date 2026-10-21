extends RefCounted
## Música da tela de carregamento: "Rain on the Borderline" (2026-10-20), no lugar do tema de cordas
## do Gemini/Lyria de 16/10. A faixa já começa cheia, então quem dá a entrada suave é o fade daqui;
## o loop volta para LOOP_OFFSET, onde tools/audio/process_loading_music.py já deixou a emenda
## misturada.
## Entra baixinha com a tela, cresce um pouco e sai em fade quando o jogo aparece. O decodificador
## roda na thread de áudio, então segue tocando mesmo quando o carregamento ocupa o quadro.
## Sem o arquivo importado a tela fica muda, como antes.
const PATH := "res://audio/menu/loading_music.ogg"
const NODE_NAME := "LoadingMusic"
const LOOP_OFFSET := 3.0
## Começa já audível: o carregamento bloqueante da cena Main congela os tweens, e um fade a
## partir do silêncio deixaria a tela muda até o fim do bloqueio.
const START_DB := -24.0
## Volume médio de fundo: a faixa nova é densa do começo ao fim (a antiga tinha introdução calma),
## por isso fica 1 dB abaixo do nível anterior para não disputar atenção com a tela.
const LEVEL_DB := -16.0
const SWELL_SECONDS := 8.0
const OUT_SECONDS := 2.5
const SILENCE_DB := -60.0

static func attach(curtain: Node) -> AudioStreamPlayer:
	if not is_instance_valid(curtain) or not ResourceLoader.exists(PATH): return null
	var track := load(PATH) as AudioStreamOggVorbis
	if track == null: return null
	var loop := track.duplicate() as AudioStreamOggVorbis
	loop.loop = true
	loop.loop_offset = LOOP_OFFSET
	var player := AudioStreamPlayer.new()
	player.name = NODE_NAME
	player.stream = loop
	player.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	player.volume_db = START_DB
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	curtain.add_child(player)
	player.play()
	_fade(player, LEVEL_DB, SWELL_SECONDS)
	return player

## Some depois da tela: a música sai da cobertura (que se apaga em `seconds`) para a raiz e
## termina o fade mais devagar, então a entrada no jogo não corta a faixa.
static func fade_out(curtain: Node, seconds: float) -> void:
	if not is_instance_valid(curtain): return
	var player := curtain.get_node_or_null(NODE_NAME) as AudioStreamPlayer
	if player == null: return
	var root := curtain.get_tree().root if curtain.is_inside_tree() else null
	if root != null: player.reparent(root)
	# -60 dB: ao fim do fade a música já é inaudível, então liberar o nó não corta nada.
	_fade(player, SILENCE_DB, maxf(seconds, OUT_SECONDS))
	if root != null:
		(player.get_meta("fade_tween") as Tween).tween_callback(player.queue_free)

## Um fade por vez: o de saída cancela o de entrada se a cobertura sair antes dele terminar.
static func _fade(player: AudioStreamPlayer, target_db: float, seconds: float) -> void:
	var running: Variant = player.get_meta("fade_tween") if player.has_meta("fade_tween") else null
	if running is Tween and (running as Tween).is_valid(): (running as Tween).kill()
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", target_db, seconds).set_trans(Tween.TRANS_SINE)
	player.set_meta("fade_tween", tween)
