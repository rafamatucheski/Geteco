extends Control
## Contextual race instruments. Native controls only; no extra render viewport.
## Every card manages its own visibility: the results card outlives the race
## (the rider is already back on foot) without a modal menu freezing the world.
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const REV_ZONE := Vector2(.55,.85)
const CALLOUT_TIME := 1.9
const RESULTS_TIME := 9.0
var position_label: Label
var lap_label: Label
var time_label: Label
var gap_label: Label
var place_caption: Label
var lap_caption: Label
var time_caption: Label
var exit_label: Label
var speed_label: Label
var state_label: Label
var message: Label
var integrity: ProgressBar
var race_card: Panel
var speed_card: Panel
var start_card: Panel
var start_title: Label
var start_hint: Label
var rev_fill: ColorRect
var rev_zone: ColorRect
var callout_title: Label
var callout_detail: Label
var results_card: Panel
var results_title: Label
var results_rows: VBoxContainer
var results_footer: Label
var _callout_left := 0.0
var _callout_priority := 0
var _results_left := 0.0
var text: String = "":
	set(value):
		text = value
		if not is_instance_valid(message): return
		message.text = value
		message.visible = not value.is_empty()
		race_card.hide()
		speed_card.hide()
		start_card.hide()

func _ready() -> void:
	name = "MotocrossHUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_card = _panel(Vector2(470,122))
	race_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	race_card.offset_left = -235; race_card.offset_right = 235
	race_card.offset_top = 28; race_card.offset_bottom = 150
	position_label = _label(race_card,"",Vector2(18,11),48)
	place_caption = _label(race_card,"POSIÇÃO",Vector2(20,66),12,Color("a4adb6"))
	lap_label = _label(race_card,"",Vector2(147,13),31)
	lap_caption = _label(race_card,"VOLTA",Vector2(149,56),13,Color("a4adb6"))
	time_label = _label(race_card,"",Vector2(280,13),31)
	time_caption = _label(race_card,"TEMPO",Vector2(282,56),13,Color("a4adb6"))
	gap_label = _label(race_card,"",Vector2(20,88),18,Color("f3b96c"))
	speed_card = _panel(Vector2(228,152))
	speed_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_card.offset_left = -252; speed_card.offset_right = -24
	speed_card.offset_top = -182; speed_card.offset_bottom = -30
	speed_label = _label(speed_card,"",Vector2(16,1),49)
	_label(speed_card,"km/h",Vector2(122,32),18,Color("bdc5cb"))
	# Let minimum font/theme sizes participate in layout instead of allowing
	# the integrity bar to grow over the exit action at a fixed Y coordinate.
	var details := VBoxContainer.new()
	details.position = Vector2(16,63)
	details.size.x = 195
	details.add_theme_constant_override("separation",8)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_card.add_child(details)
	state_label = _label(details,"",Vector2.ZERO,17,Color("f3b96c"))
	integrity = ProgressBar.new()
	integrity.custom_minimum_size = Vector2(195,5)
	integrity.show_percentage = false
	integrity.add_theme_font_size_override("font_size",1)
	integrity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := StyleBoxFlat.new(); bar.bg_color = Color("e2a554")
	integrity.add_theme_stylebox_override("fill",bar)
	var back := StyleBoxFlat.new(); back.bg_color = Color("38434a")
	integrity.add_theme_stylebox_override("background",back)
	details.add_child(integrity)
	exit_label = _label(details,"E  ·  SAIR DA PROVA",Vector2.ZERO,14,Color("e1e6ea"))
	_build_start_card()
	callout_title = _label(self,"",Vector2.ZERO,44)
	callout_detail = _label(self,"",Vector2.ZERO,22,Color("e9edf0"))
	for label in [callout_title,callout_detail]:
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		label.offset_left = -360; label.offset_right = 360
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_shadow_color",Color(0,0,0,.85))
		label.add_theme_constant_override("shadow_offset_y",2)
		label.hide()
	callout_title.offset_top = 166; callout_title.offset_bottom = 222
	callout_detail.offset_top = 220; callout_detail.offset_bottom = 252
	message = _label(self,"",Vector2.ZERO,36)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.offset_left = -320; message.offset_right = 320
	message.offset_top = 142; message.offset_bottom = 252
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_shadow_color",Color.BLACK)
	message.add_theme_constant_override("shadow_offset_y",2)
	_build_results_card()
	race_card.hide(); speed_card.hide(); start_card.hide(); message.hide(); results_card.hide()
	set_process(false)

