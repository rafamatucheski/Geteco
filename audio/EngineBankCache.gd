extends RefCounted
## Banco de 7 camadas de motor por família, compartilhado por NearbyVehicleAudio e
## ServiceVehicleAudio. Cada um carregava (load + duplicate de 7 WAV) de forma síncrona
## na 1ª vez que uma família aparecia: fire_diesel 74 ms, police 23 ms, ambulance 15 ms,
## street 10 ms (medido em tests/measure/probe_first_emergency.gd --action=bank), o que
## travava o quadro em que a 1ª viatura de emergência entrava no raio de áudio.
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
## Viaturas do despacho (DispatchRules.ARCHETYPES) e resposta policial.
const PREWARM_ARCHETYPES := ["police_cruiser", "police_transport", "bike_police", "army_tank", "medic_box", "rescue_pumper", "station_wagon"]
static var _banks: Dictionary = {}
static var _warming := false

## Família existe no disco com as 7 camadas.
static func has_bank(family: String) -> bool:
	if family == "tank": return TANK_AUDIO.engine_bank().size() == 7
	for index in 7:
		if not ResourceLoader.exists("res://audio/acoustic/engine_%s_%d.wav" % [family, index]): return false
	return true

## Sete camadas prontas para tocar em loop, ou vazio se a família não existe. Em cache.
static func bank(family: String) -> Array[AudioStreamWAV]:
	if _banks.has(family): return _banks[family]
	var result: Array[AudioStreamWAV] = []
	if family == "tank":
		result = TANK_AUDIO.engine_bank()
	elif has_bank(family):
		for index in 7:
			var source := _fetch("res://audio/acoustic/engine_%s_%d.wav" % [family, index]) as AudioStreamWAV
			if source == null:
				result.clear()
				break
			var stream := source.duplicate() as AudioStreamWAV
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
			result.append(stream)
	_banks[family] = result
	return result

## Famílias com as 7 camadas no disco.
static func all_families() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("res://audio/acoustic")
	if dir == null: return result
	for file in dir.get_files():
		if file.begins_with("engine_") and file.ends_with("_0.wav"):
			var family := file.trim_prefix("engine_").trim_suffix("_0.wav")
			if has_bank(family): result.append(family)
	return result

## Lê o WAV: se já foi pedido em segundo plano, espera só o que faltar; senão, carrega agora.
## Cada família custava 60-130 ms de `load` síncrono no quadro em que aparecia (17 famílias,
## 1,4 s no total): o pico de ~1 s do começo do jogo e uma parada a cada modelo novo de carro.
static func _fetch(path: String) -> Resource:
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return ResourceLoader.load_threaded_get(path)
	return load(path)

static func _request_family(family: String) -> void:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if ResourceLoader.exists(path): ResourceLoader.load_threaded_request(path)

static func _family_loaded(family: String) -> bool:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	return true

## Todas as famílias: a leitura dos WAV corre em segundo plano e cada banco é montado (cópia
## dos 7 fluxos) num quadro, com prioridade para as viaturas de emergência e `street`.
static func prewarm(tree: SceneTree) -> void:
	if _warming or "--no-prewarm" in OS.get_cmdline_user_args(): return
	_warming = true
	var order: Array[String] = []
	for archetype in PREWARM_ARCHETYPES:
		var family: String = ENGINE_PROFILE.bank_family(archetype)
		if family not in order: order.append(family)
	if "street" not in order: order.append("street")
	for family in all_families():
		if family not in order: order.append(family)
	for family in order: if has_bank(family) and not _banks.has(family): _request_family(family)
	for family in order:
		if _banks.has(family): continue
		var waited := 0
		while not _family_loaded(family) and waited < 600:
			await tree.process_frame
			waited += 1
		bank(family)
		await tree.process_frame
