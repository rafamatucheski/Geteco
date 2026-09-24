extends Node3D
## Native adaptation of MountainLakeWater: source durations, palette and /16 scale.
## Cosmetic only: no swimming, damage, movement or collision changes.
const MAX_MARKS := 48
var marks: Array[Dictionary] = []
var wet_steps := 0
var last_lake: WeakRef
var mesh_node: MeshInstance3D
var geometry := ImmediateMesh.new()
var drawing := false
var material := StandardMaterial3D.new()
func _ready() -> void:
	mesh_node = MeshInstance3D.new()
	mesh_node.mesh = geometry
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node.material_override = material
	add_child(mesh_node)
	set_process(false)
func clear_trail() -> void:
	if wet_steps==0 and last_lake==null and marks.is_empty(): return
	wet_steps = 0
	last_lake = null
	marks.clear()
	geometry.clear_surfaces()
	set_process(false)
func _deck(lake: Node3D,point: Vector3) -> bool:
	var local := lake.to_local(point)
	return lake.variant=="secret" and absf(local.x)<1.7 and local.z>-13.6 and local.z<9.7
func actor_step(actor: CharacterBody3D,sprinting: bool,interior: bool) -> bool:
	if interior or not actor.is_visible_in_tree():
		clear_trail()
		return false
	var lake: Node3D
	for candidate in get_tree().get_nodes_in_group("native_water_surface"):
		if candidate.is_visible_in_tree() and absf(actor.global_position.y-candidate.global_position.y)<.5 and candidate.contains_water(actor.global_position):
			lake = candidate
			break
	var water := lake!=null
	if water:
		wet_steps = 6
		last_lake = weakref(lake)
	else:
		lake = last_lake.get_ref() if last_lake!=null else null
		if not is_instance_valid(lake) or _deck(lake,actor.global_position):
			wet_steps = 0
			return false
		if wet_steps<=0: return false
		wet_steps-=1
	var heading := Vector2(actor.velocity.x,actor.velocity.z).normalized()
	if heading.is_zero_approx(): heading = Vector2.DOWN
	var side := 1.0 if marks.size()%2==0 else -1.0
	var offset := heading.orthogonal()*side*3.0/16.0
	var point := actor.global_position+Vector3(offset.x,0,offset.y)
	point.y = lake.global_position.y+.058 if water else actor.global_position.y+.015
	marks.append({"point":point,"age":0.0,"water":water,"heading":heading,"sprint":sprinting,"lake":weakref(lake)})
	if marks.size()>MAX_MARKS: marks.pop_front()
	set_process(true)
	return water
func _process(delta: float) -> void:
	for mark in marks: mark.age+=delta
	marks = marks.filter(func(mark): return mark.age<(0.85 if mark.water else 4.5) and is_instance_valid(mark.lake.get_ref()))
	geometry.clear_surfaces()
	if marks.is_empty():
		set_process(false)
		return
	drawing = false
	for mark in marks:
		var point: Vector3 = mark.point
		var age: float = mark.age
		var lake: Node3D = mark.lake.get_ref()
		if mark.water:
			var radius := (3.0+age*(24.0 if mark.sprint else 17.0))/16.0
			var color := Color(.62,.88,.90,(1-age/.85)*.65)
			for i in 24:
				var a := point+Vector3(cos(TAU*i/24.0),0,sin(TAU*i/24.0)*.55)*radius
				var b := point+Vector3(cos(TAU*(i+1)/24.0),0,sin(TAU*(i+1)/24.0)*.55)*radius
				if lake.contains_water(a) and lake.contains_water(b): _line(a,b,1.0/16,color)
			for drop in 4:
				var offset := Vector2.from_angle(drop*PI*.5+.4)*age*15.0/16.0
				var at := point+Vector3(offset.x,0,offset.y)
				if lake.contains_water(at):
					at.y+=sin(age/.85*PI)*7.0/16.0
					_disc(at,1.1/16,Vector2.RIGHT,1,Color(.65,.87,.91,(1-age/.85)*.8))
		else:
			_disc(point,3.4/16,mark.heading,.5,Color(.06,.10,.09,(1-age/4.5)*.5))
	if drawing: geometry.surface_end()
func _vertex(point: Vector3,color: Color) -> void:
	if not drawing:
		geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		drawing = true
	geometry.surface_set_color(color)
	geometry.surface_add_vertex(to_local(point))
func _line(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	var side := Vector3(-(b-a).z,0,(b-a).x).normalized()*width*.5
	for point in [a-side,b-side,b+side,a-side,b+side,a+side]: _vertex(point,color)
func _disc(center: Vector3,radius: float,heading: Vector2,flatten: float,color: Color) -> void:
	var normal := heading.orthogonal()
	for i in 8:
		var a := (heading*cos(TAU*i/8.0)+normal*sin(TAU*i/8.0)*flatten)*radius
		var b := (heading*cos(TAU*(i+1)/8.0)+normal*sin(TAU*(i+1)/8.0)*flatten)*radius
		_vertex(center,color)
		_vertex(center+Vector3(a.x,0,a.y),color)
		_vertex(center+Vector3(b.x,0,b.y),color)
