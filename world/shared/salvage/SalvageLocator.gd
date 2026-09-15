extends Control
## Nearby yard discovery and live contract direction in both generations.
var yard: Node2D
var _elapsed:=0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-234
	offset_right=-26
	offset_top=216
	offset_bottom=280

func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed<.2: return
	_elapsed=0
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(yard): return
	var player:=get_tree().get_first_node_in_group("player") as Node2D
	if player==null: return
	if player.get_meta("mountain_interior", false) or player.get_meta("harbor_interior", false): return
	var target: Vector2=yard.navigation_target()
	if target == Vector2.ZERO: return
	var origin:=player.global_position
	var car: Node2D=get_node("/root/RegionTravel").controlled_car()
	if car!=null: origin=car.global_position
	var background:=Rect2(Vector2.ZERO,Vector2(208,64))
	draw_style_box(preload("res://ui/GameStyle.gd").panel(),background)
	var center:=Vector2(25,31)
	var direction:=origin.direction_to(target)
	draw_circle(center,14,Color("334c3e"))
	draw_line(center-direction*6,center+direction*9,Color("f5ce7e"),2,true)
	draw_line(center+direction*9,center+direction.rotated(2.5)*6,Color("f5ce7e"),2,true)
	draw_line(center+direction*9,center+direction.rotated(-2.5)*6,Color("f5ce7e"),2,true)
	var font:=ThemeDB.fallback_font
	var en:=TranslationServer.get_locale().begins_with("en")
	draw_string(font,Vector2(49,25),"ENCOMENDA" if not en else "ORDER",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f5ce7e"))
	draw_string(font,Vector2(49,46),"%d m" % roundi(origin.distance_to(target)/16.6),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("e2e5da"))
