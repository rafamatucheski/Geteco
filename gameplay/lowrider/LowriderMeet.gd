extends Node3D
## Encontro de lowriders da Vila Cobra (27/10). Toda noite, das 18 h às 3 h, a turma estaciona os
## lowriders no acostamento norte da rua de acesso da vila (o lado sul é o pátio da Torque, do
## encontro de clássicos), liga o som no porta-malas do conversível e faz a hidráulica dançar.
## Quem chega num lowrider pode tentar bater o recorde de pulo da noite.
## Dono único de carros (Vehicle de verdade: dá para entrar e roubar), convidados, som e desafio.
## Só existe perto do jogador e monta uma peça por varredura (carro ou pessoa), com a cena do
## carro já carregada em segundo plano: nada pesado num quadro só.
const FLEET := preload("res://runtime/MuscleFleet.gd")
const GUEST := preload("res://gameplay/lowrider/LowriderGuest.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const CENTER := Vector3(428.0, 0.0, 100.5)
const ACTIVATE_DISTANCE := 110.0
const RELEASE_DISTANCE := 140.0
const START_HOUR := 18.0
const END_HOUR := 3.0
## Virados para a vila (frente em +X). Acostamento entre a calçada (z 99,9) e a pista (z 103,6);
## o poste em x 430,6 e o acesso da casa em x 444,9 ficam livres.
const YAW := -PI * .5
const CAR_SPOTS := [
	{"model":"imperador_64", "position":Vector3(412.0, .12, 101.5), "paint":"6b1fa0", "show":"hop", "day":true},
	{"model":"monte_rei_84", "position":Vector3(418.6, .12, 101.5), "paint":"8a1f24", "show":"side"},
	{"model":"imperador_64_conv", "position":Vector3(425.3, .12, 101.5), "paint":"1f6fa8", "show":"three_wheel", "music":true},
	{"model":"duque_76", "position":Vector3(437.0, .12, 101.5), "paint":"e9e6dc", "show":"front", "day":true},
	{"model":"monte_rei_84", "position":Vector3(443.6, .12, 101.5), "paint":"2f8f4e", "show":"wave"},
]
## Na calçada atrás dos carros; os primeiros dançam perto do som.
const GUEST_SPOTS := [
	{"position":Vector3(424.0, .06, 98.6), "focus":Vector3(425.3, 0, 101.5), "coat":"e9e6dc", "dancer":true},
	{"position":Vector3(426.6, .06, 98.4), "focus":Vector3(425.3, 0, 101.5), "coat":"16191b", "dancer":true},
	{"position":Vector3(422.2, .06, 98.9), "focus":Vector3(424.0, 0, 98.6), "coat":"2f4f8f", "dancer":true},
	{"position":Vector3(412.8, .06, 98.7), "focus":Vector3(412.0, 0, 101.5), "coat":"8a1f24"},
	{"position":Vector3(414.6, .06, 98.4), "focus":Vector3(412.0, 0, 101.5), "coat":"e9e6dc"},
	{"position":Vector3(418.0, .06, 98.8), "focus":Vector3(418.6, 0, 101.5), "coat":"3a3f44"},
	{"position":Vector3(435.6, .06, 98.7), "focus":Vector3(437.0, 0, 101.5), "coat":"c9a24a"},
	{"position":Vector3(438.8, .06, 98.5), "focus":Vector3(437.0, 0, 101.5), "coat":"16191b"},
	{"position":Vector3(442.0, .06, 98.8), "focus":Vector3(443.6, 0, 101.5), "coat":"e9e6dc"},
]
## Faixas CC0 que já estão no jogo (rádios PORTO CRUISE e PORTO GROOVE): sem trilha sintetizada.
## G-funk próprio do encontro (Gemini, tools/audio/process_lowrider_music.py) toca uma vez sim, outra
## não, entre as faixas funk/cruise das rádios.
const TRACKS := ["res://audio/lowrider/gfunk_meet.ogg", "res://audio/living_city/porto_groove.ogg", "res://audio/lowrider/gfunk_meet.ogg", "res://audio/living_city/porto_cruise.ogg"]
const MUSIC_DB := -7.0
const MUSIC_NEAR := 9.0
const MUSIC_RANGE := 60.0
## Mais perto que isso o som do encontro manda: o rádio do carro do jogador pausa.
const MUSIC_CLAIM := 24.0
const CHALLENGE_RADIUS := 16.0
const HOP_REWARD := 600
var session
var active := false
var event_active := false
var cars: Dictionary = {}
var guests: Dictionary = {}
var record := 0.0
var _scan := 0.0
var _show_clock := 2.0
var _rng := RandomNumberGenerator.new()
var _scene_refs: Dictionary = {}
var _night := -1
var _music: AudioStreamPlayer
var _track := 0
var _claimed := false
var _audio_owner: WeakRef
var _challenger: CharacterBody3D
var _hint_shown := false
var _rewarded := false

func configure(owner_session) -> void:
	session = owner_session
	name = "LowriderMeet"
	_rng.randomize()

static func is_event_time(time_of_day: float) -> bool:
	if not is_finite(time_of_day): return false
	var hour := fposmod(time_of_day, 1.0) * 24.0
	return hour >= START_HOUR or hour < END_HOUR

## A noite do encontro: depois da meia-noite ainda é a noite que começou na véspera.
static func night_of(day: int, time_of_day: float) -> int:
	return day - 1 if fposmod(time_of_day, 1.0) * 24.0 < END_HOUR else day

func _process(delta: float) -> void:
	if session == null or not session.get("ready_for_play"): return
	_scan -= delta
	_show_clock -= delta
	if _scan <= 0.0:
		_scan = .25
		refresh_context()
	if active and event_active:
		_update_show()
		_update_music()

func refresh_context() -> void:
	var player: Node3D = session.world.player
	var weather = session.get("weather")
	var clock: float = float(weather.time_of_day) if weather != null else .9
	var day: int = int(weather.moon_day()) if weather != null and weather.has_method("moon_day") else 0
	var outdoors: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	var distance := _focus().distance_to(CENTER) if is_instance_valid(player) else INF
	var wanted := outdoors and distance < (RELEASE_DISTANCE if active else ACTIVATE_DISTANCE)
	var was_event := event_active
	event_active = is_event_time(clock) or OS.get_environment("GETECO_LOWRIDER_MEET") == "always"
	var night := night_of(day, clock)
	if night != _night:
		_night = night
		# Recorde da vila sorteado por noite; o prêmio do desafio vale uma vez por noite.
		record = snappedf(_rng.randf_range(.70, .92), .01)
		_rewarded = session.state.economy.has_reward_receipt(_receipt()) if session.state.get("economy") != null else false
	if active and (not wanted or was_event != event_active):
		_release_population(not wanted)
	active = wanted
	if not active:
		_stop_music()
		return
	_spawn_next()
	_update_challenge()

func _focus() -> Vector3:
	var driving = session.world.get("driving")
	if driving != null and driving.get("occupied") and is_instance_valid(driving.get("car")): return driving.car.global_position
	return session.world.player.global_position

# ---------------------------------------------------------------- população

func _wanted_car(index: int) -> bool:
	return event_active or bool(CAR_SPOTS[index].get("day", false))

func _spawn_next() -> void:
	for index in CAR_SPOTS.size():
		if cars.has(index) or not _wanted_car(index): continue
		var spot: Dictionary = CAR_SPOTS[index]
		var model := str(spot.model)
		if not _scene_ready(model): return
		var began := STALL_WORK.begin()
		var car = session.world.production.spawn_vehicle(model, spot.position, YAW)
		STALL_WORK.finish_slow("lowrider_meet.spawn_car", began, 4000, self)
		if car == null: return
		car.vehicle_id = "lowrider_meet_%d_%d" % [index, Time.get_ticks_usec()]
		car.paint_color = Color(str(spot.paint))
		car.set_meta("lowrider_meet_spot", index)
		cars[index] = car
		return
	if not event_active: return
	for index in GUEST_SPOTS.size():
		if guests.has(index): continue
		var spec: Dictionary = GUEST_SPOTS[index]
		var at: Vector3 = spec.position
		if not _guest_space_clear(at): continue
		var guest := GUEST.new()
		guest.name = "LowriderGuest%d" % index
		guest.identity = 1400 + index
		guest.dancer = bool(spec.get("dancer", false))
		guest.host = self
		guest.specification = {"team":"lowrider", "point":at, "walk_end":at, "focus":spec.focus, "coat":Color(str(spec.coat)), "roamer":false, "identity":1400 + index}
		guest.position = at
		var began := STALL_WORK.begin()
		add_child(guest)
		STALL_WORK.finish_slow("lowrider_meet.spawn_guest", began, 4000, self)
		guests[index] = guest
		return

## A cena assada do carro vem de uma carga em segundo plano; o RedesignedFleet depois só lê o cache.
func _scene_ready(model: String) -> bool:
	return _resource_ready(preload("res://runtime/RedesignedFleet.gd").scene_path(model))

## Cena de carro (~1 MB) e faixa de música (2–3 MB) carregam numa thread e ficam retidas aqui.
func _resource_ready(path: String) -> bool:
	if _scene_refs.has(path): return true
	if ResourceLoader.has_cached(path):
		_scene_refs[path] = load(path)
		return true
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)
		return false
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_scene_refs[path] = ResourceLoader.load_threaded_get(path)
		return true
	return false

