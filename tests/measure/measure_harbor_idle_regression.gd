extends "res://tests/measure/measure_performance_plan.gd"
## Diagnóstico de produção parado/a pé; herda saves isolados, assentamento da população,
## 10 s de aquecimento, >=30 s de amostragem e --out=, --label=, --seconds=, --profile.
## --market seleciona o ponto de vista da fachada; --reveal-on opta pela transparência
## externa de diagnóstico. O jogo normal a mantém desligada; --reveal-off também força desligar.
## --walk usa o movimento normal do ator entre pontas próximas, nunca teleporte durante
## a amostra. Registre processos renderizados concorrentes fora deste runner:
## ele não consegue certificar que outros chats do Codex/sessões do Godot deixaram a GPU ociosa.
const MARKET_POINT := Vector3(109.375, .12, 32.8875)
const WALK_HALF_LENGTH := 1.5
var _market := false
var _reveal_off := false
var _reveal_on := false
var _walk := false
var _preview := false
var _night := false
var _night_applied := false
var _walk_anchor := Vector3.ZERO
var _walk_side := 1.0
var _walk_turns := 0
var _walk_distance := 0.0
var _previous_walk_point := Vector3.INF

func _initialize() -> void:
	root.close_requested.connect(func(): print("HARBOR_IDLE_WINDOW_CLOSE_REQUEST ",Time.get_ticks_usec()))
	super._initialize()

func settle_load() -> bool:
	var args := OS.get_cmdline_user_args()
	_market = "--market" in args
	_reveal_off = "--reveal-off" in args
	_reveal_on = "--reveal-on" in args
	_walk = "--walk" in args
	_preview = "--camera-preview" in args
	_night = "--night" in args
	scenario = "walk" if _walk else "idle"
	world.camera.set_preview_view(_preview)
	world.camera.heading = 0.0
	if _reveal_on: world.camera._exterior_reveal.enabled = true
	if _reveal_off: world.camera._exterior_reveal.enabled = false
	if _market:
		# Esta realocação faz parte da preparação, antes de assentamento/aquecimento/medição.
		world.production.region.prepare_collision_at(MARKET_POINT)
		world.player.teleport(MARKET_POINT)
		world.production.region.set_focus(MARKET_POINT)
		world.session.railway_world.set_focus(MARKET_POINT)
		world.camera.initialized = false
	print("HARBOR_IDLE_CONTEXT ", JSON.stringify({
		"pid": OS.get_process_id(), "market": _market, "walk": _walk,
		"reveal_off": _reveal_off, "reveal_on": _reveal_on,
		"concurrency": "Unverified: other rendered sessions may contaminate frame times; capture process inventory separately."
	}))
	var settled: bool = await super.settle_load()
	# O carregamento pode demorar o bastante para o usuário sair da janela. Pede
	# foco uma vez antes do aquecimento; nunca o rouba de volta durante o laço medido.
	if settled:
		# Um lançamento por console escondido pode deixar o motor reportando minimizado mesmo
		# depois de o foco voltar. Restaura uma vez antes do aquecimento, nunca durante a amostragem.
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()
	_walk_anchor = world.player.global_position
	_previous_walk_point = _walk_anchor
	return settled

func apply_load(_now: int) -> void:
	# O pai estabelece o dia depois do assentamento. Aplica a noite uma vez no
	# primeiro callback de aquecimento, antes do intervalo medido, sem salvar configurações.
	if _night and not _night_applied:
		_night_applied = true
		world.session.weather.time_of_day = .78
		world.session.state.world_state.time = .78
		world.session.weather._update()
	if not _walk: return
	var point: Vector3 = world.player.global_position
	if _previous_walk_point.is_finite():
		_walk_distance += Vector2(point.x - _previous_walk_point.x, point.z - _previous_walk_point.z).length()
	_previous_walk_point = point
	var goal := _walk_anchor + Vector3.RIGHT * WALK_HALF_LENGTH * _walk_side
	var offset := goal - point
	offset.y = 0.0
	if offset.length_squared() < .04:
		_walk_side = -_walk_side
		_walk_turns += 1
		goal = _walk_anchor + Vector3.RIGHT * WALK_HALF_LENGTH * _walk_side
		offset = goal - point
		offset.y = 0.0
	# Um obstáculo real pode impedir de chegar a um waypoint. Preserva-o e reporta
	# o movimento/curvas reais, em vez de teleportar ou afirmar uma rota concluída.
	world.player.automatic_direction = offset.normalized()

func state() -> Dictionary:
	var row := super.state()
	row["exterior_reveal"] = world.camera._exterior_reveal.debug_snapshot()
	row["idle_regression_fixture"] = {
		"market": _market, "reveal_off_diagnostic": _reveal_off,
		"requested_preview": _preview, "night": _night, "reveal_on_diagnostic": _reveal_on,
		"motion": "physical_walk" if _walk else "stationary",
		"walk_anchor": str(_walk_anchor), "walk_half_length": WALK_HALF_LENGTH,
		"walk_turns": _walk_turns, "walk_distance_since_warmup_m": _walk_distance,
		"player_velocity": str(world.player.velocity),
		"concurrency_verified": false, "pid": OS.get_process_id(),
		"scope": "Normal production callbacks and live population. Teleport only during setup. With --walk, actual movement starts in warm-up and continues during sampling; this overrides the parent's stationary-fixture description. Concurrent external work is not controlled, so these measurements alone cannot certify regression or absolute FPS."
	}
	return row