func _build_start_card() -> void:
	start_card = _panel(Vector2(420,118))
	start_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	start_card.offset_left = -210; start_card.offset_right = 210
	start_card.offset_top = 28; start_card.offset_bottom = 146
	start_title = _label(start_card,"",Vector2(18,8),30)
	var track := ColorRect.new()
	track.color = Color("2b353b")
	track.position = Vector2(18,54)
	track.size = Vector2(384,18)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_card.add_child(track)
	rev_zone = ColorRect.new()
	rev_zone.color = Color("3f8f58")
	rev_zone.position = Vector2(REV_ZONE.x*384,0)
	rev_zone.size = Vector2((REV_ZONE.y-REV_ZONE.x)*384,18)
	rev_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(rev_zone)
	rev_fill = ColorRect.new()
	rev_fill.color = Color("f0f3f4")
	rev_fill.position = Vector2(0,5)
	rev_fill.size = Vector2(0,8)
	rev_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(rev_fill)
	start_hint = _label(start_card,"SEGURE O GIRO NA FAIXA VERDE",Vector2(18,80),15,Color("a4adb6"))

func _build_results_card() -> void:
	# Six rows fit between the status toasts above and the minimap below.
	results_card = _panel(Vector2(430,370))
	results_card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	results_card.offset_left = 28; results_card.offset_right = 458
	results_card.offset_top = -215; results_card.offset_bottom = 155
	results_title = _label(results_card,"",Vector2(20,10),34)
	results_rows = VBoxContainer.new()
	results_rows.position = Vector2(20,62)
	results_rows.size = Vector2(390,210)
	results_rows.add_theme_constant_override("separation",2)
	results_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	results_card.add_child(results_rows)
	results_footer = _label(results_card,"",Vector2(20,318),15,Color("bdc5cb"))
	results_footer.size.x = 390
	results_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func present(place: int,count: int,lap: int,laps: int,seconds: float,bike,gap := "") -> void:
	message.hide(); start_card.hide(); race_card.show(); speed_card.show()
	place_caption.text = "POSIÇÃO"; lap_caption.text = "VOLTA"; time_caption.text = "TEMPO"
	exit_label.text = "E  ·  SAIR DA PROVA"
	position_label.text = "%d / %d"%[place,count]
	lap_label.text = "%02d / %02d"%[lap,laps]
	time_label.text = clock(seconds)
	gap_label.text = gap
	speed_label.text = "%02d"%int(absf(bike.speed)*3.6)
	integrity.value = bike.health
	state_label.text = "RECUPERANDO" if bike.crash_state!="riding" else (air_cue(bike) if bike._air_time>.12 else ("FREANDO" if bike._brake else ""))

## In flight: which way to lean to meet the ground below (W forward, S back).
static func air_cue(bike) -> String:
	var error := float(bike.air_attitude_error)
	if absf(error) <= float(bike.LANDING_PERFECT): return "NO AR · ● ALINHADO"
	return "NO AR · ▼ FRENTE (W)" if error > 0.0 else "NO AR · ▲ TRÁS (S)"

