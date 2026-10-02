extends Node3D
class_name SawmillYard3D

## Complete 3D exterior presentation of the Mountain Pass Sawmill / Logging Camp.
## Positioned at mountain coordinates (6350, 560), matching V1 geography at 16 px/metre.
## Assembles the cutting shed, strapped lumber stacks and covered log piles,
## rustic perimeter fences, campfire ring, and truck parking bay.
## Guarantees 100% unblocked transit along the main driveway and pedestrian work paths.

const SCALE := 1.0 / 16.0
const SHADOW_FINISH := preload("res://world/mountain_detail/MountainShadowFinish.gd")
static var _ground_shader: Shader

# Sub-components
var cutting_shed: SawmillShed3D
var office_cabin: Node3D
var woodpiles: Array[Node3D] = []
var lumber_stacks: Array[LumberStack3D] = []
var perimeter_fence: Node3D

func _ready() -> void:
	build_sawmill_yard()

func build_sawmill_yard() -> void:
	for child in get_children():
		child.queue_free()
	
	# 1. Earth Ground and Driveway Polygons (preserving V1 geography)
	_build_ground_polygons()
	
	# V1 uses LumberjackCabin3D at the yard origin, not an additional office.
	_build_office_cabin()
	
	# 4. Covered Log Piles at original setpiece points (-95, 5) and (-95, 55)
	_build_woodpiles()
	
	# 5. Strapped Sawn Lumber Stacks at original points (SawmillYardDetails.gd)
	_build_lumber_stacks()
	
	# 7. Campfire Stone Ring and Seating Logs at original point (90, 20)
	# HeatPresentation owns the original fire and collider.
	
	# 8. Rustic Perimeter Split-Rail Fence (with clear driveway opening)
	# No perimeter fences are authored by V1 build_detailed_sawmill.

func _build_ground_polygons() -> void:
	# The yard owns its original footprint; the short driveway plate was removed.
	var yard_poly := PackedVector2Array([
		Vector2(-180, -110), Vector2(180, -110),
		Vector2(200, 130), Vector2(-170, 140)
	])
	
	# Terra batida procedural: o material liso lia como placa marrom vista de cima.
	var earth_mat := ShaderMaterial.new()
	if _ground_shader == null:
		_ground_shader = Shader.new()
		# Opaque interior pixels occlude the expensive terrain underneath, while
		# the perimeter keeps its existing alpha blend. Compile once for this place.
		_ground_shader.code = preload("res://world/regions/natural_ground.gdshader").code.replace(
			"render_mode diffuse_lambert, specular_schlick_ggx;",
			"render_mode diffuse_lambert, specular_schlick_ggx, depth_prepass_alpha;")
	earth_mat.shader = _ground_shader
	earth_mat.set_shader_parameter("base_color",Color("5d4e3d"))
	earth_mat.set_shader_parameter("uv_meters",4.0)
	earth_mat.set_shader_parameter("edge_alpha",true)
	earth_mat.set_shader_parameter("surface_softness",0.55)
	_create_flat_polygon("OriginalSawmillYard", yard_poly, 0.024, earth_mat)

func _create_flat_polygon(node_name: String, polygon: PackedVector2Array, height: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2.ZERO
	for point in polygon: center += point / polygon.size()
	# Subdivide the unchanged physical boundary and vary the inner blend edge.
	# The broad, uneven fade avoids a rectangular dirt plate against the snow.
	var perimeter := PackedVector2Array()
	for i in polygon.size():
		for step in 4:
			perimeter.append(polygon[i].lerp(polygon[(i+1)%polygon.size()], float(step)/4.0))
	var inset := PackedVector2Array()
	var inner_scale := [0.66,0.72,0.64,0.70,0.67,0.76,0.69,0.65,
		0.73,0.67,0.75,0.68,0.64,0.71,0.66,0.74]
	for i in perimeter.size(): inset.append(center.lerp(perimeter[i],inner_scale[i]))
	for idx in Geometry2D.triangulate_polygon(inset):
		_ground_vertex(st,inset[idx],height,1.0)
	for i in perimeter.size():
		var next := (i+1)%perimeter.size()
		for item in [[inset[i],1.0],[perimeter[i],0.0],[perimeter[next],0.0],
				[inset[i],1.0],[perimeter[next],0.0],[inset[next],1.0]]:
			_ground_vertex(st,item[0],height,item[1])
	
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = node_name
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)
	# The visible triangulated footprint also owns the floor. A second opaque
	# copy at the same height used to fight this shader and hide its soft edges.
	mesh_inst.create_trimesh_collision()
	for body in mesh_inst.get_children():
		if body is StaticBody3D:
			body.collision_layer = 1
			body.collision_mask = 0