func _guest_space_clear(point: Vector3) -> bool:
	if session.has_method("position_clear") and not session.position_clear(point): return false
	var shape := CapsuleShape3D.new()
	shape.radius = .34
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point + Vector3.UP * .9
	query.collision_mask = 6
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Desmonta o que é do encontro. Carro que o jogador levou (ou dirige) vira carro comum do mundo.
func _release_population(everything: bool) -> void:
	_stop_music()
	var driving = session.world.get("driving")
	var driven: Node = driving.car if driving != null and driving.get("occupied") else null
	for index in cars.keys():
		var car = cars[index]
		if not is_instance_valid(car):
			cars.erase(index)
			continue
		if not everything and _wanted_car(index): continue
		var moved: bool = car.global_position.distance_to(CAR_SPOTS[index].position) > 4.0
		if car == driven or moved:
			if car.get("hydraulics") != null: car.hydraulics.stop()
		else: car.queue_free()
		cars.erase(index)
	for index in guests.keys():
		var guest = guests[index]
		if is_instance_valid(guest):
			guest.collision_layer = 0
			guest.hide()
			guest.process_mode = Node.PROCESS_MODE_DISABLED
			guest.queue_free()
		guests.erase(index)

func _exit_tree() -> void:
	_stop_music()

# ---------------------------------------------------------------- show

