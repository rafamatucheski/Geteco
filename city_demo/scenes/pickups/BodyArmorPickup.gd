class_name BodyArmorPickup
extends Area2D

## World pickup for a ballistic vest.  This scene is deliberately independent of
## the player implementation: it only needs Player.add_armor(amount).

@export_range(1, 200, 1) var armor_amount: int = 50
@export var interaction_radius: float = 42.0

var _nearby_player: Node2D
var _base_y: float
var _time := 0.0
var _consumed := false

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1
	_base_y = position.y
	_ensure_collision()
	_ensure_art()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.6) * 2.0
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
		draw_string(ThemeDB.fallback_font, Vector2(-29, -35), "[E] COLETE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.93, 1.0))

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
	if get_node_or_null("VestArt") != null:
		return
	var vest := Polygon2D.new()
	vest.name = "VestArt"
	vest.polygon = PackedVector2Array([
		Vector2(-7, -9), Vector2(-3, -11), Vector2(0, -8), Vector2(3, -11),
		Vector2(7, -9), Vector2(6, 9), Vector2(3, 11), Vector2(0, 8),
		Vector2(-3, 11), Vector2(-6, 9)
	])
	vest.color = Color("23516d")
	add_child(vest)
	var plate := Polygon2D.new()
	plate.name = "ArmorPlate"
	plate.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(3, 6), Vector2(-3, 6)])
	plate.color = Color("75c9e9")
	vest.add_child(plate)

func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		_nearby_player = body

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
	queue_free()

signal picked_up(player: Node, amount: int)
