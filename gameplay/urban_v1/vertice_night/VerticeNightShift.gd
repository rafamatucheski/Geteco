extends Node
## M06-C "Turno da noite" (docs/roteiro-diretor-geteco-20261021.md): depois de Cortar o
## abastecimento, à noite, o Neco liga; depois das 22h a Vértice tem segurança dos Cobras
## (dois na ronda, um na guarita). Escondido: bueiro → porão → alçapão do galpão, vigias com
## cone de visão, derrubada pelas costas, corpo achado vira busca. No tiro: o primeiro disparo
## liga o alarme, as luzes do pátio, a van com reforço em ~1 min, a polícia depois e, se a
## briga demora, o arquivo pega fogo. O livro de despachos dá a página do 0417; no fim, a
## ligação para o Maciota. Estado salvo em VerticeNightState (world_state.vertice_night).
const STATE := preload("res://gameplay/urban_v1/vertice_night/VerticeNightState.gd")
const GUARD := preload("res://gameplay/urban_v1/vertice_night/VerticeNightGuard.gd")
const PROPS := preload("res://gameplay/urban_v1/vertice_night/VerticeNightProps.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
const DIALOGUE_PATH := "res://data/campaign/vertice-night-dialogue.json"
const ORIGIN := Vector3(-340,0,-80)
const YARD_CENTER := Vector3(0,0,24)
const PLACE_UNDERCROFT := "vertice_undercroft"
const ARCHIVE_FIRES := [Vector3(39.6,0,4.2), Vector3(37.2,0,3.0), Vector3(40.0,0,7.4)]
const SENSOR_SECONDS := .15
const ACTIVE_DISTANCE := 130.0
const RELEASE_DISTANCE := 150.0
const ESCAPE_DISTANCE := 85.0
const SHOT_HEARING := 90.0
const REINFORCEMENT_SECONDS := 60.0
const POLICE_SECONDS := 95.0
const FIRE_SECONDS := 150.0
const SEARCH_SECONDS := 45.0
const VAN_SECONDS := 4.0
## Segurança da noite. A guarita olha para a rua, com a TV do lado; as rondas usam as faixas
## livres que os vigias do dia já usam (atrás do galpão em z-24 e nas laterais).
const CREW := [
	{"name":"Brito", "tier":0, "route":[Vector3(-43,0,52),Vector3(-43,0,-24),Vector3(12,0,-24),Vector3(-43,0,-24)]},
	{"name":"Saulo", "tier":0, "route":[Vector3(44,0,-24),Vector3(44,0,56),Vector3(-20,0,56),Vector3(44,0,56)]},
	{"name":"Dinho", "tier":1, "post":Vector3(13.4,0,73), "facing":Vector3(-1,0,.35)}]
const REINFORCEMENTS := [
	{"name":"Pança", "tier":1, "post":Vector3(-2.4,0,58)},
	{"name":"Russo", "tier":2, "post":Vector3(2.4,0,58)},
	{"name":"Tavinho", "tier":0, "post":Vector3(0,0,55)}]
var session
var company: Node3D
var props := {}
var running := false
var alarm := false
var alarm_time := 0.0
var search_time := 0.0
var book_burned := false
var police_called := false
var fire_started := false
var guards: Array = []
var bodies: Array[Dictionary] = []
var van_phase := ""
var van_clock := 0.0
var _pending: Array = []
var _admit_wait := 0.0
var _clock := 0.0
var _flash := 0.0
var _in_dialogue := false
var _failed_night := -999
var _dialogue := {}
var _hud: CanvasLayer
var _label: Label
var _marker: Node2D
var _state_error := false

func configure(owner_session, owner_company: Node3D) -> void:
	session = owner_session
	company = owner_company
	name = "VerticeNightShiftController"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not session.state.world_state.has(STATE.KEY): session.state.world_state[STATE.KEY] = STATE.defaults()

func _ready() -> void:
	var began := STALL_WORK.begin()
	props = PROPS.build(company)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_PATH))
	if parsed is Dictionary: _dialogue = parsed
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 105
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size",18)
	_label.add_theme_color_override("font_color",Color("f7d27c"))
	_label.add_theme_color_override("font_outline_color",Color("171714"))
	_label.add_theme_constant_override("outline_size",4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.hide()
	_hud.add_child(_label)
	_marker = preload("res://ui/DoorAccessMarker.gd").new()
	_hud.add_child(_marker)
	_marker.hide()
	_marker.update_position = _update_marker
	if session.world != null and session.world.gameplay != null:
		session.world.gameplay.weapon_fired.connect(_on_weapon_fired)
	STALL_WORK.finish("vertice_night.ready", began, {})

func data() -> Dictionary:
	var value: Variant = session.state.world_state.get(STATE.KEY)
	return value if STATE.valid(value) else {}

func stage() -> String:
	return str(data().get("stage",""))

func _hour() -> float:
	if session.weather == null: return 12.0
	return fposmod(float(session.weather.time_of_day),1.0)*24.0

func _moon_day() -> int:
	return int(session.weather.moon_day()) if session.weather != null else 0

## A noite começa às 22h e conta como um turno só até de manhã.
func night_window() -> bool:
	var hour := _hour()
	return hour >= 22.0 or hour < 5.0

func _night_id() -> int:
	return _moon_day() if _hour() >= 12.0 else _moon_day()-1

func _call_window() -> bool:
	var hour := _hour()
	return hour >= 20.0 or hour < 5.0

func _player() -> Node3D:
	return session.world.player

func _target() -> Node3D:
	return session.world.gameplay.pursuit_target()

func _yard_distance() -> float:
	var p: Vector3 = _target().global_position
	return Vector2(p.x,p.z).distance_to(Vector2(ORIGIN.x+YARD_CENTER.x,ORIGIN.z+YARD_CENTER.z))

func _local(point: Vector3) -> Vector3:
	return point-ORIGIN

## Livre para uma ligação: nada mais segurando o jogador e salvar permitido.
func _free_for_call() -> bool:
	if not session.ready_for_play or session.modal or _in_dialogue or session.is_transition_blocked(): return false
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.gameplay.health <= 0: return false
	if session.rescue_pending or session.arrest_pending or session.controller.save_invalid: return false
	if session.world.driving.occupied and session.world.driving.car.velocity.length() > 1.0: return false
	return session.save_block_reason().is_empty()

func operational() -> bool:
	return session.ready_for_play and not session.modal and not _in_dialogue and not session.is_transition_blocked() \
		and session.state.place_id.is_empty() and session.world.gameplay.health > 0 and not _player().input_locked

func _process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	if van_phase == "driving": _drive_van(delta)
	_clock += delta
	if _clock < SENSOR_SECONDS: return
	var elapsed := minf(_clock,.5)
	_clock = 0.0
	var state: Variant = session.state.world_state.get(STATE.KEY)
	if not STATE.valid(state):
		if not _state_error: push_error("Estado vertice_night inválido; Turno da noite suspenso")
		_state_error = true
		_release()
		return
	props.tape.visible = STATE.closed_by_police(session.state.world_state,_moon_day())
	if running and str(state.stage) not in ["offered", "escaping"]: _release()
	match str(state.stage):
		"": _try_neco_call()
		"offered", "escaping": _update_operation(elapsed)
	if stage() == "escaping" and not running: _try_maciota_call()
	_update_hud()

# --- Ligação do Neco ------------------------------------------------------------------------

func call_available() -> bool:
	if stage() != "" or not session.state.campaign.has_progress("cobra_supply"): return false
	if not session.state.campaign.active_id.is_empty() or session.state.campaign.aftermath_pending(): return false
	if session.state.intro.stage != "complete" or session.world.gameplay.stars > 0: return false
	return _call_window() and _free_for_call()

func _try_neco_call() -> void:
	if not call_available(): return
	_in_dialogue = true
	session.show_dialogue(lines("neco_call"), _neco_call_done)

func _neco_call_done() -> void:
	_in_dialogue = false
	var state := data()
	if state.is_empty() or state.stage != "": return
	state.stage = "offered"
	session.show_message("Turno da noite · Vértice, depois das 22h.")
	session.save_game()

func lines(id: String) -> Array:
	var result: Array = []
	for row in _dialogue.get(id,[]):
		if row is Dictionary: result.append({"speaker":str(row.get("speaker","")), "message":str(row.get("pt",""))})
	return result

# --- Operação --------------------------------------------------------------------------------

func _should_run() -> bool:
	if session.state.region_id != "harbor" or session.world.gameplay.health <= 0: return false
	if not session.state.place_id.is_empty() and session.state.place_id != PLACE_UNDERCROFT: return false
	if not running and (not night_window() or _night_id() == _failed_night): return false
	if session.state.place_id == PLACE_UNDERCROFT: return true
	return _yard_distance() < (RELEASE_DISTANCE if running else ACTIVE_DISTANCE)

func _update_operation(elapsed: float) -> void:
	var should := _should_run()
	if not running and should and not session.modal and not session.is_transition_blocked(): _begin()
	elif running and not should: _end()
	if not running: return
	var active := operational()
	for guard in guards:
		if is_instance_valid(guard): guard.set_physics_process(active and not guard.dead)
	if not active: return
	_admit_next(elapsed)
	_sense(elapsed)
	_tick_alarm(elapsed)
	if search_time > 0.0:
		search_time -= elapsed
		if search_time <= 0.0 and not alarm:
			for guard in _live_guards(): guard.calm_down()

func _begin() -> void:
	running = true
	alarm = false
	alarm_time = 0.0
	search_time = 0.0
	police_called = false
	fire_started = false
	book_burned = false
	bodies.clear()
	_pending = CREW.duplicate(true)
	_admit_wait = 0.0
	company.set_night_hold(true)
	company.night_office_access = true
	props.book.visible = stage() == "offered"

## Encerra a operação sem mexer no estado salvo (salvo o fracasso do livro, tratado antes).
func _end() -> void:
	if alarm and stage() == "offered" and not book_burned:
		session.show_message("A Vértice ficou em alerta. Volte outra noite.")
		_failed_night = _night_id()
	_release()

func _release() -> void:
	running = false
	alarm = false
	van_phase = ""
	_pending.clear()
	for guard in guards:
		if is_instance_valid(guard):
			guard.set_physics_process(false)
			guard.collision_layer = 0
			guard.queue_free()
	guards.clear()
	bodies.clear()
	if is_instance_valid(company):
		company.set_night_hold(false)
		company.night_office_access = false
		company.night_gate_open = false
		company.set_night_alarm(false)
	if is_instance_valid(props.get("root")):
		for beacon in props.beacons: beacon.visible = false
		props.van.node.visible = false
		props.van.node.position = PROPS.VAN_FROM
		props.van.body.collision_layer = 0
	if is_instance_valid(_label): _label.hide()

func _admit_next(elapsed: float) -> void:
	_admit_wait = maxf(0.0,_admit_wait-elapsed)
	if _pending.is_empty() or _admit_wait > 0.0: return
	var spec: Dictionary = _pending[0]
	var local: Vector3 = spec.route[0] if spec.has("route") else spec.post
	var point: Vector3 = ORIGIN+local+Vector3.UP*.06
	var region = session.controller.regions.get("harbor")
	if is_instance_valid(region) and not region.prepare_collision_at(point): return
	if not session.position_clear(point):
		_admit_wait = .5
		return
	# Um vigia por vez: o modelo do Cobra é a peça mais cara, e o span dá nome ao pico.
	var began := STALL_WORK.begin()
	_pending.pop_front()
	var guard := GUARD.new()
	guard.configure(session.world.gameplay,int(spec.tier))
	guard.shift = self
	for waypoint in spec.get("route",[]): guard.route.append(ORIGIN+waypoint)
	guard.post_facing = spec.get("facing",Vector3.ZERO)
	if spec.has("post"):
		guard.view_range = 9.0
		guard.view_cos = cos(deg_to_rad(42.0))
	props.root.add_child(guard)
	guard.global_position = point
	guard.set_meta("character_name",spec.name)
	guard.set_meta("police_place_id","")
	guard.died.connect(_guard_down.bind(guard))
	guards.append(guard)
	if alarm: guard.alert(_target().global_position)
	_admit_wait = .3
	STALL_WORK.finish_slow("vertice_night.admit_guard", began, 2000, self)

func _live_guards() -> Array:
	var result: Array = []
	for guard in guards:
		if is_instance_valid(guard) and not guard.dead: result.append(guard)
	return result

func live_count() -> int:
	return _live_guards().size()

func _sense(elapsed: float) -> void:
	var target := _target()
	var point: Vector3 = target.global_position
	var exclude: Array[RID] = []
	for guard in guards:
		if is_instance_valid(guard): exclude.append(guard.get_rid())
	# Com o pátio aceso o vigia enxerga mais longe; um carro chama atenção de longe.
	var range_scale := (1.6 if alarm else 1.0)*(1.5 if session.world.driving.occupied else 1.0)
	for guard in _live_guards():
		if guard.engaged: continue
		var seen: bool = target.visible and guard.can_see(point,target,range_scale,exclude)
		if guard.perceive(seen,point,elapsed,range_scale):
			raise_alarm("seen")
			return
		for body in bodies:
			if body.found or not is_instance_valid(body.guard): continue
			if guard.global_position.distance_to(body.point) < 10.0 and guard.can_see(body.point,null,1.0,exclude):
				body.found = true
				_start_search(body.point)

func _start_search(point: Vector3) -> void:
	search_time = SEARCH_SECONDS
	session.show_message("Acharam um vigia no chão. A ronda virou busca.")
	var index := 0
	for guard in _live_guards():
		guard.search(point+Vector3(sin(index*2.1),0,cos(index*2.1))*3.0*index)
		index += 1

func _guard_down(guard: Node) -> void:
	# Durante o alarme ninguém precisa achar o corpo: a briga já é pública.
	bodies.append({"guard":guard, "point":guard.global_position, "found":alarm})

func guard_hurt(guard: Node, _source: Node) -> void:
	if not guard.dead: raise_alarm("hurt")

func _on_weapon_fired(_weapon_id: String, origin: Vector3) -> void:
	if not running or alarm: return
	if Vector2(origin.x,origin.z).distance_to(Vector2(ORIGIN.x+YARD_CENTER.x,ORIGIN.z+YARD_CENTER.z)) <= SHOT_HEARING:
		raise_alarm("shot")

func raise_alarm(_reason: String) -> void:
	if not running or alarm: return
	alarm = true
	alarm_time = 0.0
	search_time = 0.0
	var state := data()
	if not state.is_empty() and state.stage == "escaping": state.route = "loud"
	var seen_at: Vector3 = _target().global_position
	for guard in _live_guards(): guard.alert(seen_at)
	for body in bodies: body.found = true
	company.set_night_alarm(true)
	session.world.gameplay._play_stream(AUDIO.wav("panic_1.wav"),ORIGIN+YARD_CENTER+Vector3.UP*3,-2.0)
	session.show_message("Alarme na Vértice! A van dos Cobras vem com reforço.")

func _tick_alarm(elapsed: float) -> void:
	if not alarm: return
	alarm_time += elapsed
	_flash += elapsed
	var lit := fposmod(_flash,.8) < .4
	for beacon in props.beacons: beacon.visible = lit
	if van_phase == "" and alarm_time >= REINFORCEMENT_SECONDS:
		van_phase = "driving"
		van_clock = 0.0
		company.night_gate_open = true
		props.van.node.position = PROPS.VAN_FROM
		props.van.node.visible = true
	if not police_called and alarm_time >= POLICE_SECONDS:
		police_called = true
		session.world.gameplay.register_crime(preload("res://gameplay/Gameplay.gd").STAR_THRESHOLDS[2],ORIGIN+YARD_CENTER,"reported")
		session.show_message("Alguém chamou a polícia.")
	if not fire_started and alarm_time >= FIRE_SECONDS:
		fire_started = true
		for local in ARCHIVE_FIRES: session.world.gameplay.emergency.ignite(ORIGIN+local,null,1.4)
		props.book.visible = false
		if stage() == "offered":
			book_burned = true
			_failed_night = _night_id()
			session.show_message("O arquivo pegou fogo. O livro de despachos virou cinza. Volte outra noite.")

func _drive_van(delta: float) -> void:
	van_clock += delta
	var t := clampf(van_clock/VAN_SECONDS,0.0,1.0)
	props.van.node.position = PROPS.VAN_FROM.lerp(PROPS.VAN_TO,1.0-pow(1.0-t,2.0))
	if t < 1.0: return
	van_phase = "parked"
	props.van.body.collision_layer = 1
	_pending.append_array(REINFORCEMENTS.duplicate(true))

func fire_seconds_left() -> float:
	return maxf(0.0,FIRE_SECONDS-alarm_time) if alarm and not fire_started else 0.0

# --- Ações (E) -------------------------------------------------------------------------------

func nearest_action() -> Dictionary:
	if session == null or not session.ready_for_play or session.modal or _in_dialogue: return {}
	if session.state.region_id != "harbor" or not session.state.place_id.is_empty() or session.world.driving.occupied: return {}
	var player := _player()
	if player.dead or player.input_locked: return {}
	var p := _local(player.global_position)
	var current := stage()
	if current == "offered" and not running and night_window() and p.distance_to(PROPS.SEWER_POINT) < 1.5 and _night_id() != _failed_night:
		return _action("vertice_night_sewer","Descer pelo bueiro",PROPS.SEWER_POINT)
	if not running: return {}
	if current == "offered" and p.distance_to(PROPS.SEWER_POINT) < 1.5:
		return _action("vertice_night_sewer","Descer pelo bueiro",PROPS.SEWER_POINT)
	var takedown := _takedown_guard()
	if takedown != null: return _action("vertice_night_takedown","Derrubar",_local(takedown.global_position))
	if current == "offered" and not book_burned and p.distance_to(PROPS.BOOK_POINT) < 1.5:
		return _action("vertice_night_book","Abrir o arquivo",PROPS.BOOK_POINT)
	if current == "escaping" and not alarm and data().route == "stealth" and not data().safe and p.distance_to(PROPS.SAFE_POINT) < 1.4:
		return _action("vertice_night_safe","Abrir o cofre",PROPS.SAFE_POINT)
	if not alarm and absf(p.x-PROPS.GATE_POINT.x) < 7.0 and p.z > 78.6 and p.z < 84.0:
		return _action("vertice_night_gate","Forçar o portão",PROPS.GATE_POINT)
	return {}

func _action(target: String, label: String, local: Vector3) -> Dictionary:
	return {"id":"urban_v1", "target":target, "label":label, "position":ORIGIN+local}

## Só pelas costas e com o vigia fora do combate.
func _takedown_guard() -> Node:
	var player := _player()
	for guard in _live_guards():
		if guard.engaged: continue
		var offset: Vector3 = player.global_position-guard.global_position
		offset.y = 0
		if offset.length() > 1.6 or offset.length() < .05: continue
		if guard.facing().dot(offset.normalized()) < -.3: return guard
	return null

func perform(target: String) -> bool:
	if nearest_action().get("target","") != target: return false
	match target:
		"vertice_night_sewer":
			session.enter_place(PLACE_UNDERCROFT,false,PLACE_UNDERCROFT)
			return true
		"vertice_night_takedown":
			var guard := _takedown_guard()
			if guard == null: return false
			guard.knock_out(_player().global_position)
			session.world.gameplay._play_stream(AUDIO.wav("impact_flesh_0.wav"),guard.global_position+Vector3.UP,-16.0)
			return true
		"vertice_night_book":
			_in_dialogue = true
			for guard in guards:
				if is_instance_valid(guard): guard.set_physics_process(false)
			session.show_dialogue(lines("dispatch_book"),_book_done)
			return true
		"vertice_night_safe": return _open_safe()
		"vertice_night_gate":
			company.night_gate_open = true
			raise_alarm("gate")
			return true
	return false

func _book_done() -> void:
	_in_dialogue = false
	var state := data()
	if state.is_empty() or state.stage != "offered" or book_burned: return
	state.stage = "escaping"
	state.route = "loud" if alarm else "stealth"
	props.book.visible = false
	session.show_message("Dante arranca a página, dobra e guarda no bolso.")

func _open_safe() -> bool:
	var state := data()
	# No tiro o cofre queima junto: só o caminho escondido leva o dinheiro.
	if state.is_empty() or state.safe or state.stage != "escaping" or state.route != "stealth" or alarm: return false
	var receipt: Dictionary = session.state.economy.grant_world_reward({"id":STATE.SAFE_RECEIPT, "kind":"cash", "amount":STATE.SAFE_CASH, "label":"Cofre dos Cobras"})
	if not receipt.get("ok",false):
		session.show_message("Libere espaço na carteira para levar o dinheiro do cofre.")
		return false
	state.safe = true
	props.safe_door.rotation.y = -1.9
	preload("res://gameplay/RewardAudio.gd").play(self,"cash")
	session.show_message("Dinheiro dos Cobras recolhido.")
	return true

# --- Saída e ligação do Maciota ------------------------------------------------------------

func _try_maciota_call() -> void:
	if _yard_distance() < ESCAPE_DISTANCE or session.world.gameplay.stars > 0: return
	if not _free_for_call(): return
	_in_dialogue = true
	session.show_dialogue(lines("maciota_call"),_maciota_call_done)

func _maciota_call_done() -> void:
	_in_dialogue = false
	var state := data()
	if state.is_empty() or state.stage != "escaping" or session.world.gameplay.health <= 0: return
	state.stage = "done"
	if state.route == "loud": state.closed_until = _moon_day()+STATE.CLOSED_DAYS
	session.show_message("Turno da noite concluído.")
	session.save_game()

# --- Sessão ---------------------------------------------------------------------------------

func save_block_reason() -> String:
	if not running: return ""
	if alarm: return "Fuja da Vértice e encerre o alarme para salvar."
	return "Saia da Vértice para salvar."

func objective() -> String:
	match stage():
		"offered":
			if book_burned or _night_id() == _failed_night: return "Turno da noite: tente a Vértice outra noite, depois das 22h."
			if not running: return "Turno da noite: entre na Vértice depois das 22h pelo bueiro do portão." if night_window() else "Turno da noite: a ronda dos Cobras começa às 22h."
			if alarm: return "Pegue o livro de despachos no escritório antes que o arquivo queime."
			return "Ache o livro de despachos no escritório da Vértice sem ser visto."
		"escaping":
			if running and alarm: return "Fuja da Vértice."
			if running and data().route == "stealth" and not data().safe: return "Saia da Vértice. O cofre do escritório está ao lado do arquivo."
			if running: return "Saia da Vértice sem ser visto."
			if session.world.gameplay.stars > 0: return "Despiste a polícia."
			return "Afaste-se da Vértice e pare para ligar para o Maciota."
	return ""

func target_position() -> Vector3:
	match stage():
		"offered": return ORIGIN+(PROPS.BOOK_POINT if running else PROPS.SEWER_POINT)
	return Vector3.INF

func _update_hud() -> void:
	if not is_instance_valid(_label): return
	var text := ""
	if running and alarm and not fire_started and stage() == "offered":
		var left := ceili(fire_seconds_left())
		text = "Arquivo em chamas em %d:%02d" % [left/60, left%60]
	elif running and not alarm:
		var worst := 0.0
		for guard in _live_guards(): worst = maxf(worst,guard.suspicion)
		if search_time > 0.0: text = "Busca em andamento"
		elif worst >= .35: text = "Um vigia desconfiou"
	_label.text = text
	_label.visible = not text.is_empty() and session.state.place_id.is_empty()

func _update_marker() -> void:
	var point := target_position()
	_marker.visible = point != Vector3.INF and not session.modal and session.state.place_id.is_empty() and stage() == "offered" and not running and night_window()
	if not _marker.visible: return
	var camera := get_viewport().get_camera_3d()
	_marker.visible = is_instance_valid(camera) and not camera.is_position_behind(point) and camera.global_position.distance_to(point) < 60.0
	if _marker.visible: _marker.position = camera.unproject_position(point+Vector3.UP*.2)

func snapshot() -> Dictionary:
	return {"stage":stage(), "running":running, "alarm":alarm, "alarm_time":alarm_time, "guards":guards.size(),
		"alive":live_count(), "bodies":bodies.size(), "search":search_time > 0.0, "van":van_phase, "book_burned":book_burned}

func _exit_tree() -> void:
	_release()
