extends Node
## Exterior skill game and a small local cache. Only active rounds poll context.
const ART := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const GAME := preload("res://gameplay/urban_v1/TruckersVillageHorseshoes.gd")
const PREFIX := "truckers_village_leisure_"
const PRIZE_ID := "tonico_horseshoes_prize"
const CACHE_ID := "tonico_windmill_cache"
const REACH := 1.9
var session
var art: Node3D
var ui: Control
var best_score := 0
var cache_opened := false
var playing := false
var _release_controls := false

func configure(owner_session, visuals: Node3D) -> void:
	session = owner_session
	art = visuals
	ui = GAME.new()
	ui.name = "VillageHorseshoes"
	session.world.hud.add_child(ui)
	ui.finished.connect(_finish_game)
	ui.throw_released.connect(_throw)
	set_process(false)
	_reconcile()

func _context_ok() -> bool:
	if session == null or not session.ready_for_play or not is_instance_valid(session.world.player): return false
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return false
	if session.world.gameplay.health <= 0 or session.world.gameplay.stars > 0 or session.world.driving.occupied: return false
	if session.is_transition_blocked(): return false
	var quest = session.urban_operations.get("village_quest")
	return not is_instance_valid(quest) or quest.commerce.data.hostility <= 0

func nearest_action() -> Dictionary:
	if playing or session.modal or not _context_ok() or session.world.player.input_locked: return {}
	var at: Vector3 = session.world.player.global_position
	if at.distance_to(ART.PLAY_POINT) <= REACH:
		return {"id":"urban_v1","target":PREFIX+"play","label":"Jogar ferraduras · recorde %d/3"%best_score}
	if best_score == 3 and not cache_opened and at.distance_to(ART.CACHE_POINT) <= REACH:
		return {"id":"urban_v1","target":PREFIX+"cache","label":"Abrir caixa sob o catavento"}
	return {}

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	if target == PREFIX+"cache": return _collect_cache()
	if target != PREFIX+"play" or not is_instance_valid(ui): return false
	session._menu("Ferraduras")
	session.panel.hide()
	session.menu_closed = _menu_closed
	playing = true
	set_process(true)
	if not ui.open_game():
		playing = false
		session.close_menu()
		set_process(false)
		return false
	if is_instance_valid(art) and art.has_method("begin_round"): art.begin_round()
	return true

func _process(_delta: float) -> void:
	if playing and (not _context_ok() or not session.modal or session.menu_closed != Callable(self,"_menu_closed") or session.world.player.global_position.distance_to(ART.PLAY_POINT) > REACH):
		ui.cancel_game()
	if _release_controls and not _held():
		_release_controls = false
		if not session.modal and session.world.gameplay.health > 0 and not session.is_transition_blocked():
			session.world.player.input_locked = false
	if not playing and not _release_controls: set_process(false)

func _held() -> bool:
	return Input.is_action_pressed("interact") or Input.is_action_pressed("fire") or Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _throw(strength: float, hit: bool) -> void:
	if playing and is_instance_valid(art): art.animate_throw(strength,hit)

func _menu_closed() -> void:
	# FullSession is already closing; never recurse into close_menu here.
	playing = false
	if is_instance_valid(ui): ui.cancel_game()
	_release_controls = _held()
	set_process(_release_controls)
	if _release_controls: _guard_controls_after_close.call_deferred()

func _guard_controls_after_close() -> void:
	# close_menu applies its own lock after the callback. Guard held controls
	# afterwards so an external dismissal cannot leak a shot into gameplay.
	if _release_controls and not session.modal:
		session.world.player.input_locked = true

func _finish_game(hits: int) -> void:
	if not playing: return
	var valid_result: bool = _context_ok() and session.modal and session.menu_closed == Callable(self,"_menu_closed") and session.world.player.global_position.distance_to(ART.PLAY_POINT) <= REACH
	playing = false
	if session.menu_closed == Callable(self,"_menu_closed"):
		session.menu_closed = Callable()
		session.close_menu()
		_release_controls = _held()
		if _release_controls: session.world.player.input_locked = true
	set_process(_release_controls)
	if hits < 0 or hits > 3 or not valid_result: return
	best_score = maxi(best_score,hits)
	var awarded := false
	if hits >= 2 and not _paid(PRIZE_ID):
		awarded = session.state.economy.grant_reward(PRIZE_ID,200)
	var result := "%d/3 acertos"%hits
	if awarded: result += " · R$ 200"
	if hits == 3: result += ". A marca na ferradura aponta para a caixa sob o catavento."
	elif hits < 2: result += ". Acerte pelo menos duas para ganhar o prêmio."
	else: result += ". Três acertos revelam o esconderijo."
	session.show_message(result)
	_persist()

func _paid(id: String) -> bool:
	return session.state.economy.snapshot().transactions.has("reward:"+id)

func _collect_cache() -> bool:
	if not _paid(CACHE_ID) and not session.state.economy.grant_reward(CACHE_ID,650):
		session.show_message("Sem espaço na carteira.")
		return false
	cache_opened = true
	if is_instance_valid(art): art.set_cache_open(true)
	session.show_message("Esconderijo encontrado · R$ 650")
	_persist()
	return true

func _persist() -> void:
	if session.save_block_reason().is_empty(): session.save_game()

func _reconcile() -> void:
	if _paid(PRIZE_ID): best_score = maxi(best_score,2)
	if _paid(CACHE_ID): cache_opened = true; best_score = 3
	if is_instance_valid(art): art.set_cache_open(cache_opened)

func snapshot() -> Dictionary:
	return {"version":1,"best_score":best_score,"cache_opened":cache_opened}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	if playing: ui.cancel_game()
	best_score = int(data.best_score)
	cache_opened = data.cache_opened
	_reconcile()
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	var score: Variant = data.get("best_score")
	return data.get("version") == 1 and typeof(score) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(score)) and float(score) == floorf(float(score)) and float(score) >= 0 and float(score) <= 3 and data.get("cache_opened") is bool and (not data.cache_opened or int(score) == 3)

func _exit_tree() -> void:
	if is_instance_valid(ui): ui.queue_free()