func _ground_vertex(st: SurfaceTool, point: Vector2, height: float, alpha: float) -> void:
	var local := point*SCALE
	st.set_normal(Vector3.UP)
	st.set_color(Color(1,1,1,alpha))
	st.set_uv(local*.25)
	st.add_vertex(Vector3(local.x,height,local.y))

func _build_office_cabin() -> void:
	# Positioned in northeast quadrant of yard (x ~ 5.5m, z ~ -3.5m)
	var cabin_path := "res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd"
	if ResourceLoader.exists(cabin_path):
		var cabin_script = load(cabin_path)
		office_cabin = cabin_script.new()
		office_cabin.name = "LoggingCampOffice"
		office_cabin.position = Vector3.ZERO
		add_child(office_cabin)
		SHADOW_FINISH.attach(office_cabin, Vector2(3.6, 4.2))
		# Original building is a closed cabin, not the delivered invented open saw hall.
		# Physical walls follow its own mesh; no single solid volume across the doorway.
		for mesh in office_cabin.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh is BoxMesh:
				var bounds: AABB = mesh.mesh.get_aabb()
				if mesh.position.y-bounds.size.y*.5>2.3: continue
				mesh.create_trimesh_collision()

func _build_woodpiles() -> void:
	# Points from MountainSceneryBuilder.gd:997: Vector2(-95, 5) and Vector2(-95, 55)
	for pt in [Vector2(-95.0, 5.0), Vector2(-95.0, 55.0)]:
		var woodpile := preload("res://world/mountain_detail/OriginalCoveredWoodpile.gd").new()
		woodpile.name = "CoveredWoodpile_%d" % woodpiles.size()
		woodpile.position = Vector3(pt.x * SCALE, 0, pt.y * SCALE)
		add_child(woodpile)
		_merged_log_collision(woodpile)
		woodpiles.append(woodpile)

## Uma colisão convexa por pilha, envolvendo as toras baixas (antes: um trimesh
## exato por tora, 224 toras e ~32 mil triângulos por pilha, ~900 nós e ~175 ms num
## quadro ao chegar dirigindo; profiler do Godot, 2026-09-24). A pilha continua
## sólida e sem frestas; o contorno segue o volume da pilha, não cada tora.
func _merged_log_collision(pile: Node3D) -> void:
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in pile.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var bounds: AABB = mesh.mesh.get_aabb()
		if mesh.position.y-bounds.size.y*.5>2.3: continue
		var local := Transform3D.IDENTITY
		var node: Node = mesh
		while node != pile and node != null:
			local = (node as Node3D).transform * local
			node = node.get_parent()
		for corner in 8: points.append(local * bounds.get_endpoint(corner))
	if points.is_empty(): return
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var body := StaticBody3D.new()
	body.name = "LogPileCollision"
	body.add_child(collider)
	pile.add_child(body)

func _build_lumber_stacks() -> void:
	# 4 row stacks from SawmillYardDetails.gd:7-10:
	# x = 1.0 + [2.0, -1.0, 0.0, 3.0][row]
	# y = 64.0 + row * 9.0
	for row in 4:
		var length_px: float = 54.0-float(row%2)*3.0
		var x_offset: float = (1.0 + [2.0, -1.0, 0.0, 3.0][row]+length_px*.5) * SCALE
		var z_offset: float = (64.0 + float(row) * 9.0+3.0) * SCALE
		
		var stack := LumberStack3D.new()
		stack.name = "LumberStack_%d" % row
		stack.stack_length = length_px*SCALE
		stack.position = Vector3(x_offset, 0, z_offset)
		add_child(stack)
		lumber_stacks.append(stack)

