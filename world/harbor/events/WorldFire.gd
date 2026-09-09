extends Node2D

var is_exploding := true
var flames: CPUParticles2D

func _ready() -> void:
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
	flames.emitting=false
