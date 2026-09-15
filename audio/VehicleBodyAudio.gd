extends RefCounted
## Original offline-generated body Foley: low thump, wet slap, short debris tail.
## Preloaded takes avoid synthesis during a collision.
const TAKES := [
	preload("res://audio/vehicle_body/body_0.wav"),
	preload("res://audio/vehicle_body/body_1.wav"),
	preload("res://audio/vehicle_body/body_2.wav"),
]
static var _take := 0

static func sound() -> AudioStreamWAV:
	_take = (_take + randi_range(1, 2)) % TAKES.size()
	return TAKES[_take]
