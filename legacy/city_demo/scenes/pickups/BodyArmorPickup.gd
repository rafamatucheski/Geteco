class_name BodyArmorPickup
extends Area2D

## World pickup for a ballistic vest.  This scene is deliberately independent of
## the player implementation: it only needs Player.add_armor(amount).

@export_range(1, 200, 1) var armor_amount: int = 50
@export var interaction_radius: float = 42.0

var _nearby_player: Node2D
var _art_root: Node2D
var _time := 0.0
var _consumed := false

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 4
	
	_ensure_collision()
	_ensure_art()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	if _consumed: return
	_art_root.position.y = sin(_time * 3.2) * 1.5
	_art_root.rotation = _time * 1.6
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _consumed or _nearby_player == null:
		return
	if event.is_action_pressed("interact"):
		_take(_nearby_player)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	# Small procedural outline/prompt; art stays crisp with no external PNG.
	if _nearby_player != null and not _consumed:
		draw_arc(Vector2.ZERO, interaction_radius, 0.0, TAU, 32, Color(0.2, 0.85, 1.0, 0.7), 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(-29, -35), "COLETE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.93, 1.0))

func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape2D") != null:
		return
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)

func _ensure_art() -> void:
	_art_root = Node2D.new()
	_art_root.name = "VestArt"
	add_child(_art_root)
	# Compact 10 x 15 silhouette: shoulder straps, open neck and tapered waist.
	_piece([Vector2(-5,-7.5),Vector2(-2,-7.5),Vector2(-1.5,-4),Vector2(1.5,-4),Vector2(2,-7.5),Vector2(5,-7.5),Vector2(4.5,-2),Vector2(5,0),Vector2(4,7.5),Vector2(-4,7.5),Vector2(-5,0),Vector2(-4.5,-2)], Color("182b38"))
	_piece([Vector2(-3.8,-2.8),Vector2(3.8,-2.8),Vector2(3,5.8),Vector2(-3,5.8)], Color("46677d"))
	_piece([Vector2(-3,-2),Vector2(3,-2),Vector2(2.6,1),Vector2(-2.6,1)], Color("7798ac"))
	for x in [-2.8, 0.4]:
		_piece([Vector2(x,2),Vector2(x+2.4,2),Vector2(x+2.4,5),Vector2(x,5)], Color("263e50"))
	for x in [-4.1, 2.5]:
		_piece([Vector2(x,-6),Vector2(x+1.6,-6),Vector2(x+1.6,-4.8),Vector2(x,-4.8)], Color("a8c3ce"))

func _piece(points: Array, color: Color) -> void:
	var part := Polygon2D.new()
	part.polygon = PackedVector2Array(points)
	part.color = color
	part.antialiased = true
	_art_root.add_child(part)

func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		_nearby_player = body
		_take(body)

func _on_body_exited(body: Node2D) -> void:
	if body == _nearby_player:
		_nearby_player = null

func _is_player(body: Node) -> bool:
	return body.has_method("add_armor") or body.is_in_group("player")

func _take(player: Node) -> void:
	if _consumed or not player.has_method("add_armor"):
		return
	_consumed = true
	player.add_armor(armor_amount)
	picked_up.emit(player, armor_amount)

	preload("res://audio/rewards/RewardAudioBank.gd").play(self, "pickup")

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.4, 1.4), 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(queue_free)

signal picked_up(player: Node, amount: int)
