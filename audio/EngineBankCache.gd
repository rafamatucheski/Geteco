extends RefCounted
## Banco de 7 camadas de motor por família, compartilhado por NearbyVehicleAudio e
## ServiceVehicleAudio. Cada um carregava (load + duplicate de 7 WAV) de forma síncrona
## na 1ª vez que uma família aparecia: fire_diesel 74 ms, police 23 ms, ambulance 15 ms,
## street 10 ms (medido em tests/measure/probe_first_emergency.gd --action=bank), o que
## travava o quadro em que a 1ª viatura de emergência entrava no raio de áudio.
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const TANK_AUDIO := preload("res://audio/tank/TankAudio.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Viaturas do despacho (DispatchRules.ARCHETYPES) e resposta policial.
const PREWARM_ARCHETYPES := ["police_cruiser", "police_transport", "bike_police", "army_tank", "medic_box", "rescue_pumper", "station_wagon"]
static var _banks: Dictionary = {}
static var _warming := false
## Ligado pelo `prewarm` (o jogo): a partir daí `bank` nunca faz leitura síncrona.
static var _streaming := false

## Família existe no disco com as 7 camadas.
static func has_bank(family: String) -> bool:
	if family == "tank": return TANK_AUDIO.engine_bank().size() == 7
	for index in 7:
		if not ResourceLoader.exists("res://audio/acoustic/engine_%s_%d.wav" % [family, index]): return false
	return true

## Sete camadas prontas para tocar em loop, ou vazio se a família não existe. Em cache.
## Durante o jogo (depois de `prewarm`) nunca espera: se os WAV ainda estão sendo lidos em
## segundo plano, devolve vazio sem guardar e quem chama usa `bridge_family` até a certa ficar
## pronta. `load_threaded_get` com a carga em andamento bloqueia o quadro até ela terminar.
static func bank(family: String) -> Array[AudioStreamWAV]:
	if _banks.has(family): return _banks[family]
	var result: Array[AudioStreamWAV] = []
	if family == "tank":
		result = TANK_AUDIO.engine_bank()
	elif has_bank(family):
		if _streaming and not _family_ready(family):
			if _family_failed(family):
				# Leitura falhou: guarda vazio para não pedir de novo a cada quadro; quem chama
				# fica na ponte, como já fazia com família sem banco.
				push_warning("EngineBankCache: falha ao ler o banco de motor '%s'" % family)
				_banks[family] = result
			else:
				_request_family(family)
			return result
		var began := STALL_WORK.begin()
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
		STALL_WORK.finish_slow("audio.engine_bank", began, 2000)
	_banks[family] = result
	return result

## Banco já montado ou com as 7 leituras concluídas (montar custa só as cópias). Não espera.
static func is_ready(family: String) -> bool:
	return bank(family).size() == 7

## Família que pode tocar agora no lugar de `family`: ela mesma se pronta, senão `street`
## (a primeira do prewarm depois das viaturas) como ponte, senão "" (silêncio até ficar pronta).
static func bridge_family(family: String) -> String:
	if is_ready(family): return family
	if family != "street" and is_ready("street"): return "street"
	return ""

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

## Lê o WAV. Em jogo `bank` só chega aqui com a leitura concluída (THREAD_LOAD_LOADED), então
## `load_threaded_get` não espera. Fora do jogo (testes e ferramentas que não chamam `prewarm`)
## cai no `load` síncrono, medido pelo span "audio.engine_bank".
## Cada família custava 60-130 ms de `load` síncrono no quadro em que aparecia (17 famílias,
## 1,4 s no total): o pico de ~1 s do começo do jogo e uma parada a cada modelo novo de carro.
static func _fetch(path: String) -> Resource:
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path)
	return load(path)

static func _family_ready(family: String) -> bool:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED: return false
	return true

static func _family_failed(family: String) -> bool:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_FAILED: return true
	return false

static func _request_family(family: String) -> void:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		# Só pede o que ainda não está em leitura: `bank` repete o pedido a cada quadro em que
		# a família falta.
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: continue
		if ResourceLoader.exists(path): ResourceLoader.load_threaded_request(path)

static func _family_loaded(family: String) -> bool:
	for index in 7:
		var path := "res://audio/acoustic/engine_%s_%d.wav" % [family, index]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	return true

## Todas as famílias: a leitura dos WAV corre em segundo plano e cada banco é montado (cópia
## dos 7 fluxos) num quadro, com prioridade para as viaturas de emergência e `street`.
static func prewarm(tree: SceneTree) -> void:
	# Mesmo com --no-prewarm o jogo não pode ler WAV no quadro: a família pedida carrega
	# em segundo plano e a ponte toca enquanto isso.
	_streaming = true
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
