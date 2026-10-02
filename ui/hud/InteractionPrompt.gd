extends PanelContainer
const STYLE := preload("res://ui/GameStyle.gd")
var key: Label
var caption: Label
var _text := ""
var _tween: Tween
func _ready() -> void:
	name="InteractionPrompt"; mouse_filter=MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",STYLE.compact(false,6,Vector2(10,6)))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",8); add_child(row)
	key=STYLE.label("",15); key.add_theme_stylebox_override("normal",STYLE.compact(true,4,Vector2(5,1))); row.add_child(key)
	caption=STYLE.label("",15); caption.autowrap_mode=TextServer.AUTOWRAP_OFF; row.add_child(caption); hide()
func update_prompt(text: String, action: String, controls: Node) -> void:
	var hint := str(controls.prompt(action))
	for prefix in [hint+"  ",hint+" ","["+hint+"] ","E  ","E ","F  ","F "]:
		if text.begins_with(prefix): text=text.trim_prefix(prefix); break
	if text == "Atender telefone": text = "Atender"
	key.text=hint; key.visible=hint!="—"; caption.text=text
	if text==_text: return
	_text=text
	if _tween: _tween.kill()
	if text.is_empty(): hide(); return
	show(); modulate.a=0; _tween=create_tween(); _tween.tween_property(self,"modulate:a",1.0,STYLE.FADE)
func follow_actor(_actor: Node3D, _camera: Camera3D, extent: Vector2) -> void:
	if not visible: return
	reset_size()
	position=Vector2((extent.x-size.x)*.5,extent.y-size.y-28).round()
