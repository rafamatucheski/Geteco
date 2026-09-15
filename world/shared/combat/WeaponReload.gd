extends RefCounted
## Player and police share magazine capacity and reload timing by weapon.
const CATALOG := preload("res://WeaponCatalog.gd")
const AUDIO := preload("res://audio/reload/ReloadAudioBank.gd")
static var _durations: Dictionary = {}
var weapon_id := ""
var clip := 0
var remaining := 0.0

static func duration(id: String) -> float:
	if int(CATALOG.get_weapon(id).get("magazine_size", -1)) <= 0: return 0.0
	if not _durations.has(id):
		var bank := AUDIO.sound(id) as AudioStreamRandomizer
		var seconds := 0.0
		if bank:
			for i in bank.streams_count:
				seconds = maxf(seconds, bank.get_stream(i).get_length())
		_durations[id] = maxf(0.5, seconds)
	return float(_durations[id])

func equip(id: String) -> void:
	if weapon_id == id: return
	weapon_id = id
	clip = maxi(0, int(CATALOG.get_weapon(id).get("magazine_size", 0)))
	remaining = 0.0

func tick(delta: float) -> void:
	if remaining <= 0.0: return
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0:
		clip = maxi(0, int(CATALOG.get_weapon(weapon_id).get("magazine_size", 0)))

func consume() -> bool:
	if remaining > 0.0 or clip <= 0: return false
	clip -= 1
	if clip == 0: remaining = duration(weapon_id)
	return true
