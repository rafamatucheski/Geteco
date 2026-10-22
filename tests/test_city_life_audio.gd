extends SceneTree
## Cidade viva em Harbor (audio/city_life/CityLifeAudio.gd) numa sessão de produção de verdade.
## Prova por CONTAGEM E ESTADO, não por ouvido: que perto do jogador há vozes tocando de trânsito,
## passos de pedestre, burburinho/fala e leitos de ambiente; que os tetos de vozes são respeitados
## em todo quadro amostrado; e qual o volume efetivo estimado (fórmula do AudioStreamPlayer3D do
## Godot 4: inverso da distância + rampa do max_distance, sem o filtro de atenuação) medido da
## câmera, que é o ouvinte. Nada disso diz se soa bem: isso precisa de ouvido humano.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_city_life_audio.gd -- --no-save --skip-arrival
## A/B: GETECO_CITY_LIFE_AUDIO=0 roda o mesmo roteiro no modo antigo e só confere a estrutura dele.
const CITY_LIFE := preload("res://audio/city_life/CityLifeAudio.gd")
const NEARBY := preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
const ACTOR := preload("res://scripts/Actor.gd")

var world: Node3D
var session: Node
var audio: Node
var failures: Array[String] = []
var checks := 0
var report: Dictionary = {}
var peaks := {"traffic_voices":0, "traffic_audible":0, "step_voices":0, "walkers":0, "city_life_nodes":0}
var limit_breaks: Array[String] = []

func _initialize() -> void:
	create_timer(840.0).timeout.connect(func(): push_error("CITY_LIFE_AUDIO timeout"); quit(2))
	_run.call_deferred()

func check(ok: bool, label: String, detail := "") -> bool:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label + ((" | " + detail) if detail != "" else ""))
	if not ok:
		failures.append(label)
		push_error(label)
	return ok

func frames(count: int) -> void:
	for _i in count: await physics_frame