func _show_cars() -> Array:
	var result := []
	var driving = session.world.get("driving")
	var driven: Node = driving.car if driving != null and driving.get("occupied") else null
	for index in cars:
		var car = cars[index]
		if not is_instance_valid(car) or car == driven or car.get("hydraulics") == null or car.health <= 0: continue
		if car.global_position.distance_to(CAR_SPOTS[index].position) > 1.5: continue
		result.append(index)
	return result

## A cada poucos segundos um carro entra na roda; o de pulo pula de verdade e a calçada comemora.
func _update_show() -> void:
	if _show_clock > 0.0: return
	_show_clock = _rng.randf_range(2.2, 4.5)
	var ready := _show_cars()
	if ready.is_empty(): return
	var index: int = ready[_rng.randi_range(0, ready.size() - 1)]
	var car = cars[index]
	var lift: Node = car.hydraulics
	if lift.playing() != "": return
	var show := str(CAR_SPOTS[index].show)
	if show == "hop":
		lift.hop(_rng.randf_range(.70, minf(1.0, record / lift.HOP_HEIGHT + .05)))
		_cheer_near(car.global_position, 2.5)
	else:
		lift.play(show, _rng.randi_range(2, 4))
		if _rng.randf() < .35: _cheer_near(car.global_position, 1.6)

func _cheer_near(point: Vector3, seconds: float) -> void:
	for guest in guests.values():
		if is_instance_valid(guest) and not guest.dead and guest.global_position.distance_to(point) < 9.0: guest.cheer(seconds)

## Usado pelos convidados (DragMeetGuest): recuo só pela calçada, nunca para a pista.
func retreat_clear(_actor: Node, refuge: Vector3) -> bool:
	return refuge.z < 100.0 and refuge.z > 96.0

func alert_crowd(origin: Vector3, radius: float) -> void:
	for guest in guests.values():
		if is_instance_valid(guest) and not guest.dead and guest.global_position.distance_to(origin) < radius: guest.alert(origin)

