extends Control
## Two flat image layers; no world, shaders or offscreen viewport of its own.
const ART: Array[Texture2D] = [
	preload("res://ui/art/loading/ink/garage.png"),
	preload("res://ui/art/loading/ink/lighthouse.png"),
	preload("res://ui/art/loading/ink/port.png"),
	preload("res://ui/art/loading/ink/mountain.png"),
	preload("res://ui/art/loading/ink/cargo.png"),
	preload("res://ui/art/loading/ink/lookout.png"),
	preload("res://ui/art/loading/ink/ridge.png"),
	preload("res://ui/art/loading/ink/desert_highway.png"),
	preload("res://ui/art/loading/ink/desert_canyon.png"),
	preload("res://ui/art/loading/ink/desert_village.png"),
	preload("res://ui/art/loading/ink/drag_race.png"),
	preload("res://ui/art/loading/ink/motocross.png"),
	preload("res://ui/art/loading/ink/fishing.png"),
	preload("res://ui/art/loading/ink/amusement_park.png"),
	preload("res://ui/art/loading/ink/arcade.png"),
]
const HOLD_SECONDS := 6.0
const FADE_SECONDS := 1.0
var first_index := -1
var current_index := 0
var transitions := 0
var _order: Array[int] = []
var _position := 0
var _elapsed := 0.0
var _front: TextureRect
var _incoming: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	# Local RNG does not change the world's procedural/random gameplay sequence.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in ART.size(): _order.append(i)
	for i in range(_order.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var previous := _order[i]
		_order[i] = _order[other]
		_order[other] = previous
	if first_index >= 0:
		var wanted := _order.find(posmod(first_index, ART.size()))
		var previous := _order[0]
		_order[0] = _order[wanted]
		_order[wanted] = previous
	current_index = _order[0]
	_front = _image()
	_incoming = _image()
	_front.texture = ART[current_index]
	_incoming.hide()

func _image() -> TextureRect:
	var result := TextureRect.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func _process(delta: float) -> void:
	# A synchronous world-build stall must not skip several pictures or flash a cut.
	_elapsed += minf(delta, .1)
	if _elapsed < HOLD_SECONDS: return
	if not _incoming.visible:
		_incoming.texture = ART[_order[(_position + 1) % _order.size()]]
		_incoming.modulate.a = 0.0
		_incoming.show()
	var blend := clampf((_elapsed - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)
	_incoming.modulate.a = blend * blend * (3.0 - 2.0 * blend)
	if blend >= 1.0:
		_position = (_position + 1) % _order.size()
		current_index = _order[_position]
		_front.texture = _incoming.texture
		_incoming.hide()
		_elapsed = 0.0
		transitions += 1
