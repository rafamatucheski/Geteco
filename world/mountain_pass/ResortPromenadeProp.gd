extends "res://world/mountain_pass/MountainProjectedExterior.gd"
var kind := "brazier"
func _ready() -> void:
	z_index = 5
	build_view(preload("res://world/mountain_pass/ResortPromenadeProp3D.gd"),6.5 if kind=="brazier" else 4.2,18.0,Vector3(0,1.0,0),Vector3(0,13,11),Vector2i(320,320))
	model.build(kind)
	depth_bounds = Rect2(-3.0,-2.0,6.0,4.0) if kind=="brazier" else Rect2(-1.5,-1.1,3.0,2.2)
	install_projected_solids()
	if kind == "brazier":
		var heat := Area2D.new()
		heat.name = "PromenadeBrazierHeat"
		heat.add_to_group("heat_source")
		var collision := CollisionShape2D.new()
		collision.shape = CircleShape2D.new()
		collision.shape.radius = 280.0
		heat.add_child(collision)
		add_child(heat)
