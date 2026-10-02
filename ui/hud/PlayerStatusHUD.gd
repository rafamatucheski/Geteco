extends PanelContainer
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
var health_bar: ProgressBar
var armor_bar: ProgressBar
var cold_bar: ProgressBar
var cold_row: HBoxContainer
var cold_icon: Control
var cold_label: Label
var _values := {}
var _tweens := {}
var _cold_hold := 0.0
var _cold_visible := false
var _cold_tween: Tween
var _pulse: Tween
func _ready() -> void:
	name = "PlayerStatusHUD"
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",STYLE.compact(false,10,Vector2(12,10)))
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",5); add_child(column)
	health_bar = _row(column,"heart",STYLE.HEALTH)
	armor_bar = _row(column,"shield",STYLE.ARMOR)
	cold_bar = _row(column,"cold",STYLE.COLD)
	cold_row = cold_bar.get_parent(); cold_icon=cold_row.get_child(0); cold_row.hide(); cold_row.modulate.a=0
	cold_label = STYLE.label("",14,STYLE.TEXT); cold_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; column.add_child(cold_label); cold_label.hide()
func _row(column: VBoxContainer, symbol: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",10); column.add_child(row)
	row.add_child(GLYPH.new(symbol,color))
	var bar := ProgressBar.new(); bar.show_percentage=false; bar.custom_minimum_size=Vector2(120,6)
	bar.size_flags_vertical=SIZE_SHRINK_CENTER; bar.mouse_filter=MOUSE_FILTER_IGNORE
	var bg := STYLE.compact(false,3,Vector2.ZERO); bg.bg_color=STYLE.SURFACE; bg.shadow_size=0
	var fill := bg.duplicate(); fill.bg_color=color; fill.set_border_width_all(0)
	bar.add_theme_stylebox_override("background",bg); bar.add_theme_stylebox_override("fill",fill)
	row.add_child(bar); return bar
func update_status(health: float, armor: float, thermal: Dictionary, delta: float) -> void:
	_value(health_bar,health); _value(armor_bar,armor)
	var temperature := clampf(float(thermal.get("temperature",100)),0,100)
	_value(cold_bar,temperature)
	var relevant := bool(thermal.get("visible",false)) or temperature < 99.5
	_cold_hold = 3.0 if relevant else maxf(0,_cold_hold-delta)
	var show_cold := relevant or _cold_hold>0
	cold_label.visible=show_cold
	if show_cold:
		cold_label.text="%s · %d%%" % [str(thermal.get("text","")).get_slice("\n",0),roundi(temperature)]
	if show_cold != _cold_visible:
		_cold_visible=show_cold
		if _cold_tween: _cold_tween.kill()
		cold_row.show()
		_cold_tween=create_tween()
		_cold_tween.tween_property(cold_row,"modulate:a",1.0 if show_cold else 0.0,STYLE.FADE)
		if not show_cold: _cold_tween.tween_callback(func(): cold_row.hide(); reset_size())
	var pulse := show_cold and temperature<35 and str(thermal.get("key","")) in ["exposed","hypothermia"]
	if pulse and (_pulse==null or not _pulse.is_running()):
		_pulse=create_tween().set_loops(); _pulse.tween_property(cold_icon,"modulate:a",.45,.65); _pulse.tween_property(cold_icon,"modulate:a",1.0,.65)
	elif not pulse and _pulse:
		_pulse.kill(); cold_icon.modulate.a=1
func _value(bar: ProgressBar, value: float) -> void:
	var key := bar.get_instance_id()
	if _values.get(key,-1)==value: return
	if _tweens.has(key): _tweens[key].kill()
	if not _values.has(key): bar.value=value
	else:
		var tween := create_tween(); tween.tween_property(bar,"value",value,STYLE.FADE); _tweens[key]=tween
	_values[key]=value
