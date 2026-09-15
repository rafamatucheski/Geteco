extends StaticBody2D

var is_exploding := true
var flames: CPUParticles2D

func _ready() -> void:
	var collision := CollisionShape2D.new()
	var footprint := RectangleShape2D.new()
	footprint.size = Vector2(30, 24)
	collision.shape = footprint
	add_child(collision)
	var bin := Polygon2D.new()
	bin.polygon=PackedVector2Array([Vector2(-15,-12),Vector2(15,-12),Vector2(15,12),Vector2(-15,12)])
	bin.color=Color("484f49")
	add_child(bin)
	flames=CPUParticles2D.new()
	flames.amount=22
	flames.lifetime=.9
	flames.direction=Vector2.UP
	flames.spread=30
	flames.gravity=Vector2(0,-20)
	flames.initial_velocity_min=12
	flames.initial_velocity_max=35
	flames.scale_amount_min=3
	flames.scale_amount_max=7
	flames.color=Color("f5a541")
	add_child(flames)

func extinguish_fire() -> void:
	is_exploding=false
	set_meta("service_complete", true)
	if is_instance_valid(flames): flames.emitting=false

func update_fire_suppression(progress: float) -> void:
	if not is_instance_valid(flames): return
	# The existing emitter shrinks with cooling; no additional emitters or lights.
	flames.scale_amount_max = lerpf(7.0, 2.0, progress)
	flames.scale_amount_min = lerpf(3.0, 0.8, progress)
	flames.initial_velocity_max = lerpf(35.0, 10.0, progress)