func seconds(value: float) -> void:
	await create_timer(value).timeout

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--no-save" in args or not "--skip-arrival" in args:
		push_error("CITY_LIFE_AUDIO recusa rodar sem --no-save --skip-arrival")
		quit(2)
		return
	var city_mode := CITY_LIFE.enabled()
	report["mode"] = "city_life" if city_mode else "legacy"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var started := Time.get_ticks_msec()
	while not (world.session != null and world.session.ready_for_play and world.production.ready_for_play):
		await physics_frame
		if Time.get_ticks_msec() - started > 420000:
			check(false, "sessão de produção inicia")
			_finish()
			return
	session = world.session
	audio = world.production.world_audio
	report["boot_s"] = (Time.get_ticks_msec() - started) / 1000.0
	check(is_instance_valid(audio), "WorldAudio montado na sessão")
	check(str(session.state.region_id) == "harbor" and str(session.state.place_id).is_empty(), "sessão começa no exterior de Harbor", "%s/%s" % [session.state.region_id, session.state.place_id])
	var mixer: Node = audio.vehicle_ambience
	check(is_instance_valid(mixer), "mixer do trânsito existe")
	var city: Node = audio.get("city_life")
	if city_mode:
		check(is_instance_valid(city), "CityLifeAudio montado (interruptor ligado)")
		check(bool(mixer.snapshot().player_relative), "trânsito medido do jogador (interruptor ligado)")
	else:
		check(city == null, "sem CityLifeAudio com GETECO_CITY_LIFE_AUDIO=0")
		check(not bool(mixer.snapshot().player_relative), "trânsito no modo antigo com GETECO_CITY_LIFE_AUDIO=0")
	# A população nasce longe e fora do quadro; dá tempo de ela e o trânsito circularem.
	await _sample(6.0, "settle")

	# ── Trânsito ─────────────────────────────────────────────────────────────
	if int(mixer.snapshot().audible) == 0:
		var car := _nearest_moving_traffic()
		if car != null: await _place_player_beside(car.global_position, 6.0)
	await _sample(5.0, "traffic")
	var traffic: Dictionary = report.get("traffic", {})
	check(int(peaks.traffic_voices) > 0, "motor de trânsito tocando perto do jogador", "pico de vozes=%d audíveis=%d" % [peaks.traffic_voices, peaks.traffic_audible])
	if city_mode:
		check(float(traffic.get("loudest_engine_db", -200.0)) > -45.0, "motor mais próximo com volume efetivo audível (estimativa)", "%.1f dB" % float(traffic.get("loudest_engine_db", -200.0)))

	# ── Leitos de ambiente ──────────────────────────────────────────────────
	var beds: Dictionary = _bed_state()
	report["beds"] = beds
	var profiles := preload("res://audio/v1_ambience/AmbienceProfile.gd")
	report["urban_weight"] = profiles.harbor_urban_weight(world.player.global_position)
	report["coast_weight"] = profiles.harbor_coast_weight(world.player.global_position)
	var bed_playing := 0
	for id in beds:
		if beds[id].playing: bed_playing += 1
	check(bed_playing >= 2, "leitos de ambiente tocando no exterior de Harbor", JSON.stringify(beds))
	if city_mode:
		# Só cobra o leito que o lugar pede (no porto sul o peso urbano cai a zero de propósito).
		for id in ["traffic", "city", "street", "breeze"]:
			if float(audio.bed_targets.get(id, 0.0)) <= 0.05: continue
			check(beds.has(id) and beds[id].playing and float(beds[id].volume_db) > -40.0, "leito '%s' tocando acima de -40 dB" % id, JSON.stringify(beds.get(id, {})))

	# ── Pedestres: passos, burburinho e fala ────────────────────────────────
	var fixtures: Array[Node] = []
	if city_mode:
		fixtures = await _spawn_walkers(12)
		report["fixture_walkers"] = fixtures.size()
		# Força tentativas de fala (o intervalo normal é 9–20 s) para não depender da sorte.
		var spoke := false
		var tries := 0
		var began := Time.get_ticks_msec()
		while Time.get_ticks_msec() - began < 12000:
			if not spoke and not city._chatter.playing:
				city._chatter_clock = 0.0
				tries += 1
			await _sample(0.5, "pedestrians", false)
			spoke = spoke or city.snapshot().chatter_played > 0
		var life: Dictionary = city.snapshot()
		report["city_life"] = life
		check(int(life.steps_played) > 0, "passos de pedestre tocaram", "passos=%d descartados=%d" % [life.steps_played, life.steps_dropped])
		check(int(peaks.step_voices) <= CITY_LIFE.STEP_VOICES, "teto de vozes de passo respeitado", "pico=%d teto=%d" % [peaks.step_voices, CITY_LIFE.STEP_VOICES])
		check(int(peaks.walkers) <= CITY_LIFE.MAX_WALKERS, "teto de pedestres seguidos respeitado", "pico=%d teto=%d" % [peaks.walkers, CITY_LIFE.MAX_WALKERS])
		check(int(peaks.city_life_nodes) == CITY_LIFE.STEP_VOICES + 2, "CityLifeAudio nunca cria voz nova", "nós=%d" % peaks.city_life_nodes)
		check(bool(report.get("murmur_seen", false)), "burburinho tocou perto do grupo")
		var language := str(root.get_node("V2Settings").voice_language) if root.has_node("V2Settings") else "pt_BR"
		var available := int(life.chatter_lines.get(preload("res://audio/DirectedVoiceBank.gd").language(language), 0))
		report["chatter_language"] = language
		report["chatter_tries"] = tries
		if available > 0:
			check(spoke, "fala curta de civil tocou num pedestre próximo", "idioma=%s falas=%d tentativas=%d" % [language, available, tries])
		else:
			print("CASE SKIP fala curta: nenhuma gravação neutra no idioma ", language)
		for actor in fixtures:
			if is_instance_valid(actor):
				world.people.erase(actor)
				actor.queue_free()
	check(int(peaks.traffic_audible) <= NEARBY.MAX_AUDIBLE, "teto de 6 carros audíveis respeitado", "pico=%d" % peaks.traffic_audible)
	check(limit_breaks.is_empty(), "nenhum quadro amostrado passou de um teto", ", ".join(limit_breaks.slice(0, 6)))
	if city_mode:
		report["select_cost_us_debug"] = _time_selection(city)
	report["census_last"] = _census()
	_finish()

