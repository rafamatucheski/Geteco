extends PanelContainer
const STYLE := preload("res://ui/GameStyle.gd")
var heading: Label
var message: Label
var _tween: Tween
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",STYLE.compact(false,10))
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",3); add_child(column)
	heading=STYLE.label("",11,STYLE.ACCENT); column.add_child(heading)
	message=STYLE.label("",16); message.custom_minimum_size.x=260; message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	hide()
func present(text: String, title := "", duration := 2.6) -> void:
	if _tween: _tween.kill()
	message.text=text; heading.text=title; heading.visible=not title.is_empty()
	show(); modulate.a=0; scale=Vector2.ONE*.96
	_tween=create_tween(); _tween.set_parallel(true)
	_tween.tween_property(self,"modulate:a",1.0,STYLE.FADE)
	_tween.tween_property(self,"scale",Vector2.ONE,STYLE.FADE)
	_tween.chain().tween_interval(duration)
	_tween.chain().tween_property(self,"modulate:a",0.0,STYLE.FADE)
	_tween.chain().tween_callback(hide)
