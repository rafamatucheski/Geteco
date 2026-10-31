extends Node
## Voz do rádio da central (perseguição estilo GTA): toca uma fala montada por pedaços, como o scanner
## do GTA — chiado de abrir o canal, frase-base, rua e sentido, chiado de fechar. Os pedaços foram
## gravados na ElevenLabs e passados pelo filtro de rádio em `tools/police_radio_voice.py`
## (manifesto `audio/police_radio/manifest.json`).
## Os WAVs do idioma de voz atual são pedidos em segundo plano ao configurar
## (ResourceLoader.load_threaded_request); pedaço que ainda não carregou é pulado, nunca carregado
## no meio do quadro. `GETECO_RADIO_VOICE=0` deixa o rádio só em texto.

const MANIFEST := "res://audio/police_radio/manifest.json"
const ROOT := "res://audio/police_radio/"
const VOLUME_DB := -3.0
## Silêncio curto entre pedaços: o scanner do GTA também "costura" as falas.
const GAP_SECONDS := 0.06
const LOADS_PER_TICK := 4

static var enabled := OS.get_environment("GETECO_RADIO_VOICE") != "0"

var _manifest: Dictionary = {}
var _language := ""
var _requested: Dictionary = {}
var _streams: Dictionary = {}
var _queue: Array[String] = []
var _player: AudioStreamPlayer
var _gap := 0.0
## Falas tocadas (testes e depuração).
var played := 0

func _ready() -> void:
	name = "PoliceRadioVoice"
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	_player.bus = &"Dialogue" if AudioServer.get_bus_index("Dialogue") >= 0 else &"Master"
	_player.finished.connect(_next)
	add_child(_player)
	set_process(false)
	if not enabled or not FileAccess.file_exists(MANIFEST): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary: _manifest = parsed
	_prepare(_voice_language())

func _voice_language() -> String:
	var settings := get_node_or_null("/root/V2Settings")
	var language := str(settings.get("voice_language")) if settings != null else "pt_BR"
	return "en" if language.begins_with("en") else "pt"

## Pede em segundo plano os WAVs de um idioma (e os chiados).
func _prepare(language: String) -> void:
	if _manifest.is_empty() or language == _language: return
	_language = language
	var paths: Array[String] = [str(_manifest.get("squelch", {}).get("open", "")), str(_manifest.get("squelch", {}).get("close", ""))]
	for table in ["phrases", "headings", "streets"]:
		for key in _manifest.get(table, {}):
			paths.append(str(_manifest[table][key].get(language, "")))
	for relative in paths:
		if relative.is_empty() or _requested.has(relative) or _streams.has(relative): continue
		var path := ROOT + relative
		if not ResourceLoader.exists(path): continue
		if ResourceLoader.load_threaded_request(path, "AudioStream") == OK: _requested[relative] = path
	if not _requested.is_empty(): set_process(true)

func _stream(relative: String) -> AudioStream:
	if _streams.has(relative): return _streams[relative]
	var path: String = _requested.get(relative, "")
	if path.is_empty() or ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED: return null
	var stream := ResourceLoader.load_threaded_get(path) as AudioStream
	_requested.erase(relative)
	_streams[relative] = stream
	return stream

## Todo pedido com thread bem-sucedido é dono de um handle do loader, mesmo quando nenhuma fala é dita.
## Colhe o trabalho concluído quando ocioso; nunca bloqueia um quadro de jogo ativo na decodificação.
func _collect_loaded() -> void:
	var collected := 0
	for relative in _requested.keys():
		if collected >= LOADS_PER_TICK: break
		var path: String = _requested[relative]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED:
			var stream := ResourceLoader.load_threaded_get(path) as AudioStream
			if stream != null: _streams[relative] = stream
		_requested.erase(relative)
		collected += 1

## Chave de pedaço -> caminho relativo no idioma atual ("" se não houver gravação).
## Chaves: "phrase:fleeing", "street:Union Avenue", "heading:norte".
func clip(key: String) -> String:
	var parts := key.split(":", true, 1)
	if parts.size() != 2: return ""
	var table: String = str({"phrase": "phrases", "street": "streets", "heading": "headings"}.get(parts[0], ""))
	var entry: Variant = _manifest.get(table, {}).get(parts[1])
	return str(entry.get(_language, "")) if entry is Dictionary else ""

## Toca uma fala montada. Com o rádio ocupado, a nova fala só entra se `urgent` (substitui).
func say(keys: Array, urgent := false) -> bool:
	if not enabled or _manifest.is_empty(): return false
	_prepare(_voice_language())
	if (_player.playing or not _queue.is_empty()) and not urgent: return false
	var clips: Array[String] = []
	for index in keys.size():
		var key := str(keys[index])
		# "Última posição" sem a rua gravada depois ficaria pendurado: pula a frase.
		if key == "phrase:lost" and (index + 1 >= keys.size() or clip(str(keys[index + 1])).is_empty()): continue
		var relative := clip(key)
		if not relative.is_empty() and _stream(relative) != null: clips.append(relative)
	if clips.is_empty(): return false
	_queue.clear()
	_queue.append(str(_manifest.get("squelch", {}).get("open", "")))
	_queue.append_array(clips)
	_queue.append(str(_manifest.get("squelch", {}).get("close", "")))
	_player.stop()
	played += 1
	_next()
	return true

func _next() -> void:
	_gap = GAP_SECONDS if not _queue.is_empty() else 0.0
	set_process(_gap > 0.0 or not _requested.is_empty())

func _process(delta: float) -> void:
	_collect_loaded()
	_gap -= delta
	if _gap > 0.0: return
	set_process(not _requested.is_empty())
	if is_instance_valid(_player) and _player.playing: return
	while not _queue.is_empty():
		var stream := _stream(_queue.pop_front())
		if stream == null: continue
		_player.stream = stream
		_player.play()
		return

func stop() -> void:
	_queue.clear()
	_gap = 0.0
	if is_instance_valid(_player): _player.stop()
	set_process(not _requested.is_empty())

func _exit_tree() -> void:
	stop()
	# Um mapa pode descarregar logo depois de _ready, antes do próximo tick de coleta.
	# Conclui só o banco de áudio finito pedido por este dono; get libera o handle do
	# loader. Isso pode esperar decodificação pendente na desmontagem, nunca durante a reprodução.
	for path: String in _requested.values():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_requested.clear()
	_streams.clear()
	if is_instance_valid(_player): _player.stream = null