## Timed practice on a rented or owned bike: laps, best lap and current lap.
func present_practice(bike, laps: int, lap_clock: float, timing: bool, record: float, session_best: float, exit_hint: String) -> void:
	message.hide(); start_card.hide(); race_card.show(); speed_card.show()
	place_caption.text = "VOLTAS"; lap_caption.text = "MELHOR"; time_caption.text = "VOLTA ATUAL"
	exit_label.text = "E  ·  "+exit_hint
	position_label.text = "%d"%laps
	lap_label.text = clock(session_best) if session_best > 0.0 else "--:--"
	time_label.text = clock(lap_clock) if timing else "--:--.--"
	gap_label.text = ("RECORDE DA PISTA %s"%clock(record) if record > 0.0 else "SEM RECORDE NA PISTA")+("" if timing else " · CRUZE A LARGADA")
	speed_label.text = "%02d"%int(absf(bike.speed)*3.6)
	integrity.value = bike.health
	state_label.text = "RECUPERANDO" if bike.crash_state!="riding" else (air_cue(bike) if bike._air_time>.12 else ("FREANDO" if bike._brake else ""))

func present_start(rev: float, title: String) -> void:
	message.hide(); race_card.hide(); speed_card.hide(); start_card.show()
	start_title.text = title
	var value := clampf(rev,0.0,1.0)
	rev_fill.size.x = value*384.0
	var in_zone := value >= REV_ZONE.x and value <= REV_ZONE.y
	rev_fill.color = Color("8ee29f") if in_zone else (Color("f08a5d") if value > REV_ZONE.y else Color("f0f3f4"))

## Short centered announcement. A lower-priority line never hides a more
## important one (lap, holeshot, last lap) that is still fresh on screen.
func callout(title: String, detail := "", color := Color("f0f3f4"), priority := 1) -> void:
	if _callout_left > CALLOUT_TIME-.9 and priority < _callout_priority: return
	_callout_priority = priority
	_callout_left = CALLOUT_TIME
	callout_title.text = title
	callout_title.add_theme_color_override("font_color",color)
	callout_detail.text = detail
	callout_title.show()
	callout_detail.visible = not detail.is_empty()
	callout_title.modulate.a = 1.0
	callout_detail.modulate.a = 1.0
	set_process(true)

## rows: [{place, name, detail, player}] in finishing order.
func show_results(title: String, rows: Array, footer: String) -> void:
	results_title.text = title
	for child in results_rows.get_children(): child.queue_free()
	for row in rows:
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		results_rows.add_child(line)
		var color := Color("ffc34f") if bool(row.get("player",false)) else Color("e9edf0")
		var place := _label(line,"%dº"%int(row.place),Vector2.ZERO,22,color)
		place.custom_minimum_size.x = 46
		var who := _label(line,str(row.name),Vector2.ZERO,22,color)
		who.custom_minimum_size.x = 190
		_label(line,str(row.detail),Vector2.ZERO,20,Color("bdc5cb") if not bool(row.get("player",false)) else color)
	results_footer.text = footer
	results_card.show()
	results_card.modulate.a = 1.0
	_results_left = RESULTS_TIME
	set_process(true)

func hide_results() -> void:
	_results_left = 0.0
	results_card.hide()

func _process(delta: float) -> void:
	if _callout_left > 0.0:
		_callout_left = maxf(0.0,_callout_left-delta)
		var alpha := clampf(_callout_left/.45,0.0,1.0)
		callout_title.modulate.a = alpha
		callout_detail.modulate.a = alpha
		if _callout_left <= 0.0:
			callout_title.hide(); callout_detail.hide()
			_callout_priority = 0
	if _results_left > 0.0:
		_results_left = maxf(0.0,_results_left-delta)
		results_card.modulate.a = clampf(_results_left/.8,0.0,1.0)
		if _results_left <= 0.0: results_card.hide()
	if _callout_left <= 0.0 and _results_left <= 0.0: set_process(false)

static func clock(seconds: float) -> String:
	# Whole-number grouping/index; preserve integer truncation and precision.
	@warning_ignore("integer_division")
	return "%02d:%05.2f"%[int(seconds)/60,fmod(seconds,60)]

func _panel(dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035,.052,.063,.91)
	style.border_color = Color("bd7b38")
	style.border_width_top = 3
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	return panel

func _label(parent: Node,caption: String,at: Vector2,size_px: int,color := Color("f0f3f4")) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label
