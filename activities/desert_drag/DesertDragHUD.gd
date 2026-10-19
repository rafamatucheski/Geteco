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
const GO := Color("6cf4b4")
# Quanto tempo as lâmpadas ficam verdes depois da largada: a confirmação do
# verde aparece onde o olhar já está, no conta-giros, e não só na árvore 3D.
const GO_FLASH := .6
const STYLES := ["classic", "bar", "street", "pro", "champion"]
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")

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
var event_title := ""
var challenge_status := ""
var _race_controls := true
var _shift_active := false
var _nitro_installed := true
var _dial_center := Vector2(INF, INF)
var _dial_redline := -1.0
var _dial_shift := -1.0
var _dial_staging := false
var _dial_style := ""
var _dial_race_controls := false
var _dial_minor := PackedVector2Array()
var _dial_major := PackedVector2Array()
var _dial_red_minor := PackedVector2Array()
var _dial_red_major := PackedVector2Array()
var _dial_label_positions := PackedVector2Array()
var _dial_label_text: Array[String] = []
var _dial_arcs: Dictionary = {}
var _dial_face := PackedVector2Array()

func set_style(id: String) -> void:
	style_id = id if id in STYLES else "classic"
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A connected but idle controller must not hide the keyboard controls.
	# The next real input event selects the displayed device.
	input_gamepad = false

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
	_race_controls = drive.race_mode
	_shift_active = drive.shift_remaining>0.0
	_nitro_installed = float(drive.spec.nitro_seconds)>0.0
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
	var canvas := size / factor
	# Em tela ultralarga (21:9) os painéis iam para as bordas, a ~860 px lógicos
	# do conta-giros. A HUD fica numa faixa 16:9 centrada; telas mais estreitas
	# que 16:9 não mudam.
	var inset := maxf(0.0, canvas.x - canvas.y * 16.0 / 9.0) * .5
	canvas.x -= inset * 2.0
	draw_set_transform(Vector2(inset * factor, 0.0), 0.0, Vector2.ONE * factor)
	_draw_progress(canvas)
	_draw_timer(canvas)
	_draw_instruments(canvas)
	_draw_start(canvas)
	if not challenge_status.is_empty():
		var status_at := Vector2((canvas.x-520)*.5,92)
		_panel(Rect2(status_at,Vector2(520,34)))
		_text(status_at+Vector2(12,23),challenge_status,16,AMBER,496,HORIZONTAL_ALIGNMENT_CENTER)
	if rival_offscreen != 0:
		_draw_rival_indicator(canvas)
	draw_set_transform(Vector2.ZERO)

func _draw_progress(_canvas: Vector2) -> void:
	if style_id=="classic":
		_draw_meet_progress()
		return
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
	if style_id=="classic":
		_draw_meet_timer(canvas)
		return
	var at := Vector2(canvas.x - 248, 24)
	_panel(Rect2(at, Vector2(224, 100)))
	_text(at + Vector2(16, 24), "TEMPO", 13, MUTED)
	_text(at + Vector2(16, 62), "%05.2f" % seconds, 38, PAPER)
	_text(at + Vector2(16, 87), String(TranslationServer.translate("%d m RESTANTES")) % ceili(maxf(0.0, remaining)), 15, MUTED)

func _draw_instruments(canvas: Vector2) -> void:
	if style_id=="classic":
		_draw_classic(canvas)
		return
	if style_id != "bar":
		_draw_circular(canvas)
		return
	_draw_bar(canvas)

func _good_from(staging: bool) -> float:
	return (DRIVE.LAUNCH_GOOD_MIN if _race_controls else .43) if staging else shift_rpm*.94/maxf(redline,1.0)

func _good_to(staging: bool) -> float:
	return (DRIVE.LAUNCH_GOOD_MAX if _race_controls else .64) if staging else .985

func _perfect_from(staging: bool) -> float:
	return DRIVE.LAUNCH_PERFECT_MIN if staging else .89

func _perfect_to(staging: bool) -> float:
	return DRIVE.LAUNCH_PERFECT_MAX if staging else .94

func _cue(staging: bool, ratio: float) -> String:
	if staging:
		if ratio<_good_from(true): return "ACELERE ATÉ A FAIXA"
		if ratio>_good_to(true): return "ALIVIE O ACELERADOR"
		return "GIRO IDEAL" if ratio>=_perfect_from(true) and ratio<=_perfect_to(true) else "SEGURE O GIRO"
	if _shift_active: return "TROCANDO"
	if racing:
		if gear>=_max_gear: return "ÚLTIMA MARCHA"
		if ratio>.985: return "NO LIMITE"
		if ratio>=_good_from(false): return "TROQUE AGORA"
		if ratio>=_good_from(false)-.12: return "PREPARE A TROCA"
	return headline

