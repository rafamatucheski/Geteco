extends RefCounted
## Musiquinha da tela de carregamento (Firefly, 2026-10-15): synthwave calmo em loop, entra
## devagar com a tela e sai junto com ela. Ogg em loop sem emenda; o decodificador roda na
## thread de áudio, então segue tocando mesmo quando o carregamento ocupa o quadro.
## Sem o arquivo importado a tela fica muda, como antes.
const PATH := "res://audio/menu/loading_music.ogg"
const NODE_NAME := "LoadingMusic"
const LEVEL_DB := -16.0

static func attach(curtain: Node) -> AudioStreamPlayer:
	if not is_instance_valid(curtain) or not ResourceLoader.exists(PATH): return null
	var track := load(PATH) as AudioStreamOggVorbis
	if track == null: return null
	var loop := track.duplicate() as AudioStreamOggVorbis
	loop.loop = true
	var player := AudioStreamPlayer.new()
	player.name = NODE_NAME
	player.stream = loop
	player.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	player.volume_db = -40.0
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	curtain.add_child(player)
	player.play()
	_fade(player, LEVEL_DB, 1.6)
	return player

## Some com a tela: o fade acompanha o da cobertura.
static func fade_out(curtain: Node, seconds: float) -> void:
	if not is_instance_valid(curtain): return
	var player := curtain.get_node_or_null(NODE_NAME) as AudioStreamPlayer
	if player == null: return
	_fade(player, -40.0, seconds)

## Um fade por vez: o de saída cancela o de entrada se a cobertura sair antes dele terminar.
static func _fade(player: AudioStreamPlayer, target_db: float, seconds: float) -> void:
	var running: Variant = player.get_meta("fade_tween") if player.has_meta("fade_tween") else null
	if running is Tween and (running as Tween).is_valid(): (running as Tween).kill()
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", target_db, seconds).set_trans(Tween.TRANS_SINE)
	player.set_meta("fade_tween", tween)
