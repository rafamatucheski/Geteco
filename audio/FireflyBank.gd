extends RefCounted
## Banco dos sons gerados no Adobe Firefly em 2026-10-15 (armas, veículos, ambiente).
## Os arquivos passaram por tratamento (mono, corte de silêncio, fade, volume casado com o
## que o jogo já tinha, loops sem emenda); os originais ficam em evidence/ fora do Git.
## Tudo aqui é opcional: se um arquivo ainda não foi importado a função devolve nulo e
## quem chama segue com o som que já existia, então o jogo nunca fica mudo por isso.
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const ROOT := "res://audio/"
const SFX_BUS := &"SFX"
## Famílias de motor sem partida de motor de combustão.
const NO_CRANK := ["electric", "tank"]
const HEAVY := ["truck", "bus", "fire_diesel", "tank"]
static var _streams: Dictionary = {}
static var _counts: Dictionary = {}
static var _last: Dictionary = {}
static var _loops: Dictionary = {}

static func stream(folder: String, key: String, index: int) -> AudioStream:
	var path := "%s%s/%s_%d.wav" % [ROOT, folder, key, index]
	if _streams.has(path): return _streams[path]
	var loaded: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[path] = loaded
	return loaded

## Quantas tomadas existem de `key` (0..n-1 sem buracos). Tomadas fracas foram descartadas
## no tratamento, então o número varia por som.
static func count(folder: String, key: String) -> int:
	var id := folder + "/" + key
	if _counts.has(id): return _counts[id]
	var total := 0
	while ResourceLoader.exists("%s%s/%s_%d.wav" % [ROOT, folder, key, total]): total += 1
	_counts[id] = total
	return total

## Tomada aleatória sem repetir a anterior do mesmo som. Nulo se não existir.
static func take(folder: String, key: String, rng: RandomNumberGenerator = null) -> AudioStream:
	var total := count(folder, key)
	if total == 0: return null
	var index := rng.randi_range(0, total - 1) if rng != null else randi() % total
	var id := folder + "/" + key
	if total > 1 and int(_last.get(id, -1)) == index: index = (index + 1) % total
	_last[id] = index
	return stream(folder, key, index)

## Todas as tomadas de `key` (para listas cíclicas como as do turbo).
static func all(folder: String, key: String) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for index in count(folder, key):
		var item := stream(folder, key, index)
		if item != null: result.append(item)
	return result

## Arquivo tratado para repetir sem emenda (sirene, bipe de ré, compressor, vento).
static func loop(folder: String, file: String) -> AudioStreamWAV:
	var path := ROOT + folder + "/" + file
	if _loops.has(path): return _loops[path]
	var source: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	var looped: AudioStreamWAV = null
	if source != null:
		looped = source.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = maxi(1, roundi(source.get_length() * source.mix_rate) - 8)
	_loops[path] = looped
	return looped

## Carrega agora, sob a tela de carregamento, o que o jogo toca no meio da ação: assim o
## primeiro tiro, a primeira porta e o primeiro turbo não pagam leitura de disco.
static func prewarm(tree: SceneTree) -> void:
	var sets := {
		"weapons_fire": ["pistol", "shotgun", "rifle_shot", "magnum", "smg", "sawed_off", "hunting_rifle", "distant_shot", "dry_fire", "gun_draw", "gun_holster",
			"grenade_pin", "explosion_tail", "ricochet", "bullet_whiz"],
		"katana": ["draw", "sheath"],
		"vehicle_fx": ["door_open", "door_close", "ignition", "engine_off", "handbrake", "backfire",
			"car_horn", "wastegate", "turbo_flutter", "turbo_spool", "turbo_spooldown", "diesel_turbo"],
		"service_vehicles": ["horn"],
	}
	for folder in sets:
		for key in sets[folder]: all(folder, key)
		await tree.process_frame
	loop("service_vehicles", "siren_loop.wav")
	loop("service_vehicles", "reverse_beep_loop.wav")
	loop("vehicle_fx", "supercharger_loop.wav")
	loop("weapons_fire", "rocket_flight_loop.wav")

static func bus_name() -> StringName:
	return SFX_BUS if AudioServer.get_bus_index(SFX_BUS) >= 0 else &"Master"

## Toca uma vez, com a posição do mundo, e some sozinho. `parent` é quem carrega o som
## (o veículo): se ele sair da árvore o som sai junto.
static func play_at(parent: Node, audio: AudioStream, world_point: Vector3, volume_db: float, pitch := 1.0, max_distance := 35.0, unit_size := 8.0) -> AudioStreamPlayer3D:
	if audio == null or not is_instance_valid(parent) or not parent.is_inside_tree(): return null
	var voice := AudioStreamPlayer3D.new()
	voice.stream = audio
	voice.bus = bus_name()
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.unit_size = unit_size
	voice.max_distance = max_distance
	parent.add_child(voice)
	voice.global_position = world_point
	voice.finished.connect(voice.queue_free)
	voice.play()
	return voice

static func _family(vehicle: Node) -> String:
	return ENGINE_PROFILE.family(str(vehicle.get("archetype")))

## Porta do motorista abrindo/fechando, no mesmo instante da animação da folha.
static func door(vehicle: Node3D, side: int, opened: bool) -> void:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): return
	var key := "firefly_door_open_left" if side < 0 else "firefly_door_open_right"
	if vehicle.has_meta(key) and bool(vehicle.get_meta(key)) == opened: return
	vehicle.set_meta(key, opened)
	var family := _family(vehicle)
	var point: Vector3 = vehicle.driver_door_anchor(side) if vehicle.has_method("driver_door_anchor") else vehicle.global_position
	var heavy := family in HEAVY
	# Porta de caminhão é mais pesada: mais grave e um pouco mais alta.
	var pitch := (0.82 if heavy else randf_range(0.96, 1.05))
	play_at(vehicle, take("vehicle_fx", "door_open" if opened else "door_close"), point, -5.0 if heavy else -8.0, pitch, 30.0)

## Motor pegando quando o jogador termina de sentar.
static func ignition(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle): return
	var family := _family(vehicle)
	if family in NO_CRANK: return
	if bool(vehicle.get("engine_disabled")): return
	var pitch := 0.88 if family in HEAVY else (1.06 if family.begins_with("bike") or family in ["sport", "vq35", "rosso_v12"] else 1.0)
	play_at(vehicle, take("vehicle_fx", "ignition"), vehicle.global_position, -7.0, pitch * randf_range(0.98, 1.02), 35.0)

## Motor morrendo quando o jogador começa a descer.
static func engine_off(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle): return
	var family := _family(vehicle)
	if family in NO_CRANK: return
	var pitch := 0.88 if family in HEAVY else 1.0
	play_at(vehicle, take("vehicle_fx", "engine_off"), vehicle.global_position, -9.0, pitch * randf_range(0.98, 1.02), 30.0)

## Puxada do freio de mão; no máximo uma por 0,45 s por veículo.
static func handbrake(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): return
	var now := Time.get_ticks_msec()
	if now - int(vehicle.get_meta("firefly_handbrake_msec", -10000)) < 450: return
	vehicle.set_meta("firefly_handbrake_msec", now)
	play_at(vehicle, take("vehicle_fx", "handbrake"), vehicle.global_position, -11.0, randf_range(0.97, 1.04), 24.0)
