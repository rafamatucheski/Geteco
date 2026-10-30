extends RefCounted
## Foley editado offline; seleção de tomadas sem repetição imediata por evento.
## O áudio é reproduzido pelo pool de Gameplay, nunca por players criados no golpe.
const LOADER := preload("res://audio/export_compat/ImportedAudioLoader.gd")
const WEAPONS := ["knife", "bat", "katana", "axe"]
const TAKES := 4
var _last: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func _take(key: String, count: int = TAKES) -> int:
	var previous := int(_last.get(key, -1))
	var take := _rng.randi_range(0, count - 1 if previous < 0 else count - 2)
	if previous >= 0 and take >= previous: take += 1
	_last[key] = take
	return take

func _clip(event: String) -> AudioStreamWAV:
	return LOADER.wav("res://audio/melee_foley/%s_%d.wav" % [event, _take(event)])

func swing(weapon: String) -> AudioStreamWAV:
	if weapon not in WEAPONS: return null
	return _clip(weapon + "_swing")

func hit(weapon: String, material: String, heavy: bool = false, severed: bool = false) -> AudioStreamWAV:
	if material != "flesh":
		var surface := material if material in ["wood", "metal", "glass"] else "concrete"
		var event := "impact_" + surface
		return LOADER.wav("res://assets/gameplay/audio/%s_%d.wav" % [event, _take(event, 3)])
	if weapon not in WEAPONS: return null
	var event := weapon + ("_sever" if severed and weapon in ["katana", "axe"] else ("_heavy" if heavy else "_hit"))
	return _clip(event)

func landing() -> AudioStreamWAV:
	return _clip("landing")

static func prewarm() -> void:
	for weapon: String in WEAPONS:
		for event: String in ["swing", "hit", "heavy"]:
			for take in TAKES: LOADER.wav("res://audio/melee_foley/%s_%s_%d.wav" % [weapon, event, take])
	for weapon: String in ["katana", "axe"]:
		for take in TAKES: LOADER.wav("res://audio/melee_foley/%s_sever_%d.wav" % [weapon, take])
	for take in TAKES: LOADER.wav("res://audio/melee_foley/landing_%d.wav" % take)
