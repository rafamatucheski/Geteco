extends Node2D
var age := 0.0
var heading := Vector2.RIGHT
static func spawn(actor: Node2D, origin: Vector2, direction: Vector2) -> void:
	var parent := preload("res://guns/combat/CombatWorld.gd").scene_for(actor)
	if actor.get_tree().get_nodes_in_group("rocket_backblasts").size()>=8: return
	var effect := new()
	effect.heading = direction.normalized()
	parent.add_child(effect)
	effect.global_position = origin-direction*18.0
func _ready() -> void:
	add_to_group("rocket_backblasts")
	z_index = 19
func _process(delta: float) -> void:
	age += delta
	if age>.38: queue_free()
	else: queue_redraw()
func _draw() -> void:
	var axis := -heading
	var side := axis.orthogonal()
	var fade := 1.0-age/.38
	for i in 5:
		var distance := float(i)*6.0+age*55.0
		var position := axis*distance + side*sin(i*2.3)*age*10.0
		draw_circle(position,2.0+i*1.1+age*9.0,Color(.52,.48,.4,fade*.12))
	if age<.065:
		var points := PackedVector2Array([side*2.0,axis*25.0+side*4.0,axis*35.0,axis*25.0-side*4.0,-side*2.0])
		draw_colored_polygon(points,Color(1,.72,.27,(1-age/.065)*.6))
