extends Node2D
var token := ""

func _ready() -> void:
	z_index=45
	queue_redraw()

func _process(_delta: float) -> void:
	if String(get_parent().get_meta("salvage_token",""))!=token:
		queue_free()
		return
	global_rotation=0
	var player:=get_tree().get_first_node_in_group("player") as Node2D
	visible=player!=null and player.global_position.distance_to(global_position)<1000 and get_parent().get("is_driven_by_player")!=true

func _draw() -> void:
	var p:=Vector2(0,-60)
	draw_colored_polygon(PackedVector2Array([p+Vector2(0,-9),p+Vector2(9,0),p+Vector2(0,9),p+Vector2(-9,0)]),Color("f3cb63"))
	draw_string(ThemeDB.fallback_font,p+Vector2(-20,-16),"NECO",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f9dfa0"))
