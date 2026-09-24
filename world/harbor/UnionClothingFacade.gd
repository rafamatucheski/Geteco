extends Node2D
## Union's roof and street frontage cover the physical room until entry.

var entrance: BuildingEntrance
var inline_room: Node2D
var door_blocker: CollisionShape2D

func _ready() -> void:
	z_index = 6
	set_process(false)
	var sign := Label.new()
	sign.text = "U N I O N"
	sign.position = Vector2(-87, 7)
	sign.size = Vector2(174, 26)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_theme_font_size_override("font_size", 19)
	sign.add_theme_color_override("font_color", Color("f2dfb6"))
	add_child(sign)
	queue_redraw()

func bind_inline(door: BuildingEntrance, room: Node2D) -> void:
	entrance = door
	inline_room = room
	var body := StaticBody2D.new()
	body.name = "SlidingDoorSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	door_blocker = CollisionShape2D.new()
	door_blocker.name = "DoorLeaves"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(44, 9)
	door_blocker.shape = shape
	door_blocker.position = Vector2(0, 81)
	body.add_child(door_blocker)
	set_process(true)

func set_inline_occupied(occupied: bool) -> void:
	visible = not occupied
	if is_instance_valid(entrance): entrance.visible = not occupied

func _process(_delta: float) -> void:
	if not is_instance_valid(entrance): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(actor) and actor.get("is_dead") != true:
		var local := entrance.to_local(actor.global_position)
		if absf(local.x) < 43 and absf(local.y) < 66:
			entrance._away_time = 0.0
			entrance.open_door()
	if is_instance_valid(door_blocker): door_blocker.disabled = entrance.open_amount >= .55

func _draw() -> void:
	# The roof sits within the original 230 x 180 px lot. It disappears with
	# this facade when the player crosses the threshold.
	draw_rect(Rect2(-108, -85, 216, 91), Color("394847"))
	draw_rect(Rect2(-103, -81, 206, 83), Color("505e59"))
	for y in [-66, -43, -20]:
		draw_line(Vector2(-96, y), Vector2(96, y), Color("2a3c3b"), 2)
	draw_rect(Rect2(-108, 2, 216, 5), Color("c2a676"))
	draw_rect(Rect2(-108, 5, 216, 85), Color("273d3c"))
	draw_rect(Rect2(-102, 8, 204, 25), Color("203331"))
	draw_line(Vector2(-100, 34), Vector2(100, 34), Color("bca275"), 2)
	for side in [-1, 1]:
		var x: float = side * 69.0
		draw_rect(Rect2(x-28, 41, 56, 43), Color("bda77f"))
		draw_rect(Rect2(x-25, 44, 50, 36), Color("435d61"))
		_draw_dressed_mannequin(x, side > 0)
		draw_line(Vector2(x-22,46),Vector2(x-5,46),Color("ddd6b9"),1)
		draw_rect(Rect2(x-25,82,50,4),Color("263530"))
	# Door stays exposed in the central opening, with a small woven welcome mat.
	draw_rect(Rect2(-30,37,60,53),Color("172a2b"))
	draw_rect(Rect2(-30,108,60,12),Color("74644a"))
	for i in 6:
		draw_line(Vector2(-27+i*10,109),Vector2(-27+i*10,118),Color("8d7b5e"),1)

func _draw_dressed_mannequin(x: float, long_coat: bool) -> void:
	# A complete 29-unit figure fits inside the glass with breathing room.
	var ivory := Color("e3d8c3")
	var coat := Color("c09868") if long_coat else Color("6595a5")
	var trousers := Color("343a42") if long_coat else Color("243745")
	draw_ellipse_base(Vector2(x, 78))
	draw_line(Vector2(x, 74), Vector2(x, 78), Color("9c9989"), 0.8)
	# Separate legs and shoes make the silhouette human at street scale.
	draw_line(Vector2(x-2, 64), Vector2(x-2.5, 74), trousers, 2.8)
	draw_line(Vector2(x+2, 64), Vector2(x+3, 74), trousers, 2.8)
	draw_line(Vector2(x-4, 75), Vector2(x-1, 75), Color("172329"), 1.8)
	draw_line(Vector2(x+2, 75), Vector2(x+5, 75), Color("172329"), 1.8)
	draw_line(Vector2(x, 53), Vector2(x, 56), ivory, 1.8)
	draw_circle(Vector2(x, 51), 2.2, ivory)
	var hem := 68.0 if long_coat else 64.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x-3.5,55), Vector2(x+3.5,55),
		Vector2(x+3,61), Vector2(x+4,hem),
		Vector2(x-4,hem), Vector2(x-3,61)]), coat)
	for arm in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([
			Vector2(x+arm*3,56), Vector2(x+arm*5,60),
			Vector2(x+arm*5.5,64)]), coat.darkened(0.1), 2.2, true)
		draw_circle(Vector2(x+arm*5.5,65), 1.0, ivory)
	draw_line(Vector2(x,57), Vector2(x,hem-0.5), coat.darkened(0.35), 0.6)
	draw_polyline(PackedVector2Array([
		Vector2(x-2,55), Vector2(x,58), Vector2(x+2,55)]), ivory, 0.9, true)

func draw_ellipse_base(at: Vector2) -> void:
	draw_set_transform(at, 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, 8, Color("263b3d"))
	draw_set_transform(Vector2.ZERO)
