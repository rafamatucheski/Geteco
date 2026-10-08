extends Control
## Race instruments read the drivetrain directly; no interpolation delays shifts.
const FACE := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const INK := Color("11161c")
const PAPER := Color("f4f3ef")
const MUTED := Color("a3aab2")
const CORAL := Color("ff633b")
const AMBER := Color("ffbe63")
const CYAN := Color("58d7ec")
const TRACK := Color("343b43")
const STYLES := ["classic", "bar", "street", "pro", "champion"]

var rpm := 900.0
var redline := 7000.0
var shift_rpm := 6000.0
var speed := 0.0
var gear := 1
var nitro := 0.0
var remaining := 0.0
var seconds := 0.0
var gap := 0.0
var headline := ""
var rival := ""
var feedback := ""
var clock := 0.0
var rival_offscreen := 0
var race_distance := 800.0
var show_start_lights := false
var racing := false
var input_gamepad := false
var _nitro_active := false
var _max_gear := 6
var style_id := "classic"
var preview_mode := false
var _dial_center := Vector2(INF, INF)
var _dial_redline := -1.0
var _dial_shift := -1.0
var _dial_staging := false
var _dial_style := ""
var _dial_minor := PackedVector2Array()
var _dial_major := PackedVector2Array()
var _dial_red_minor := PackedVector2Array()
var _dial_red_major := PackedVector2Array()
var _dial_label_positions := PackedVector2Array()
var _dial_label_text: Array[String] = []
var _dial_arcs: Dictionary = {}

func set_style(id: String) -> void:
	style_id = id if id in STYLES else "classic"
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_gamepad = not Input.get_connected_joypads().is_empty()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.2):
		input_gamepad = true
	elif event is InputEventKey:
		input_gamepad = false

func update_state(drive, distance_left: float, elapsed: float, lead: float, text: String, rival_name: String) -> void:
	rpm = drive.rpm
	redline = drive.redline
	shift_rpm = drive.ideal_shift_rpm
	speed = drive.speed_mps * 3.6
	gear = drive.gear
	nitro = drive.nitro
	_nitro_active = drive.nitro_active
	_max_gear = drive.spec.gears.size()
	remaining = distance_left
	seconds = elapsed
	gap = lead
	headline = text
	rival = rival_name
	queue_redraw()

func _draw() -> void:
	if preview_mode:
		var preview_scale := minf(size.x / 640.0, size.y / 270.0)
		if preview_scale <= 0.0: return
		var inset := (size - Vector2(640, 270) * preview_scale) * .5
		draw_set_transform(inset, 0.0, Vector2.ONE * preview_scale)
		_draw_instruments(Vector2(640, 280 if style_id == "bar" else 300))
		draw_set_transform(Vector2.ZERO)
		return
	# A single logical canvas keeps every instrument and control inside 960x540
	# and 1280x720, including non-16:9 windows. No per-frame Control rebuilding.
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	if factor <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	var canvas := size / factor
	_draw_progress(canvas)
	_draw_timer(canvas)
	_draw_instruments(canvas)
	_draw_start(canvas)
	if rival_offscreen != 0:
		_draw_rival_indicator(canvas)
	draw_set_transform(Vector2.ZERO)