func _finish() -> void:
	report["peaks"] = peaks
	report["checks"] = checks
	report["failures"] = failures
	print("CITY_LIFE_AUDIO_REPORT ", JSON.stringify(report))
	print("CITY_LIFE_AUDIO mode=%s checks=%d failures=%d" % [report.get("mode", "?"), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## Amostra a cada quadro: tetos e a maior contagem por categoria; guarda o retrato do fim.
func _sample(duration: float, label: String, store := true) -> void:
	var began := Time.get_ticks_msec()
	var loudest := -200.0
	var loudest_distance := -1.0
	var by_category: Dictionary = {}
	var mixer: Node = audio.vehicle_ambience
	var city: Node = audio.get("city_life")
	var frame := 0
	while Time.get_ticks_msec() - began < int(duration * 1000.0):
		await process_frame
		frame += 1
		var traffic: Dictionary = mixer.snapshot()
		peaks.traffic_voices = maxi(peaks.traffic_voices, int(traffic.playing_voices))
		peaks.traffic_audible = maxi(peaks.traffic_audible, int(traffic.audible))
		if int(traffic.playing_voices) > int(traffic.voice_limit): limit_breaks.append("%s: trânsito %d>%d" % [label, traffic.playing_voices, traffic.voice_limit])
		if int(traffic.audible) > NEARBY.MAX_AUDIBLE: limit_breaks.append("%s: carros %d" % [label, traffic.audible])
		for voice in mixer.find_children("*", "AudioStreamPlayer3D", true, false):
			if not voice.playing or voice.stream == null: continue
			var estimate := _effective_db(voice)
			if estimate > loudest:
				loudest = estimate
				var car_distance := INF
				for id in traffic.audible_ids:
					var car := instance_from_id(id) as Node3D
					if car != null: car_distance = minf(car_distance, Vector2(car.global_position.x - world.player.global_position.x, car.global_position.z - world.player.global_position.z).length())
				loudest_distance = car_distance
		if is_instance_valid(city):
			var life: Dictionary = city.snapshot()
			peaks.step_voices = maxi(peaks.step_voices, int(life.step_voices_playing))
			peaks.walkers = maxi(peaks.walkers, int(life.walkers))
			peaks.city_life_nodes = maxi(peaks.city_life_nodes, city.find_children("*", "AudioStreamPlayer3D", true, false).size())
			if int(life.step_voices_playing) > CITY_LIFE.STEP_VOICES: limit_breaks.append("%s: passos %d" % [label, life.step_voices_playing])
			if int(life.walkers) > CITY_LIFE.MAX_WALKERS: limit_breaks.append("%s: pedestres %d" % [label, life.walkers])
			if life.murmur_playing: report["murmur_seen"] = true
		# A varredura da árvore inteira é cara; a cada 12 quadros basta para o pico por categoria.
		if frame % 12 != 0: continue
		var census := _census()
		for category in census.by_category:
			by_category[category] = maxi(int(by_category.get(category, 0)), int(census.by_category[category]))
	if store:
		report[label] = {"loudest_engine_db": loudest, "loudest_engine_car_m": loudest_distance,
			"peak_playing_by_category": by_category, "census": _census(), "traffic": mixer.snapshot()}
		print("CITY_LIFE_AUDIO %s %s" % [label, JSON.stringify(report[label])])

## Volume efetivo estimado na câmera (ouvinte), em dB antes do bus. ATTENUATION_DISABLED com
## max_distance 0 é o próprio volume_db (a perda por distância já está nele).
func _effective_db(voice: AudioStreamPlayer3D) -> float:
	var db := voice.volume_db
	if voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED and voice.max_distance <= 0.0: return db
	var camera: Camera3D = world.camera
	var distance := voice.global_position.distance_to(camera.global_position) if camera != null else 0.0
	if voice.max_distance > 0.0 and distance > voice.max_distance: return -200.0
	match voice.attenuation_model:
		AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE: db += linear_to_db(1.0 / (distance / voice.unit_size + 0.00001))
		AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE: db += linear_to_db(1.0 / pow(distance / voice.unit_size + 0.00001, 2.0))
		AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC: db += -20.0 * log(distance / voice.unit_size + 0.00001) / log(10.0)
	db = minf(db, voice.max_db)
	if voice.max_distance > 0.0: db += linear_to_db(maxf(0.00001, 1.0 - distance / voice.max_distance))
	return db

## Vozes tocando agora, por bus e por categoria (pelo dono do nó).
func _census() -> Dictionary:
	var by_bus: Dictionary = {}
	var by_category: Dictionary = {}
	var nodes: Array[Node] = root.find_children("*", "AudioStreamPlayer", true, false)
	nodes.append_array(root.find_children("*", "AudioStreamPlayer3D", true, false))
	for node in nodes:
		if not node.playing or node.stream == null: continue
		var bus := str(node.bus)
		by_bus[bus] = int(by_bus.get(bus, 0)) + 1
		var category := _category(node)
		by_category[category] = int(by_category.get(category, 0)) + 1
	return {"by_bus": by_bus, "by_category": by_category}

func _category(node: Node) -> String:
	var label := str(node.name)
	if label.begins_with("PedestrianStep"): return "pedestrian_step"
	if label == "StreetMurmur": return "murmur"
	if label == "StreetChatter": return "chatter"
	if label == "NearbyV1Detail": return "ambient_detail"
	if label == "ActorDialogueVoice": return "dialogue"
	var parent := node.get_parent()
	while parent != null:
		var owner_name := str(parent.name)
		if owner_name == "NearbyVehicleAudio": return "traffic_engine"
		if parent == audio:
			return "ambient_bed" if label.ends_with("Ambience") else "world_audio_other"
		parent = parent.get_parent()
	return "other"

func _bed_state() -> Dictionary:
	var result: Dictionary = {}
	for id in audio.beds:
		var player: AudioStreamPlayer = audio.beds[id]
		result[id] = {"playing": player.playing, "volume_db": snappedf(player.volume_db, 0.1), "gain": snappedf(float(audio.bed_gains.get(id, 0.0)), 0.001)}
	return result

func _nearest_moving_traffic() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for car in world.production.vehicles:
		if not is_instance_valid(car) or not car.traffic or car.health <= 0.0 or absf(float(car.speed)) < 1.0: continue
		var distance: float = car.global_position.distance_to(world.player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = car
	return best

func _place_player_beside(point: Vector3, radius: float) -> void:
	for step in 16:
		var angle := TAU * step / 16.0
		var candidate := point + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var space := world.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 3.0, candidate - Vector3.UP * 3.0, 1))
		if hit.is_empty(): continue
		candidate.y = hit.position.y + 0.08
		if not session.position_clear(candidate): continue
		world.production.region.set_focus(candidate)
		world.player.teleport(candidate)
		await frames(6)
		report["player_moved_to_traffic"] = candidate
		return

## Pedestres de teste andando em volta do jogador (rota curta em calçada livre), para que os
## tetos sejam postos à prova com mais gente do que vozes.
func _spawn_walkers(count: int) -> Array[Node]:
	var spawned: Array[Node] = []
	var origin: Vector3 = world.player.global_position
	var space := world.get_world_3d().direct_space_state
	var attempt := 0
	while spawned.size() < count and attempt < count * 6:
		attempt += 1
		var angle := TAU * float(attempt) / 7.3
		var radius := 2.0 + float(attempt % 5)
		var start := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var heading := Vector3(cos(angle + PI * 0.5), 0.0, sin(angle + PI * 0.5))
		var route := PackedVector3Array()
		for point in [start, start + heading * 5.0]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point - Vector3.UP * 2.0, 1))
			if hit.is_empty(): break
			var grounded := Vector3(point.x, hit.position.y + 0.08, point.z)
			if not session.position_clear(grounded): break
			route.append(grounded)
		if route.size() < 2: continue
		var actor = ACTOR.new()
		actor.identity = 9100 + attempt
		actor.position = route[0]
		actor.speed = 1.4
		actor.route = route
		actor.set_meta("region_id", "harbor")
		world.add_child(actor)
		world.people.append(actor)
		spawned.append(actor)
	await frames(10)
	return spawned

## Custo da seleção (0,2 s) no binário do editor: só ordem de grandeza, não vale como release.
func _time_selection(city: Node) -> float:
	var began := Time.get_ticks_usec()
	for _i in 50: city._select()
	return (Time.get_ticks_usec() - began) / 50.0
