extends RefCounted
## Seven-bag falling blocks with wall kicks, landing preview and a finite board.

const WIDTH := 10
const HEIGHT := 18
const SHAPES := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
]
const COLORS := [Color("54dcea"), Color("f8d574"), Color("bd86e9"), Color("7bdda1"), Color("ef788d"), Color("689de8"), Color("f3a36c")]
var score: int = 0
var finished: bool = false
var status: String = ""
var board: Array[PackedInt32Array] = []
var piece: int = 0
var next_piece: int = 0
var rotation: int = 0
var origin := Vector2i(3, -1)
var lines: int = 0
var sound_events: Array[String] = []
var _bag: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _fall_timer: float = 0.0
var _repeat_timer: float = 0.0
var _held_direction: int = 0

func title() -> String:
	return "Blocos"

func instructions() -> String:
	return "← → mover  •  ↑ / Ação: girar  •  ↓ descer  •  Alternativa: soltar"

func reset(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	score = 0
	lines = 0
	sound_events.clear()
	finished = false
	board.clear()
	_bag.clear()
	for y in range(HEIGHT):
		var row := PackedInt32Array()
		row.resize(WIDTH)
		board.append(row)
	_fall_timer = 0.0
	_repeat_timer = 0.0
	_held_direction = 0
	next_piece = _take_piece()
	_spawn()

func _take_piece() -> int:
	if _bag.is_empty():
		_bag.assign([0, 1, 2, 3, 4, 5, 6])
		for i in range(6, 0, -1):
			var j := _rng.randi_range(0, i)
			var item: int = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = item
	return _bag.pop_back()

func _spawn() -> void:
	piece = next_piece
	next_piece = _take_piece()
	origin = Vector2i(3, -1)
	rotation = 0
	_fall_timer = 0.0
	status = String(TranslationServer.translate("NÍVEL %d  •  %d LINHAS")) % [1 + floori(float(lines) / 10.0), lines]
	if not _fits(origin, rotation):
		finished = true
		status = "FIM DE JOGO"

func cells(kind: int, turns: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw in SHAPES[kind]:
		var cell: Vector2i = raw
		if kind != 1:
			for turn in range(posmod(turns, 4)):
				cell = Vector2i((3 if kind == 0 else 2) - cell.y, cell.x)
		result.append(cell)
	return result

func _fits(position: Vector2i, turns: int) -> bool:
	for cell in cells(piece, turns):
		var p := position + cell
		if p.x < 0 or p.x >= WIDTH or p.y >= HEIGHT:
			return false
		if p.y >= 0 and board[p.y][p.x] != 0:
			return false
	return true

func _move(horizontal: int) -> void:
	var target := origin + Vector2i(horizontal, 0)
	if _fits(target, rotation):
		origin = target
		sound_events.append("move")

func _rotate() -> void:
	for offset in [0, -1, 1, -2, 2]:
		var target := origin + Vector2i(offset, 0)
		if _fits(target, rotation + 1):
			origin = target
			rotation = posmod(rotation + 1, 4)
			sound_events.append("move")
			return

func _drop_one(award: bool) -> void:
	if _fits(origin + Vector2i.DOWN, rotation):
		origin.y += 1
		if award:
			score += 1
	else:
		_lock()

func _lock() -> void:
	for cell in cells(piece, rotation):
		if (origin + cell).y < 0:
			finished = true
			status = "FIM DE JOGO"
			return
	for cell in cells(piece, rotation):
		var p := origin + cell
		board[p.y][p.x] = piece + 1
	var removed := 0
	for y in range(HEIGHT - 1, -1, -1):
		if board[y].count(0) == 0:
			board.remove_at(y)
			removed += 1
	for i in range(removed):
		var row := PackedInt32Array()
		row.resize(WIDTH)
		board.push_front(row)
	if removed > 0:
		sound_events.append("line")
		var rewards := [0, 100, 300, 500, 800]
		score += int(rewards[removed]) * (1 + floori(float(lines) / 10.0))
		lines += removed
	else:
		sound_events.append("lock")
	_spawn()

func step(delta: float, controls: Dictionary) -> void:
	if finished:
		return
	var dt := clampf(delta, 0.0, 0.1)
	var direction := int(bool(controls.get("right", false))) - int(bool(controls.get("left", false)))
	if direction != _held_direction:
		_held_direction = direction
		_repeat_timer = 0.23
		if direction != 0:
			_move(direction)
	elif direction != 0:
		_repeat_timer -= dt
		if _repeat_timer <= 0.0:
			_move(direction)
			_repeat_timer += 0.085
	if bool(controls.get("up_pressed", false)) or bool(controls.get("action_pressed", false)):
		_rotate()
	if bool(controls.get("action_alt_pressed", false)):
		while _fits(origin + Vector2i.DOWN, rotation):
			origin.y += 1
			score += 2
		_lock()
		return
	var soft := bool(controls.get("down", false))
	var interval := 0.055 if soft else maxf(0.12, 0.7 - float(floori(float(lines) / 10.0)) * 0.065)
	_fall_timer += dt
	if _fall_timer >= interval:
		_fall_timer -= interval
		_drop_one(soft)

func render(canvas: Control, area: Rect2) -> void:
	canvas.draw_set_transform(area.position, 0.0, area.size / Vector2(800, 480))
	canvas.draw_rect(Rect2(0, 0, 800, 480), Color("0d1529"))
	for i in range(12):
		var x := float(i*76-40)
		canvas.draw_line(Vector2(x,0),Vector2(x+210,480),Color("152238"),1.0)
	canvas.draw_rect(Rect2(24,48,212,246),Color("111f33"))
	canvas.draw_rect(Rect2(24,48,3,246),Color("73d9d0"))
	canvas.draw_rect(Rect2(530,48,222,280),Color("111f33"))
	canvas.draw_rect(Rect2(270, 30, 240, 416), Color("1e354c"))
	canvas.draw_rect(Rect2(274, 34, 232, 408), Color("73d9d0"))
	canvas.draw_rect(Rect2(278, 38, 224, 400), Color("090f1e"))
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var p := Vector2(280 + x * 22, 40 + y * 22)
			var value: int = board[y][x]
			if value > 0:
				_draw_cell(canvas, p, COLORS[value - 1])
			else:
				canvas.draw_rect(Rect2(p + Vector2.ONE, Vector2(20, 20)), Color("101d31"))
	if not finished:
		var ghost := origin
		while _fits(ghost + Vector2i.DOWN, rotation):
			ghost.y += 1
		for cell in cells(piece, rotation):
			var p := ghost + cell
			if p.y >= 0:
				canvas.draw_rect(Rect2(Vector2(280 + p.x * 22, 40 + p.y * 22) + Vector2.ONE, Vector2(20, 20)), Color(COLORS[piece], 0.35), false, 1.5)
		for cell in cells(piece, rotation):
			var p := origin + cell
			if p.y >= 0:
				_draw_cell(canvas, Vector2(280 + p.x * 22, 40 + p.y * 22), COLORS[piece])
	_text(canvas, Vector2(44, 90), "PONTOS", 18, Color("8196b3"))
	_text(canvas, Vector2(44, 130), "%06d" % score, 32, Color("f8d574"))
	_text(canvas, Vector2(44, 211), "LINHAS", 18, Color("8196b3"))
	_text(canvas, Vector2(44, 248), "%02d" % lines, 30, Color("dbecff"))
	_text(canvas, Vector2(551, 89), "PRÓXIMA", 18, Color("8196b3"))
	canvas.draw_rect(Rect2(546, 105, 162, 113), Color("142039"))
	for cell in cells(next_piece, 0):
		_draw_cell(canvas, Vector2(574 + cell.x * 22, 133 + cell.y * 22), COLORS[next_piece])
	_text(canvas, Vector2(551, 290), String(TranslationServer.translate("NÍVEL %02d")) % (1 + floori(float(lines) / 10.0)), 24, Color("dbecff"))
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_cell(canvas: Control, position: Vector2, color: Color) -> void:
	canvas.draw_rect(Rect2(position + Vector2.ONE, Vector2(20, 20)), color.darkened(0.5))
	canvas.draw_rect(Rect2(position + Vector2(3, 3), Vector2(16, 15)), color.darkened(.08))
	canvas.draw_rect(Rect2(position + Vector2(5, 5), Vector2(12, 9)), color.lightened(.12))
	canvas.draw_line(position + Vector2(3, 3), position + Vector2(18, 3), color.lightened(0.4), 2.0)
	canvas.draw_line(position + Vector2(18, 5), position + Vector2(18, 18), color.darkened(.3), 2.0)

func _text(canvas: Control, point: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(ThemeDB.fallback_font, point, String(TranslationServer.translate(text)), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