func _draw_progress(_canvas: Vector2) -> void:
	var at := Vector2(24, 24)
	_panel(Rect2(at, Vector2(344, 100)))
	_text(at + Vector2(16, 25), "DANTE", 18, PAPER)
	_text(at + Vector2(150, 25), rival.to_upper(), 18, MUTED, 176, HORIZONTAL_ALIGNMENT_RIGHT)
	var progress := clampf(1.0 - remaining / maxf(race_distance, 1.0), 0.0, 1.0)
	var opponent := clampf(progress - gap / maxf(race_distance, 1.0), 0.0, 1.0)
	var rail := at + Vector2(16, 43)
	for lane in 2:
		var y := rail.y + lane * 13.0
		var fraction := progress if lane == 0 else opponent
		var tint := CORAL if lane == 0 else MUTED
		draw_rect(Rect2(rail.x, y, 310, 3), TRACK)
		draw_rect(Rect2(rail.x, y, 310 * fraction, 3), tint)
		draw_rect(Rect2(rail.x + 306 * fraction, y - 3, 4, 9), tint)
	draw_line(at + Vector2(326, 38), at + Vector2(326, 64), PAPER, 1.0)
	var placing := "1º" if gap >= 0.0 else "2º"
	_text(at + Vector2(16, 88), placing + " / 2", 20, PAPER)
	var advantage := "LADO A LADO" if absf(gap) < 0.5 else ("+%.1f m" % gap if gap > 0.0 else "−%.1f m" % absf(gap))
	_text(at + Vector2(100, 87), advantage, 16, AMBER if gap >= 0.0 else MUTED, 226, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_timer(canvas: Vector2) -> void:
	var at := Vector2(canvas.x - 248, 24)
	_panel(Rect2(at, Vector2(224, 100)))
	_text(at + Vector2(16, 24), "TEMPO", 13, MUTED)
	_text(at + Vector2(16, 62), "%05.2f" % seconds, 38, PAPER)
	_text(at + Vector2(16, 87), "%d m RESTANTES" % ceili(maxf(0.0, remaining)), 15, MUTED)

func _draw_instruments(canvas: Vector2) -> void:
	if style_id != "bar":
		_draw_circular(canvas)
		return
	_draw_bar(canvas)

func _draw_bar(canvas: Vector2) -> void:
	var at := Vector2((canvas.x - 600) * 0.5, canvas.y - 211)
	_panel(Rect2(at, Vector2(600, 159)))
	var ratio := clampf(rpm / maxf(redline, 1.0), 0.0, 1.0)
	var staging := show_start_lights or headline.is_valid_int()
	var ideal_from := 0.43 if staging else shift_rpm * 0.94 / maxf(redline, 1.0)
	var ideal_to := 0.64 if staging else 0.985
	var ideal := ratio >= ideal_from and ratio <= ideal_to
	var limiter := ratio > 0.985
	var accent := CORAL if limiter else (AMBER if ideal else PAPER)
	draw_rect(Rect2(at, Vector2(600, 2)), CYAN if _nitro_active else CORAL)
	_text(at + Vector2(18, 22), "RPM", 13, MUTED)
	_text(at + Vector2(62, 22), "%04d" % roundi(rpm), 15, accent)
	var cue := "MANTENHA O GIRO" if staging and ideal else ("PREPARE A LARGADA" if staging else "")
	if racing and gear < _max_gear:
		cue = "TROQUE AGORA" if ideal else ("NO LIMITE" if limiter else "")
	elif not headline.is_empty() and not staging:
		cue = headline
	_text(at + Vector2(235, 22), cue, 15, accent, 347, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := at + Vector2(18, 33)
	var bar_width := 564.0
	# The illuminated shift window exactly matches DesertDrivetrain, including staging.
	draw_rect(Rect2(bar + Vector2(bar_width * ideal_from, -3), Vector2(bar_width * (ideal_to - ideal_from), 27)), Color(AMBER, 0.17))
	for segment in 36:
		var segment_ratio := float(segment + 1) / 36.0
		var lit := ratio >= float(segment) / 36.0
		var tint := TRACK
		if lit:
			tint = CORAL if segment_ratio > 0.985 else (AMBER if segment_ratio >= ideal_from and segment_ratio <= ideal_to else PAPER)
		draw_rect(Rect2(bar + Vector2(segment * bar_width / 36.0, 0), Vector2(bar_width / 36.0 - 3.0, 20)), tint)
	# A thin cursor exposes changes smaller than one segment immediately.
	draw_rect(Rect2(bar + Vector2(bar_width * ratio - 1.0, -4), Vector2(2, 28)), accent)
	for mark in range(int(floor(redline / 1000.0)) + 1):
		var x := bar.x + bar_width * float(mark) * 1000.0 / maxf(redline, 1.0)
		_text(Vector2(x - 4, bar.y + 38), str(mark), 11, MUTED)
	_text(at + Vector2(17, 135), "%03d" % roundi(speed), 68, PAPER)
	_text(at + Vector2(153, 134), "km/h", 16, MUTED)
	draw_line(at + Vector2(214, 86), at + Vector2(214, 143), TRACK, 1.0)
	_text(at + Vector2(235, 134), str(gear), 60, accent)
	_text(at + Vector2(284, 105), "MARCHA", 12, MUTED)
	_text(at + Vector2(284, 130), "/ %d" % _max_gear, 18, MUTED)
	var nitro_at := at + Vector2(389, 93)
	_text(nitro_at, "NITRO", 13, CYAN if nitro > 0.0 else MUTED)
	_text(nitro_at + Vector2(83, 0), "ATIVO" if _nitro_active else "%d%%" % roundi(nitro * 100.0), 14, CYAN, 110, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_rect(Rect2(nitro_at + Vector2(0, 12), Vector2(193, 6)), TRACK)
	draw_rect(Rect2(nitro_at + Vector2(0, 12), Vector2(193 * clampf(nitro, 0.0, 1.0), 6)), CYAN)
	_text(nitro_at + Vector2(0, 46), "A" if input_gamepad else "SHIFT", 13, CYAN if nitro > 0.0 else MUTED)
	_text(nitro_at + Vector2(52, 46), "ACIONAR", 12, MUTED)
	if not preview_mode: _draw_controls(Vector2((canvas.x - 600) * 0.5, canvas.y - 27))
	_draw_feedback(at, staging)

func _draw_feedback(at: Vector2, staging: bool) -> void:
	if not preview_mode and not feedback.is_empty():
		var text := feedback.to_upper().replace("LARGOU · ", "")
		if staging and text == "ACELERE PARA PREPARAR O GIRO":
			text = "ACELERE ATÉ A FAIXA AMARELA"
		var positive := "IDEAL" in text or "PERFEITA" in text or "BOA TROCA" in text
		var negative := "ADIANT" in text or "ATRAS" in text or "PATIN" in text or "BAIXO" in text
		var color := AMBER if positive else (CORAL if negative else PAPER)
		_panel(Rect2(at + Vector2(0, -47), Vector2(600, 36)))
		_text(at + Vector2(12, -22), text, 21, color, 576, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_circular(canvas: Vector2) -> void:
	var at := Vector2((canvas.x - 600) * .5, canvas.y - 294)
	var center := at + Vector2(126, 124)
	var staging := show_start_lights or headline.is_valid_int()
	var ratio := clampf(rpm / maxf(redline, 1.0), 0.0, 1.0)
	var ideal_from := .43 if staging else clampf(shift_rpm * .94 / maxf(redline, 1.0), 0.0, .985)
	var ideal_to := .64 if staging else .985
	var ideal := ratio >= ideal_from and ratio <= ideal_to
	var limiter := ratio > .985
	var face_color := Color("eeeae0") if style_id == "pro" else INK
	var tick_color := Color("20262b") if style_id == "pro" else PAPER
	var dim_color := Color("63707b") if style_id == "pro" else MUTED
	var accent := Color("6cf4b4") if style_id == "street" else (AMBER if style_id == "champion" else CORAL)
	var start := PI * .75
	var sweep := PI * 1.5
	_cache_dial_geometry(center, staging)
	# One low-profile telemetry wing joins the physical-looking circular face.
	_panel(Rect2(at + Vector2(126, 69), Vector2(474, 154)))
	draw_rect(Rect2(at + Vector2(258, 69), Vector2(342, 2)), CYAN if _nitro_active else accent)
	draw_circle(center, 123, Color("080b0f"), true, -1, true)
	draw_circle(center, 119, face_color, true, -1, true)
	_static_dial_arc(&"rim", 120, 0, TAU, 96, Color("56616b"), 1.5)
	if style_id == "street":
		_static_dial_arc(&"street_outer", 115, start, start + sweep, 80, Color(accent, .22), 5)
		draw_arc(center, 115, start, start + sweep * ratio, 80, accent, 2.5, true)
		_static_dial_arc(&"street_inner", 104, start, start + sweep, 72, Color(CYAN, .5), 1)
	elif style_id == "champion":
		_static_dial_arc(&"champion_outer", 121, 0, TAU, 96, Color(AMBER, .7), 2)
		_static_dial_arc(&"champion_inner", 114, start, start + sweep, 80, Color("665333"), 1.5)
		for angle in [PI * .25, PI * .75, PI * 1.25, PI * 1.75]:
			var screw := center + Vector2.from_angle(angle) * 115
			draw_circle(screw, 2.5, AMBER, true, -1, true)
			draw_line(screw - Vector2(1.5, 0), screw + Vector2(1.5, 0), INK, 1, true)
	elif style_id == "pro":
		_static_dial_arc(&"pro_inner", 112, 0, TAU, 88, Color("b7bebc"), 1.5)
	else:
		_static_dial_arc(&"classic_inner", 113, start, start + sweep, 80, TRACK, 3)
	# This band shares the exact launch and shift bounds of the powertrain.
	_static_dial_arc(&"shift_window", 106, start + sweep * ideal_from, start + sweep * ideal_to, 32, AMBER, 6 if ideal else 4)
	_static_dial_arc(&"redline", 106, start + sweep * .985, start + sweep, 6, CORAL, 6)
	if not _dial_minor.is_empty(): draw_multiline(_dial_minor, tick_color, 1, true)
	if not _dial_major.is_empty(): draw_multiline(_dial_major, tick_color, 2, true)
	if not _dial_red_minor.is_empty(): draw_multiline(_dial_red_minor, CORAL, 1, true)
	if not _dial_red_major.is_empty(): draw_multiline(_dial_red_major, CORAL, 2, true)
	for label in _dial_label_positions.size():
		_text(_dial_label_positions[label], _dial_label_text[label], 18 if style_id == "pro" else 16, tick_color, 28, HORIZONTAL_ALIGNMENT_CENTER)
	_text(center + Vector2(-55, -29), "RPM × 1000", 12, dim_color, 110, HORIZONTAL_ALIGNMENT_CENTER)
	# A rigid needle follows the authoritative RPM in the same rendered frame.
	# No tween, lerp, additional timer or delayed gauge state is introduced.
	var needle_direction := Vector2.from_angle(start + sweep * ratio)
	var perpendicular := Vector2(-needle_direction.y, needle_direction.x)
	draw_colored_polygon(PackedVector2Array([
		center - needle_direction * 15 - perpendicular * 3,
		center + needle_direction * 89,
		center - needle_direction * 15 + perpendicular * 3,
	]), CORAL if limiter or style_id == "pro" else accent)
	draw_circle(center, 8, tick_color, true, -1, true)
	draw_circle(center, 4, face_color, true, -1, true)
	_text(center + Vector2(-44, 43), "%04d" % roundi(rpm), 24, tick_color, 88, HORIZONTAL_ALIGNMENT_CENTER)
	_text(center + Vector2(-44, 61), "RPM", 11, dim_color, 88, HORIZONTAL_ALIGNMENT_CENTER)
	if style_id in ["pro", "champion"]:
		# Competition faces add five real shift lamps without blinking the scene.
		for lamp in 5:
			var lit := ratio >= ideal_from - .12 + lamp * .03
			var lamp_tint := (CORAL if limiter else AMBER) if lit else (Color("d0d2cb") if style_id == "pro" else TRACK)
			draw_circle(center + Vector2((lamp - 2) * 11, 84), 3, lamp_tint, true, -1, true)
	var cue := "GIRO IDEAL" if staging and ideal else ("ACELERE ATÉ A FAIXA" if staging else "")
	if racing and gear < _max_gear:
		cue = "TROQUE AGORA" if ideal else ("NO LIMITE" if limiter else "")
	elif not headline.is_empty() and not staging:
		cue = headline
	if not cue.is_empty():
		_panel(Rect2(at + Vector2(258, 34), Vector2(342, 35)))
		_text(at + Vector2(274, 56), cue, 17, CORAL if limiter else (AMBER if ideal else PAPER), 309, HORIZONTAL_ALIGNMENT_CENTER)
	_text(at + Vector2(270, 100), "VELOCIDADE", 12, MUTED)
	_text(at + Vector2(268, 160), "%03d" % roundi(speed), 66, PAPER)
	_text(at + Vector2(387, 159), "km/h", 15, MUTED)
	draw_line(at + Vector2(449, 87), at + Vector2(449, 169), TRACK, 1, true)
	_text(at + Vector2(465, 100), "MARCHA", 12, MUTED, 116, HORIZONTAL_ALIGNMENT_CENTER)
	_text(at + Vector2(465, 159), str(gear), 62, accent, 74, HORIZONTAL_ALIGNMENT_CENTER)
	_text(at + Vector2(539, 151), "/ %d" % _max_gear, 17, MUTED)
	var nitro_at := at + Vector2(271, 186)
	_text(nitro_at, "NITRO", 12, CYAN if nitro > 0 else MUTED)
	_text(nitro_at + Vector2(64, 0), "A" if input_gamepad else "SHIFT", 11, MUTED)
	_text(nitro_at + Vector2(126, 0), "ATIVO" if _nitro_active else "%d%%" % roundi(nitro * 100.0), 12, CYAN, 184, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_rect(Rect2(nitro_at + Vector2(0, 10), Vector2(310, 5)), TRACK)
	draw_rect(Rect2(nitro_at + Vector2(0, 10), Vector2(310 * clampf(nitro, 0, 1), 5)), CYAN)
	if not preview_mode: _draw_controls(Vector2(at.x, canvas.y - 27))
	# Keep the cars and countdown unobstructed. Staging instructions belong to
	# the instrument wing; shift/launch feedback sits below the top race HUD.
	if not staging: _draw_feedback(Vector2(at.x, 177), false)

func _cache_dial_geometry(center: Vector2, staging: bool) -> void:
	if center == _dial_center and redline == _dial_redline and shift_rpm == _dial_shift and staging == _dial_staging and style_id == _dial_style:
		return
	_dial_center = center
	_dial_redline = redline
	_dial_shift = shift_rpm
	_dial_staging = staging
	_dial_style = style_id
	_dial_minor.clear()
	_dial_major.clear()
	_dial_red_minor.clear()
	_dial_red_major.clear()
	_dial_label_positions.clear()
	_dial_label_text.clear()
	_dial_arcs.clear()
	# Static positions and strings are rebuilt only on layout/powertrain/style
	# changes. RPM changes leave this cache intact and still move the needle now.
	for tick in range(int(floor(redline / 250.0)) + 1):
		var tick_rpm := float(tick) * 250.0
		var unit := Vector2.from_angle(PI * .75 + PI * 1.5 * tick_rpm / maxf(redline, 1.0))
		var major := tick % 4 == 0
		var red := tick_rpm / maxf(redline, 1.0) > .985
		var begin := center + unit * (89 if major else 95)
		var end := center + unit * 101
		if major:
			if red:
				_dial_red_major.append(begin)
				_dial_red_major.append(end)
			else:
				_dial_major.append(begin)
				_dial_major.append(end)
			_dial_label_positions.append(center + unit * 75 + Vector2(-14, 6))
			_dial_label_text.append(str(floori(float(tick) / 4.0)))
		elif red:
			_dial_red_minor.append(begin)
			_dial_red_minor.append(end)
		else:
			_dial_minor.append(begin)
			_dial_minor.append(end)

func _static_dial_arc(key: StringName, radius: float, from: float, to: float, count: int, color: Color, width: float) -> void:
	if not _dial_arcs.has(key):
		var points := PackedVector2Array()
		points.resize(count)
		for vertex in count:
			points[vertex] = _dial_center + Vector2.from_angle(lerpf(from, to, float(vertex) / float(count - 1))) * radius
		_dial_arcs[key] = points
	draw_polyline(_dial_arcs[key], color, width, true)

func _draw_controls(at: Vector2) -> void:
	_control_key(at, "RT" if input_gamepad else "W / ↑", "ACELERAR", 138)
	_control_key(at + Vector2(150, 0), "RB" if input_gamepad else "ESPAÇO", "TROCAR", 159)
	_control_key(at + Vector2(321, 0), "B" if input_gamepad else "Q", "ABANDONAR", 132)
	_control_key(at + Vector2(474, 0), "START" if input_gamepad else "ESC", "PAUSA", 126)

func _control_key(at: Vector2, key: String, action: String, width: float) -> void:
	var key_width := maxf(25.0, FACE.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12)
	draw_rect(Rect2(at + Vector2(0, -17), Vector2(width, 25)), Color(INK, 0.88))
	draw_rect(Rect2(at + Vector2(0, -17), Vector2(key_width, 25)), TRACK)
	_text(at + Vector2(6, 1), key, 12, PAPER)
	_text(at + Vector2(key_width + 7, 1), action, 12, PAPER)

func _draw_start(canvas: Vector2) -> void:
	var staging := show_start_lights or headline.is_valid_int()
	if not staging:
		return
	var center := Vector2(canvas.x * 0.5, 40)
	_panel(Rect2(center - Vector2(111, 16), Vector2(222, 69)))
	var count := clampi(int(headline), 1, 3)
	for lamp in 3:
		var lamp_at := center + Vector2((lamp - 1) * 52, 17)
		var on := lamp < 4 - count
		draw_rect(Rect2(lamp_at - Vector2(18, 18), Vector2(36, 36)), AMBER if on else TRACK)
		if on:
			draw_rect(Rect2(lamp_at - Vector2(12, 12), Vector2(24, 3)), Color(PAPER, 0.55))
	var number_at := Vector2(center.x - 70, canvas.y * 0.31)
	_text(number_at, str(count), 92, PAPER, 140, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_rival_indicator(canvas: Vector2) -> void:
	var at := Vector2(24.0 if rival_offscreen < 0 else canvas.x - 232.0, canvas.y * 0.43)
	_panel(Rect2(at, Vector2(208, 48)))
	draw_rect(Rect2(at, Vector2(3, 48)), CORAL)
	var direction := "← " if rival_offscreen < 0 else "→ "
	_text(at + Vector2(12, 20), direction + rival.to_upper(), 17, PAPER, 184)
	_text(at + Vector2(12, 39), "%d m" % roundi(absf(gap)), 14, MUTED)

func _panel(rect: Rect2) -> void:
	draw_rect(rect, Color(INK, 0.93))
	draw_rect(rect, Color("414850"), false, 1.0)

func _text(at: Vector2, value: String, font_size: int, color: Color, width := -1.0, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FACE if font_size >= 17 else BODY, at, value, alignment, width, font_size, color)