func message(staging: bool, ratio: float) -> Array:
	# Uma instrução por vez. Troca devida agora vence o veredito da troca
	# anterior: o veredito dura 1,2 s e, se a faixa seguinte chegasse nesse
	# intervalo, o painel elogiava a troca velha em vez de pedir a nova.
	var cue := _cue(staging,ratio)
	if staging:
		var over := ratio>_good_to(true)
		return [cue,CORAL if over else (AMBER if ratio>=_good_from(true) else PAPER)]
	if cue=="NO LIMITE": return [cue,CORAL]
	if cue=="TROQUE AGORA": return [cue,AMBER]
	if not feedback.is_empty():
		var text := feedback.to_upper()
		return [text,feedback_tone(text)]
	return [cue,MUTED if cue in ["TROCANDO","ÚLTIMA MARCHA"] else PAPER]

static func feedback_tone(text: String) -> Color:
	# Recebe o texto-fonte em português, antes do tr().
	if "ADIANT" in text or "ATRAS" in text or "PATIN" in text or "BAIXO" in text: return CORAL
	if "IDEAL" in text or "PERFEITA" in text or "BOA" in text: return AMBER
	return PAPER

func start_lamps_lit(staging: bool) -> int:
	# 3, 2, 1 acendem uma, duas e três lâmpadas âmbar; -1 é verde.
	if staging: return 4-clampi(int(headline),1,3) if headline.is_valid_int() else 0
	return -1 if racing and seconds<GO_FLASH else 0

