extends Node2D
## Mancha no piso acompanha o ponto do tronco durante a queda e depois fica parada.
var guard: Node2D

func _ready() -> void:
	name="BankGuardBloodPool"
	add_to_group("bank_guard_blood")
	z_as_relative=false
	z_index=5
	var rim := Polygon2D.new()
	rim.polygon=PackedVector2Array([Vector2(-18,-2),Vector2(-15,-7),Vector2(-7,-10),Vector2(2,-9),Vector2(11,-8),Vector2(18,-2),Vector2(16,5),Vector2(8,10),Vector2(-2,11),Vector2(-12,7)])
	rim.color=Color("60121b")
	add_child(rim)
	var core := Polygon2D.new()
	core.polygon=rim.polygon
	core.scale=Vector2(.80,.76)
	core.color=Color("911e29")
	add_child(core)
	scale=Vector2.ONE*.15
	_process(0)
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(self,"scale",Vector2.ONE*1.15,1.5)
	var fade := create_tween()
	fade.tween_interval(14)
	fade.tween_property(self,"modulate:a",0.0,3)
	fade.tween_callback(queue_free)

func _process(_delta: float) -> void:
	if not is_instance_valid(guard):
		set_process(false)
		return
	var camera: Camera3D=guard.viewport_3d.get_camera_3d()
	var pixel := camera.unproject_position(guard.torso_node.global_position)-Vector2(guard.viewport_3d.size)*.5
	global_position=guard.sprite_3d_display.to_global(pixel)+Vector2(0,3)
	if not guard.fall_presentation.active: set_process(false)
