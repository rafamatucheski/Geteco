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
			var source := load("res://audio/acoustic/engine_%s_%d.wav" % [family, index]) as AudioStreamWAV
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

## Carrega as famílias das viaturas de emergência, uma por quadro, sob a tela de carga.
static func prewarm(tree: SceneTree) -> void:
	if _warming or "--no-prewarm" in OS.get_cmdline_user_args(): return
	_warming = true
	for archetype in PREWARM_ARCHETYPES:
		var family: String = ENGINE_PROFILE.bank_family(archetype)
		if not _banks.has(family): bank(family)
		await tree.process_frame
	# `street` é o recuo das famílias sem áudio próprio.
	if not _banks.has("street"): bank("street")