func _draw_meet_progress() -> void:
	var at := Vector2(24,24)
	_panel(Rect2(at,Vector2(330,73)))
	_text(at+Vector2(16,29),"DANTE",23,PAPER)
	_text(at+Vector2(144,28),"×",23,MUTED)
	_text(at+Vector2(175,29),rival.to_upper(),23,PAPER,139,HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(at+Vector2(16,39),at+Vector2(114,39),AMBER,3)
	draw_line(at+Vector2(216,39),at+Vector2(314,39),CORAL,3)
	var advantage := "LADO A LADO" if absf(gap)<.5 else ("+%.1f m"%gap if gap>0 else "−%.1f m"%absf(gap))
	_text(at+Vector2(16,61),"1º / 2" if gap>=0 else "2º / 2",16,AMBER if gap>=0 else MUTED)
	_text(at+Vector2(121,61),advantage,16,MUTED,193,HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_meet_timer(canvas: Vector2) -> void:
	var at := Vector2(canvas.x-254,24)
	_panel(Rect2(at,Vector2(230,89)))
	_text(at+Vector2(14,36),"%d"%ceili(maxf(0.0,remaining)),34,PAPER,155,HORIZONTAL_ALIGNMENT_RIGHT)
	_text(at+Vector2(175,34),"m",18,MUTED)
	var progress := clampf(1.0-remaining/maxf(1.0,race_distance),0.0,1.0)
	var opponent := clampf(progress-gap/maxf(1.0,race_distance),0.0,1.0)
	draw_line(at+Vector2(16,49),at+Vector2(210,49),TRACK,3)
	draw_line(at+Vector2(16,49),at+Vector2(16+194*progress,49),AMBER,3)
	draw_line(at+Vector2(210,43),at+Vector2(210,55),PAPER,2)
	# Mesmas cores dos sublinhados dos nomes: âmbar Dante, coral rival. O ponto
	# do rival fica por baixo; lado a lado os dois viram um só marcador.
	draw_circle(at+Vector2(16+194*opponent,49),4,CORAL,true,-1,true)
	draw_circle(at+Vector2(16+194*progress,49),4,AMBER,true,-1,true)
	_text(at+Vector2(16,75),"TEMPO",12,MUTED)
	_text(at+Vector2(88,77),"%05.2f s"%seconds,20,PAPER,123,HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_classic(canvas: Vector2) -> void:
	# Compact half dial from the selected Noite de Acerto concept. All static
	# geometry is cached; the track and both cars keep the middle of the screen.
	var center := Vector2(canvas.x*.5-118,canvas.y-72)
	var staging := show_start_lights or headline.is_valid_int()
	var ratio := clampf(rpm/maxf(redline,1.0),0.0,1.0)
	var good := ratio>=_good_from(staging) and ratio<=_good_to(staging)
	var perfect := ratio>=_perfect_from(staging) and ratio<=_perfect_to(staging)
	_cache_dial_geometry(center,staging)
	# Separate silhouettes: 13 px of air after the 98 px dial, no rectangular
	# backing under the arc. Smaller plate retains legible type and contrast.
	draw_rect(Rect2(center+Vector2(111,-103),Vector2(224,124)),Color(INK,.85))
	draw_colored_polygon(_dial_face,Color("0a0f14",.87))
	_static_dial_arc(&"meet_rim",98,PI,TAU,64,Color("697078",.7),1)
	_static_dial_arc(&"meet_track",89,PI,TAU,64,TRACK,5)
	_static_dial_arc(&"meet_good",89,PI+PI*_good_from(staging),PI+PI*_good_to(staging),32,Color(AMBER,.48),5)
	_static_dial_arc(&"meet_perfect",89,PI+PI*_perfect_from(staging),PI+PI*_perfect_to(staging),24,AMBER,5 if perfect else 4)
	_static_dial_arc(&"meet_red",89,PI+PI*.985,TAU,6,CORAL,5)
	if not _dial_minor.is_empty(): draw_multiline(_dial_minor,PAPER,1,true)
	if not _dial_major.is_empty(): draw_multiline(_dial_major,PAPER,2,true)
	for label in _dial_label_positions.size():
		_text(_dial_label_positions[label],_dial_label_text[label],14,PAPER,28,HORIZONTAL_ALIGNMENT_CENTER)
	var needle := Vector2.from_angle(PI+PI*ratio)
	var perpendicular := Vector2(-needle.y,needle.x)
	draw_colored_polygon(PackedVector2Array([center-needle*6-perpendicular*1.5,center+needle*79,center-needle*6+perpendicular*1.5]),CORAL)
	draw_circle(center,6,PAPER,true,-1,true)
	draw_circle(center,3,INK,true,-1,true)
	_text(center+Vector2(-53,-23),"RPM × 1000",12,MUTED,106,HORIZONTAL_ALIGNMENT_CENTER)
	_text(center+Vector2(123,-57),"MARCHA",12,MUTED,58,HORIZONTAL_ALIGNMENT_CENTER)
	_text(center+Vector2(123,-10),str(gear),46,AMBER,58,HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(center+Vector2(185,-61),center+Vector2(185,-9),Color(TRACK,.7),1)
	_text(center+Vector2(196,-15),"%03d"%roundi(speed),38,PAPER,126,HORIZONTAL_ALIGNMENT_CENTER)
	_text(center+Vector2(196,1),"km/h",12,MUTED,126,HORIZONTAL_ALIGNMENT_CENTER)
	if _nitro_installed:
		_text(center+Vector2(123,16),"NITRO",12,CYAN if _nitro_active else MUTED)
		draw_rect(Rect2(center+Vector2(165,9),Vector2(107,4)),TRACK)
		draw_rect(Rect2(center+Vector2(165,9),Vector2(107*clampf(nitro,0,1),4)),CYAN if _nitro_active else Color("718691"))
		_literal(center+Vector2(278,16),"A" if input_gamepad else "SHIFT",12,CYAN if nitro>0 else MUTED,44,HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		# Barra vazia com a tecla acesa convidava a apertar SHIFT à toa.
		_text(center+Vector2(123,16),"SEM NITRO",12,MUTED)
	_draw_shift_lamps(center+Vector2(0,-111),ratio,staging)
	var line := message(staging,ratio)
	if not str(line[0]).is_empty():
		_text(center+Vector2(123,-80),line[0],17,line[1],200,HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(center+Vector2(123,-72),center+Vector2(323,-72),Color(AMBER if good else TRACK,.65),1)
	if not preview_mode:
		var actions: Array[String]=["RT" if input_gamepad else "W / ↑",tr("ACELERAR")]
		if not staging: actions.append_array(["RB" if input_gamepad else tr("ESPAÇO"),tr("TROCAR")])
		actions.append_array(["B" if input_gamepad else "Q",tr("ABANDONAR"),"START" if input_gamepad else "ESC",tr("PAUSA")])
		var hints := ""
		for index in range(0,actions.size(),2):
			if not hints.is_empty(): hints+="    ·    "
			hints+=actions[index]+"  "+actions[index+1]
		var at := Vector2((canvas.x-560)*.5,canvas.y-20)
		draw_string_outline(BODY,at,hints,HORIZONTAL_ALIGNMENT_CENTER,560,16,2,Color("080b0f",.9))
		_literal(at,hints,16,PAPER,560,HORIZONTAL_ALIGNMENT_CENTER)

func _draw_shift_lamps(center: Vector2, ratio: float, staging: bool) -> void:
	draw_rect(Rect2(center+Vector2(-52,-11),Vector2(104,22)),Color(INK,.85))
	# Na preparação o casulo vira o semáforo, logo acima do ponteiro que o
	# jogador segura na faixa (como no conceito escolhido). As luzes de troca
	# não diziam nada ali: apagadas em marcha lenta, todas acesas na faixa.
	var start := start_lamps_lit(staging)
	if start!=0:
		for lamp in 3:
			draw_circle(center+Vector2((lamp-1)*30,0),7,GO if start<0 else (AMBER if lamp<start else TRACK),true,-1,true)
		return
	for lamp in 5:
		var threshold := _good_from(staging)-.12+lamp*.03
		var lit := ratio>=threshold
		var tint := (CORAL if ratio>_good_to(staging) else AMBER) if lit else TRACK
		draw_circle(center+Vector2((lamp-2)*17,0),5,tint,true,-1,true)

func _draw_bar(canvas: Vector2) -> void:
	var at := Vector2((canvas.x - 600) * 0.5, canvas.y - 211)
	_panel(Rect2(at, Vector2(600, 159)))
	var ratio := clampf(rpm / maxf(redline, 1.0), 0.0, 1.0)
	var staging := show_start_lights or headline.is_valid_int()
	var ideal_from := _good_from(staging)
	var ideal_to := _good_to(staging)
	var ideal := ratio >= ideal_from and ratio <= ideal_to
	var limiter := ratio > 0.985
	var accent := CORAL if limiter else (AMBER if ideal else PAPER)
	draw_rect(Rect2(at, Vector2(600, 2)), CYAN if _nitro_active else CORAL)
	_text(at + Vector2(18, 22), "RPM", 13, MUTED)
	_text(at + Vector2(62, 22), "%04d" % roundi(rpm), 15, accent)
	var cue := _cue(staging,ratio)
	_text(at + Vector2(235, 22), cue, 15, accent, 347, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := at + Vector2(18, 33)
	var bar_width := 564.0
	# The illuminated shift window exactly matches DesertDrivetrain, including staging.
	draw_rect(Rect2(bar + Vector2(bar_width * ideal_from, -3), Vector2(bar_width * (ideal_to - ideal_from), 27)), Color(AMBER, 0.17))
	if _race_controls: draw_line(bar+Vector2(bar_width*_perfect_from(staging),-4),bar+Vector2(bar_width*_perfect_to(staging),-4),AMBER,3)
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
	_literal(nitro_at + Vector2(0, 46), "A" if input_gamepad else "SHIFT", 13, CYAN if nitro > 0.0 else MUTED)
	_text(nitro_at + Vector2(52, 46), "ACIONAR", 12, MUTED)
	if not preview_mode: _draw_controls(Vector2((canvas.x - 600) * 0.5, canvas.y - 27))
	_draw_feedback(at, staging)

func _draw_feedback(at: Vector2, staging: bool) -> void:
	if not preview_mode and not feedback.is_empty():
		var text := feedback.to_upper().replace("LARGOU · ", "")
		if staging and text == "ACELERE PARA PREPARAR O GIRO":
			text = "ACELERE ATÉ A FAIXA AMARELA"
		var positive := "IDEAL" in text or "PERFEITA" in text or "BOA" in text
		var negative := "ADIANT" in text or "ATRAS" in text or "PATIN" in text or "BAIXO" in text
		var color := AMBER if positive else (CORAL if negative else PAPER)
		_panel(Rect2(at + Vector2(0, -47), Vector2(600, 36)))
		_text(at + Vector2(12, -22), text, 21, color, 576, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_circular(canvas: Vector2) -> void:
	var at := Vector2((canvas.x - 600) * .5, canvas.y - 294)
	var center := at + Vector2(126, 124)
	var staging := show_start_lights or headline.is_valid_int()
	var ratio := clampf(rpm / maxf(redline, 1.0), 0.0, 1.0)
	var ideal_from := _good_from(staging)
	var ideal_to := _good_to(staging)
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
	if _race_controls: _static_dial_arc(&"perfect_window",110,start+sweep*_perfect_from(staging),start+sweep*_perfect_to(staging),20,AMBER,3)
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
	# Functional anticipation belongs to every face, including the free one.
	for lamp in 5:
		var lit := ratio>=ideal_from-.12+lamp*.03
		var lamp_tint := (CORAL if limiter else AMBER) if lit else (Color("d0d2cb") if style_id=="pro" else TRACK)
		draw_circle(center+Vector2((lamp-2)*11,84),3,lamp_tint,true,-1,true)
	var cue := _cue(staging,ratio)
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
	_literal(nitro_at + Vector2(64, 0), "A" if input_gamepad else "SHIFT", 11, MUTED)
	_text(nitro_at + Vector2(126, 0), "ATIVO" if _nitro_active else "%d%%" % roundi(nitro * 100.0), 12, CYAN, 184, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_rect(Rect2(nitro_at + Vector2(0, 10), Vector2(310, 5)), TRACK)
	draw_rect(Rect2(nitro_at + Vector2(0, 10), Vector2(310 * clampf(nitro, 0, 1), 5)), CYAN)
	if not preview_mode: _draw_controls(Vector2(at.x, canvas.y - 27))
	# Keep the cars and countdown unobstructed. Staging instructions belong to
	# the instrument wing; shift/launch feedback sits below the top race HUD.
	if not staging: _draw_feedback(Vector2(at.x, 177), false)

func _cache_dial_geometry(center: Vector2, staging: bool) -> void:
	if center == _dial_center and redline == _dial_redline and shift_rpm == _dial_shift and staging == _dial_staging and style_id == _dial_style and _race_controls==_dial_race_controls:
		return
	_dial_center = center
	_dial_redline = redline
	_dial_shift = shift_rpm
	_dial_staging = staging
	_dial_style = style_id
	_dial_race_controls = _race_controls
	_dial_minor.clear()
	_dial_major.clear()
	_dial_red_minor.clear()
	_dial_red_major.clear()
	_dial_label_positions.clear()
	_dial_label_text.clear()
	_dial_arcs.clear()
	_dial_face.clear()
	if style_id=="classic":
		for i in 49:
			_dial_face.append(center+Vector2.from_angle(PI+PI*float(i)/48.0)*97.0)
		_dial_face.append(center+Vector2(97,8))
		_dial_face.append(center+Vector2(-97,8))
		for tick in range(int(floor(redline/250.0))+1):
			var unit := Vector2.from_angle(PI+PI*float(tick)*250.0/maxf(redline,1.0))
			var major := tick%4==0
			var points: PackedVector2Array=_dial_major if major else _dial_minor
			points.append(center+unit*(72 if major else 78))
			points.append(center+unit*84)
			if major:
				_dial_major=points
				_dial_label_positions.append(center+unit*59+Vector2(-14,5))
				_dial_label_text.append(str(floori(float(tick)/4.0)))
			else: _dial_minor=points
		return
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
	_control_key(at + Vector2(150, 0), "RB" if input_gamepad else tr("ESPAÇO"), "TROCAR", 159)
	_control_key(at + Vector2(321, 0), "B" if input_gamepad else "Q", "ABANDONAR", 132)
	_control_key(at + Vector2(474, 0), "START" if input_gamepad else "ESC", "PAUSA", 126)

func _control_key(at: Vector2, key: String, action: String, width: float) -> void:
	var key_width := maxf(25.0, FACE.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12)
	draw_rect(Rect2(at + Vector2(0, -17), Vector2(width, 25)), Color(INK, 0.88))
	draw_rect(Rect2(at + Vector2(0, -17), Vector2(key_width, 25)), TRACK)
	_literal(at + Vector2(6, 1), key, 12, PAPER)
	_text(at + Vector2(key_width + 7, 1), action, 12, PAPER)

func _draw_start(canvas: Vector2) -> void:
	var staging := show_start_lights or headline.is_valid_int()
	if style_id=="classic":
		# A contagem mora no casulo do conta-giros; o título não desce mais
		# 24 px na preparação para abrir espaço às lâmpadas aqui em cima.
		var title := event_title if not event_title.is_empty() else "ARRANCADA · %d M"%roundi(race_distance)
		_panel(Rect2(Vector2(canvas.x*.5-158,26),Vector2(316,31)))
		_text(Vector2(canvas.x*.5-150,48),title,17,PAPER,300,HORIZONTAL_ALIGNMENT_CENTER)
		return
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
	_literal(at,tr(value),font_size,color,width,alignment)

func _literal(at: Vector2, value: String, font_size: int, color: Color, width := -1.0, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# Key names are input legends, not translatable action identifiers (SHIFT).
	draw_string(FACE if font_size>=17 else BODY,at,value,alignment,width,font_size,color)
