extends Node2D
## A bounded wake remains in world space after the rocket moves or detonates.
const MAX_TRAILS := 12
const MAX_PUFFS := 24
var rocket: Node2D
var puffs: Array[Vector3] = []
var last := Vector2.ZERO
static var soft: GradientTexture2D

static func attach(projectile: Node2D) -> void:
	if projectile.get_tree().get_nodes_in_group("rocket_trails").size() >= MAX_TRAILS: return
	var trail := new()
	trail.rocket = projectile
	trail.last = projectile.global_position
	projectile.get_parent().add_child(trail)
	trail.global_position = Vector2.ZERO
	trail.puffs.append(Vector3(trail.last.x,trail.last.y,0))

func _ready() -> void:
	add_to_group("rocket_trails")
	z_as_relative = false
	z_index = 19
	if soft == null:
		soft = GradientTexture2D.new()
		soft.width = 32
		soft.height = 32
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(.5,.5)
		soft.fill_to = Vector2(1,.5)
		soft.gradient = Gradient.new()
		soft.gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
func _process(delta: float) -> void:
	for i in range(puffs.size()-1,-1,-1):
		puffs[i].z += delta
		if puffs[i].z > .55: puffs.remove_at(i)
	if is_instance_valid(rocket) and not rocket.is_queued_for_deletion():
		var point: Vector2 = rocket.global_position - rocket.direction * 16.0
		if point.distance_to(last)>9.0:
			last = point
			puffs.append(Vector3(point.x,point.y,0))
			if puffs.size()>MAX_PUFFS: puffs.pop_front()
	elif puffs.is_empty():
		queue_free()
		return
	queue_redraw()
func _draw() -> void:
	for puff in puffs:
		var age := puff.z/.55
		var radius := 2.0+age*7.0
		var point := to_local(Vector2(puff.x,puff.y))+Vector2(0,-age*5.0)
		draw_texture_rect(soft,Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2),false,Color(.58,.55,.48,(1.0-age)*.38))
