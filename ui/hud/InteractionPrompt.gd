extends PanelContainer
const STYLE := preload("res://ui/GameStyle.gd")
var key: Label
var caption: Label
var _row: HBoxContainer
var _text := ""
var _tween: Tween
func _ready() -> void:
	name="InteractionPrompt"; mouse_filter=MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",STYLE.compact(false,6,Vector2(10,6)))
	_row = HBoxContainer.new(); _row.add_theme_constant_override("separation",8); add_child(_row)
	key=STYLE.label("",13); key.add_theme_stylebox_override("normal",STYLE.compact(true,4,Vector2(5,1))); _row.add_child(key)
	key.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; key.size_flags_vertical=SIZE_SHRINK_CENTER
	caption=STYLE.label("",13); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.size_flags_horizontal=SIZE_EXPAND_FILL; _row.add_child(caption); hide()
## `text` é só a legenda; a tecla vem da ação (GameInput.prompt), sem cortar prefixo de frase.
func update_prompt(text: String, action: String, controls: Node) -> void:
	var hint := str(controls.prompt(action))
	key.text=hint; key.visible=hint!="—"; caption.text=text
	if text==_text: return
	_text=text
	if _tween: _tween.kill()
	if text.is_empty(): hide(); return
	show(); modulate.a=0; _tween=create_tween(); _tween.tween_property(self,"modulate:a",1.0,STYLE.FADE)
func follow_actor(_actor: Node3D, _camera: Camera3D, extent: Vector2) -> void:
	layout_in_rect(Rect2(Vector2(24,24),Vector2(maxf(1,extent.x-48),maxf(1,extent.y-52))))

func layout_in_rect(area: Rect2) -> void:
	if not visible: return
	# Reserva a largura real da tecla antes de quebrar a ação. A largura vem
	# da área livre do HUD, e texto mais longo pode crescer para cima.
	var padding := get_theme_stylebox("panel").get_minimum_size().x
	var gap := float(_row.get_theme_constant("separation")) if key.visible else 0.0
	var available := maxf(1, area.size.x-padding-gap)
	var key_width := 0.0
	if key.visible:
		var natural_key := _text_width(key)+key.get_theme_stylebox("normal").get_minimum_size().x
		key_width = minf(natural_key,maxf(1,available-minf(48,available*.4)))
		key.custom_minimum_size.x=key_width
		key.size.x=key_width
	var body_width := minf(_text_width(caption),maxf(1,available-key_width))
	caption.custom_minimum_size.x=body_width
	caption.size.x=body_width
	size=Vector2(padding+gap+key_width+body_width,0)
	reset_size()
	position=Vector2(area.position.x+(area.size.x-size.x)*.5,area.end.y-size.y).round()

func _text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := 0.0
	for line in label.text.split("\n"):
		width=maxf(width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	return ceilf(width)
