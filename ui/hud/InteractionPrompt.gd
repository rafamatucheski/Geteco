extends PanelContainer
const STYLE := preload("res://ui/GameStyle.gd")
var key: Label
var caption: Label
var _text := ""
var _tween: Tween
func _ready() -> void:
	name="InteractionPrompt"; mouse_filter=MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",STYLE.compact(false,6,Vector2(7,5)))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",8); add_child(row)
	key=STYLE.label("",15); key.add_theme_stylebox_override("normal",STYLE.compact(true,4,Vector2(5,1))); row.add_child(key)
	caption=STYLE.label("",16); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; row.add_child(caption); hide()
func update_prompt(text: String, action: String, controls: Node) -> void:
	var hint := str(controls.prompt(action))
	for prefix in [hint+"  ",hint+" ","["+hint+"] ","E  ","E ","F  ","F "]:
		if text.begins_with(prefix): text=text.trim_prefix(prefix); break
	key.text=hint; key.visible=hint!="—"; caption.text=text
	if text==_text: return
	_text=text
	if _tween: _tween.kill()
	if text.is_empty(): hide(); return
	show(); modulate.a=0; _tween=create_tween(); _tween.tween_property(self,"modulate:a",1.0,STYLE.FADE)
func follow_actor(actor: Node3D, camera: Camera3D, extent: Vector2) -> void:
	if not visible or camera.is_position_behind(actor.global_position): return
	caption.custom_minimum_size.x=minf(260,maxf(80,caption.get_minimum_size().x))
	reset_size()
	var point := camera.unproject_position(actor.global_position+Vector3.UP*1.9)+Vector2(20,-12)
	position=Vector2(clampf(point.x,24,extent.x-size.x-24),clampf(point.y,90,extent.y-size.y-110)).round()