# ---------------------------------------------------------------- desafio do pulo

func _receipt() -> String:
	return "lowrider_hop_%d" % _night

func _update_challenge() -> void:
	var driving = session.world.get("driving")
	var car: Node = driving.car if driving != null and driving.get("occupied") else null
	var lift: Node = car.get("hydraulics") if is_instance_valid(car) else null
	if not event_active or lift == null or car.global_position.distance_to(CENTER) > CHALLENGE_RADIUS:
		_challenger = null
		return
	if _challenger != car:
		_challenger = car
		lift.reset_best_hop()
		if not _hint_shown:
			_hint_shown = true
			var controls := get_node_or_null("/root/GameInput")
			var key: String = controls.hint("hydraulics") if controls != null and controls.has_method("hint") else "Ctrl"
			var jump: String = controls.hint("handbrake") if controls != null and controls.has_method("hint") else "Espaço"
			session.show_message(String(TranslationServer.translate("Desafio do pulo: segure %s e aperte %s; aperte de novo logo que cair para pular mais alto. Recorde da vila: %.2f m.")) % [key, jump, record])
	if float(lift.best_hop) <= record: return
	var height := float(lift.best_hop)
	record = snappedf(height, .01)
	_cheer_near(CENTER, 3.5)
	if not _rewarded and session.state.economy.grant_reward(_receipt(), HOP_REWARD, "Encontro lowrider"):
		_rewarded = true
		session.show_message(String(TranslationServer.translate("Novo recorde da vila: %.2f m! A quebrada pagou.")) % height)
	else:
		session.show_message(String(TranslationServer.translate("Novo recorde da vila: %.2f m!")) % height)

# ---------------------------------------------------------------- som

func _music_source() -> Vector3:
	for index in cars:
		if bool(CAR_SPOTS[index].get("music", false)) and is_instance_valid(cars[index]): return cars[index].global_position
	return CAR_SPOTS[2].position

func _update_music() -> void:
	var distance := _focus().distance_to(_music_source())
	if distance > MUSIC_RANGE:
		_stop_music()
		return
	if not _ensure_music(): return
	var level := MUSIC_DB + (0.0 if distance <= MUSIC_NEAR else linear_to_db(MUSIC_NEAR / distance)) + linear_to_db(maxf(.001, 1.0 - distance / MUSIC_RANGE))
	_music.volume_db = lerpf(_music.volume_db, level, .2)
	var world_audio := _world_audio()
	if distance < MUSIC_CLAIM and not _claimed and world_audio != null and world_audio.has_method("set_scoped_music_override"):
		_claimed = world_audio.set_scoped_music_override(self)
		if _claimed: _audio_owner = weakref(world_audio)
	elif distance > MUSIC_CLAIM + 6.0 and _claimed: _release_claim()

func _world_audio() -> Node:
	var production: Variant = session.world.get("production")
	var found: Variant = production.get("world_audio") if production != null else null
	return found if found is Node else null

func _ensure_music() -> bool:
	if is_instance_valid(_music): return true
	for path: String in TRACKS:
		if not _resource_ready(path): return false
	var stream := _scene_refs[TRACKS[_track]] as AudioStream
	if stream == null: return false
	_music = AudioStreamPlayer.new()
	_music.name = "LowriderMeetMusic"
	_music.stream = stream
	_music.bus = &"Radio" if AudioServer.get_bus_index(&"Radio") >= 0 else &"Master"
	_music.volume_db = -60.0
	_music.finished.connect(_next_track)
	add_child(_music)
	_music.play(_rng.randf_range(0.0, 40.0))
	return true

func _next_track() -> void:
	_track = (_track + 1) % TRACKS.size()
	if not is_instance_valid(_music): return
	_music.stream = _scene_refs.get(TRACKS[_track]) as AudioStream
	_music.play()

func _stop_music() -> void:
	_release_claim()
	if is_instance_valid(_music):
		_music.stop()
		_music.queue_free()
	_music = null

func _release_claim() -> void:
	if not _claimed: return
	_claimed = false
	var owner: Object = _audio_owner.get_ref() if _audio_owner != null else null
	if is_instance_valid(owner) and owner.has_method("clear_scoped_music_override"): owner.clear_scoped_music_override(self)
