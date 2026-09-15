extends StaticBody2D
var debris_material := "wood"
var extent := Vector2(24,22)
var presentation: Node2D
var broken := false

func _ready() -> void:
	if debris_material in ["trash", "wood"]:
		preload("res://systems/ContactShadow.gd").add_box(self, extent * 1.05, 0.48)
	else:
		preload("res://systems/ContactShadow.gd").add_2d(self, extent * 1.18, 0.36)

func receive_vehicle_impact(speed: float, direction: Vector2) -> void:
	if broken or speed < (65.0 if debris_material == "wood" else 35.0): return
	broken = true
	if has_node("ContactShadow"): $ContactShadow.hide()
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(presentation): presentation.hide()
	preload("res://guns/ImpactDebris.gd").spawn(get_parent(),global_position,direction,speed,debris_material,extent)
	queue_redraw()

func _draw() -> void:
	if debris_material != "trash" or broken: return
	draw_style_box(_bin_style(),Rect2(-extent*.5,extent))
	draw_rect(Rect2(Vector2(-extent.x*.6,-extent.y*.6),Vector2(extent.x*1.2,4)),Color("72786c"))

func _bin_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("414b40")
	style.border_color = Color("798474")
	style.set_border_width_all(2)
	return style

func restore_world_prop() -> void:
	broken = false
	if has_node("ContactShadow"): $ContactShadow.show()
	if is_instance_valid(presentation): presentation.show()
	queue_redraw()
