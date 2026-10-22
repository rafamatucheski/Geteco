extends RefCounted
## Orçamento grande enquanto a cortina de carregamento cobre a tela (21/10/2026).
##
## Por que existe: o carregamento fatiava o trabalho com os MESMOS orçamentos do jogo (streaming de
## prédios 1–2 ms por quadro, preparação retida 2 ms, partida da sessão 4 ms). Sob a cortina cada quadro
## ainda desenha o mundo e a tela de carregamento (~5–15 ms a 3440x1440), então a maior parte do tempo de
## "Preparando texturas e prédios" (4,9 s no release) e do streaming inicial era quadro, não trabalho.
## Com a cortina cobrindo (StartupCurtain sem estar saindo), esses orçamentos são multiplicados por FACTOR:
## quadros de ~15–25 ms sob a cortina são aceitáveis (docs/HOW-TO-DEVELOP.md §3.1); no instante em que a
## cortina começa a sair (lift), tudo volta ao orçamento do jogo. Nada sai da cortina por causa disto.
## GETECO_LOADING_TURBO=0 desliga (A/B no mesmo export).
const FACTOR := 6.0
## Cortinas que cobrem a tela agora (id da instância → true). Prévia do menu (stage_only) não entra.
static var _covers := {}
static var _enabled := OS.get_environment("GETECO_LOADING_TURBO") != "0"

## Sem teto de FPS nem v-sync enquanto a cortina cobre (22/10): o carregamento espera quadros (cada
## await process_frame é um quadro; ~900 até jogável no oeste), e com o limite de 144 do jogador cada um
## custava no mínimo 6,9 ms — com v-sync a 60 Hz, 16,7 ms. O teto e o v-sync voltam no lift (o v-sync só
## é tocado se estava ligado, para não recriar a cadeia de troca à toa). GETECO_LOADING_UNCAP=0 desliga.
static var _uncap_enabled := OS.get_environment("GETECO_LOADING_UNCAP") != "0"
static var _saved_fps := -1
static var _saved_vsync := -1

static func cover(curtain: Object) -> void:
	if _enabled and curtain != null:
		if _covers.is_empty() and _uncap_enabled and _saved_fps < 0 and DisplayServer.get_name() != "headless":
			_saved_fps = Engine.max_fps
			_saved_vsync = DisplayServer.window_get_vsync_mode()
			Engine.max_fps = 0
			if _saved_vsync != DisplayServer.VSYNC_DISABLED: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_covers[curtain.get_instance_id()] = true
		if OS.get_environment("GETECO_LOADING_TRACE") == "1": print("LoadingTurbo: cobre ", curtain.get_instance_id(), " quadro ", Engine.get_process_frames(), " cortinas ", _covers.size(), " teto ", Engine.max_fps)

static func uncover(curtain: Object) -> void:
	if curtain != null: _covers.erase(curtain.get_instance_id())
	# A cortina que sai (lift) devolve o jogo: teto e v-sync voltam já, mesmo que outra cortina ainda conste
	# como cobrindo. No A/B de 22/10 o teto de 144 voltava depois de a bancada zerá-lo (JSON com max_fps 144
	# só no lado "depois"), achatando o p50 do deserto e da travessia em ~6,9 ms.
	var lifting := curtain != null and bool(curtain.get("_lifting"))
	if OS.get_environment("GETECO_LOADING_TRACE") == "1": print("LoadingTurbo: descobre ", curtain.get_instance_id() if curtain != null else 0, " saindo ", lifting, " quadro ", Engine.get_process_frames(), " cortinas ", _covers.size(), " teto ", Engine.max_fps, " guardado ", _saved_fps)
	# Nenhuma cortina cobre o jogo visível: um registro que sobrou deixaria o orçamento ×6 no jogo.
	if lifting: _covers.clear()
	if (_covers.is_empty() or lifting) and _saved_fps >= 0:
		# Só devolve o que ninguém mudou no meio (opções aplicadas durante a carga valem).
		if Engine.max_fps == 0: Engine.max_fps = _saved_fps
		if _saved_vsync != DisplayServer.VSYNC_DISABLED and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(_saved_vsync)
		_saved_fps = -1
		_saved_vsync = -1

static func active() -> bool:
	return not _covers.is_empty()

static func budget(base_usec: float) -> float:
	return base_usec * FACTOR if not _covers.is_empty() else base_usec