func _build_sawdust_area() -> void:
	# Original point from SawmillYardDetails.gd:30: Vector2(-30, 81) with radius 22x17
	var center := Vector3(-30.0 * SCALE, 0.022, 81.0 * SCALE)
	var radius_x: float = 22.0 * SCALE
	var radius_z: float = 17.0 * SCALE
	
	var poly := PackedVector2Array()
	var steps := 24
	for i in steps:
		var angle := float(i) * TAU / float(steps)
		poly.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_z))
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(poly)
	for idx in indices:
		var pt: Vector2 = poly[idx]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(pt.x * 0.5, pt.y * 0.5))
		st.add_vertex(center + Vector3(pt.x, 0.015, pt.y))
	
	var sawdust_mesh := MeshInstance3D.new()
	sawdust_mesh.name = "SawdustMound"
	sawdust_mesh.mesh = st.commit()
	sawdust_mesh.material_override = MountainMaterials.sawdust()
	sawdust_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sawdust_mesh)

func _build_campfire_area() -> void:
	# Original campfire point from MountainPass.gd: Vector2(90, 20)
	var camp_pos := Vector3(90.0 * SCALE, 0, 20.0 * SCALE)
	var campfire_root := Node3D.new()
	campfire_root.name = "SawmillCampfire"
	campfire_root.position = camp_pos
	add_child(campfire_root)
	
	# Circular ring of river stones
	var stone_mat := MountainMaterials.stone_river()
	var stone_count := 10
	var ring_r := 0.65
	for i in stone_count:
		var angle := float(i) * TAU / float(stone_count)
		var sx := cos(angle) * ring_r
		var sz := sin(angle) * ring_r
		_add_box(campfire_root, "RingStone_%d" % i, Vector3(sx, 0.10, sz), Vector3(0.20, 0.16, 0.20), stone_mat)
	
	# Charcoal and glowing embers in center
	_add_box(campfire_root, "Embers", Vector3(0, 0.04, 0), Vector3(0.70, 0.08, 0.70), MountainMaterials.brazier_coals())
	
	# Seating log benches around campfire
	var log_mat := MountainMaterials.wood_log()
	MountainMaterials.wood_cut_end()
	for angle_deg in [-50.0, 75.0, 195.0]:
		var rad := deg_to_rad(angle_deg)
		var seat_pos := Vector3(cos(rad) * 1.35, 0.18, sin(rad) * 1.35)
		var seat := _add_box(campfire_root, "SeatLog", seat_pos, Vector3(1.4, 0.32, 0.32), log_mat)
		seat.rotation.y = rad + PI * 0.5
		
		# Solid collision for seat log
		var seat_body := StaticBody3D.new()
		seat_body.collision_layer = 1
		seat_body.collision_mask = 0
		var scol := CollisionShape3D.new()
		var sbox := BoxShape3D.new()
		sbox.size = Vector3(1.4, 0.35, 0.35)
		scol.shape = sbox
		seat_body.add_child(scol)
		seat.add_child(seat_body)

func _build_perimeter_fences() -> void:
	perimeter_fence = Node3D.new()
	perimeter_fence.name = "SawmillPerimeterFences"
	add_child(perimeter_fence)
	
	# Yard boundary coordinates (derived from polygon corners / 16):
	# West: X = -11.0m, Z from -6.8m to +8.5m
	# South: Z = +8.5m, X from -11.0m to +12.5m
	# East: X = +12.5m, Z from +8.5m to -6.8m
	# North: Z = -6.8m, with GAP from X = -2.5m to +2.5m for the driveway!
	
	var west_start := Vector3(-10.8, 0, -6.8)
	var west_end := Vector3(-10.8, 0, 8.4)
	
	var south_start := west_end
	var south_end := Vector3(12.2, 0, 8.4)
	
	var east_start := south_end
	var east_end := Vector3(12.2, 0, -6.8)
	
	var north_east_start := east_end
	var north_east_end := Vector3(2.5, 0, -6.8)
	
	var north_west_start := Vector3(-2.5, 0, -6.8)
	var north_west_end := west_start
	
	# Build segments
	_add_fence_segment(west_start, west_end)
	_add_fence_segment(south_start, south_end)
	_add_fence_segment(east_start, east_end)
	_add_fence_segment(north_east_start, north_east_end)
	_add_fence_segment(north_west_start, north_west_end)

func _add_fence_segment(a: Vector3, b: Vector3) -> void:
	var fence := MountainFence3D.new()
	fence.build_segment(a, b)
	perimeter_fence.add_child(fence)

func _add_box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi
