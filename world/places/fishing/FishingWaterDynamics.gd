extends RefCounted
## Campo de altura de águas rasas: grade limitada, passo de tempo fixo, equação de onda amortecida.
## Altura/normais renderizadas e flutuação leem o mesmo campo. Nenhum corpo rígido por gota.
const SIZE := Vector2i(48, 32)
const ORIGIN := Vector2(-30, -24)
const EXTENT := Vector2(60, 40)
const STEP := 1.0 / 30.0
const MAX_PENDING := 128
var heights := PackedFloat32Array()
var velocities := PackedFloat32Array()
var _next := PackedFloat32Array()
var _wet := PackedByteArray()
var _pending: Array[Vector4] = []
var _accumulator := 0.0
var _remaining := 0.0
var texture: ImageTexture
var impact_count := 0
var active := false

func _init(polygon: PackedVector2Array) -> void:
	var count := SIZE.x * SIZE.y
	heights.resize(count)
	velocities.resize(count)
	_next.resize(count)
	_wet.resize(count)
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var point := ORIGIN + Vector2(x, y) / Vector2(SIZE - Vector2i.ONE) * EXTENT
			_wet[y * SIZE.x + x] = int(Geometry2D.is_point_in_polygon(point, polygon))
	texture = ImageTexture.create_from_image(_image())

func _image() -> Image:
	return Image.create_from_data(SIZE.x, SIZE.y, false, Image.FORMAT_RF, heights.to_byte_array())

func impact(point: Vector2, strength: float, delay: float) -> void:
	if _pending.size() >= MAX_PENDING or strength <= 0.0: return
	_pending.append(Vector4(point.x, point.y, clampf(strength, 0, 1), maxf(0, delay)))
	active = true

func update(delta: float) -> void:
	if not active: return
	# A slow frame never causes an unbounded catch-up loop.
	_accumulator = minf(_accumulator + delta, STEP * 3.0)
	var changed := false
	while _accumulator >= STEP:
		_accumulator -= STEP
		for i in range(_pending.size() - 1, -1, -1):
			_pending[i].w -= STEP
			if _pending[i].w <= 0.0:
				_apply_impact(_pending[i])
				_pending.remove_at(i)
		if _remaining > 0.0:
			_step()
			_remaining -= STEP
			changed = true
		elif _pending.is_empty():
			heights.fill(0)
			velocities.fill(0)
			active = false
			changed = true
			break
	if changed: texture.update(_image())

func _apply_impact(drop: Vector4) -> void:
	var cell := (Vector2(drop.x, drop.y) - ORIGIN) / EXTENT * Vector2(SIZE - Vector2i.ONE)
	var center := Vector2i(cell.round())
	for y in range(maxi(1, center.y - 1), mini(SIZE.y - 1, center.y + 2)):
		for x in range(maxi(1, center.x - 1), mini(SIZE.x - 1, center.x + 2)):
			var index := y * SIZE.x + x
			if _wet[index] == 0: continue
			var distance := Vector2(x, y).distance_squared_to(cell)
			velocities[index] -= .32 * drop.z * exp(-distance * 2.3)
	_remaining = 8.0
	impact_count += 1

func _step() -> void:
	# c = 3.2 m/s, spacing ~1.28 m. CFL remains below .12 at 30 Hz.
	var spacing := EXTENT / Vector2(SIZE - Vector2i.ONE)
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var i := y * SIZE.x + x
			if _wet[i] == 0: continue
			var h := heights[i]
			var lap := (heights[i - 1] + heights[i + 1] - 2 * h) / (spacing.x * spacing.x)
			lap += (heights[i - SIZE.x] + heights[i + SIZE.x] - 2 * h) / (spacing.y * spacing.y)
			velocities[i] += (10.24 * lap - 2.2 * velocities[i] - .5 * h) * STEP
			_next[i] = clampf(h + velocities[i] * STEP, -.035, .035)
	var old := heights
	heights = _next
	_next = old

func height_at(point: Vector2) -> float:
	var cell := (point - ORIGIN) / EXTENT * Vector2(SIZE - Vector2i.ONE)
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE.x - 1 or cell.y >= SIZE.y - 1: return 0.0
	var x := floori(cell.x)
	var y := floori(cell.y)
	var i := y * SIZE.x + x
	return lerpf(lerpf(heights[i], heights[i + 1], cell.x - x), lerpf(heights[i + SIZE.x], heights[i + SIZE.x + 1], cell.x - x), cell.y - y)
