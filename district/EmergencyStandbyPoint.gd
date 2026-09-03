class_name EmergencyStandbyPoint
extends Node2D

## A reserved police car waiting in an alley. It is deliberately not a traffic
## vehicle, so the generic lane spawner cannot claim or duplicate it.

@export var standby_id := "alley_unit_01"
@export var service_key := "police"
@export var available := true
@export var restore_after_seconds := 18.0

func _ready() -> void:
	add_to_group("emergency_standby_point")
	queue_redraw()

func claim() -> bool:
	if not available:
		return false
	available = false
	visible = false
	var collision := get_node_or_null("Body/CollisionShape2D") as CollisionShape2D
	if collision:
		collision.set_deferred("disabled", true)
	return true

func restore_after_return() -> void:
	await get_tree().create_timer(restore_after_seconds).timeout
	available = true
	visible = true
	var collision := get_node_or_null("Body/CollisionShape2D") as CollisionShape2D
	if collision:
		collision.set_deferred("disabled", false)
	queue_redraw()

func _draw() -> void:
	# Compact procedural top-down patrol car; a prop until dispatched.
	draw_rect(Rect2(-31, -14, 62, 28), Color("#182635"))
	draw_rect(Rect2(-20, -12, 40, 24), Color("#e4e8eb"))
	draw_rect(Rect2(-9, -11, 18, 22), Color("#293b52"))
	draw_rect(Rect2(-4, -15, 8, 4), Color("#2b72d6"))
	draw_rect(Rect2(4, -15, 8, 4), Color("#d94343"))
	draw_rect(Rect2(-27, -17, 14, 4), Color("#10151b"))
	draw_rect(Rect2(13, -17, 14, 4), Color("#10151b"))
	draw_rect(Rect2(-27, 13, 14, 4), Color("#10151b"))
	draw_rect(Rect2(13, 13, 14, 4), Color("#10151b"))
