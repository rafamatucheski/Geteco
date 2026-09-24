extends Node3D
class_name MountainFence3D

## Modular rustic split-rail wooden fence with timber posts, horizontal split rails,
## and snowy top caps. Generates native StaticBody3D collision (layer 1, mask 0).

@export var post_height: float = 1.15
@export var post_thickness: float = 0.14
@export var rail_count: int = 2

func _ready() -> void:
	pass

## Constructs a fence segment connecting two 3D points.
func build_segment(start_pt: Vector3, end_pt: Vector3) -> void:
	var delta := end_pt - start_pt
	var length := delta.length()
	if length < 0.2:
		return
	
	var pole_mat := MountainMaterials.wood_pole()
	var snow_mat := MountainMaterials.snow_fresh()
	
	var center := (start_pt + end_pt) * 0.5
	var angle_y := atan2(delta.x, delta.z)
	
	# Solid StaticBody3D for physical barrier
	var body := StaticBody3D.new()
	body.name = "FenceCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(post_thickness * 1.5, post_height, length)
	col.shape = box_shape
	col.position = Vector3(0, post_height * 0.5, 0)
	body.add_child(col)
	
	var seg_root := Node3D.new()
	seg_root.name = "Segment"
	seg_root.position = center
	seg_root.rotation.y = angle_y
	seg_root.add_child(body)
	add_child(seg_root)
	
	# Start post
	_add_post(seg_root, Vector3(0, post_height * 0.5, -length * 0.5), pole_mat, snow_mat)
	# End post
	_add_post(seg_root, Vector3(0, post_height * 0.5, length * 0.5), pole_mat, snow_mat)
	
	# If segment is long (> 3.5m), place an intermediate post
	if length > 3.5:
		_add_post(seg_root, Vector3(0, post_height * 0.5, 0), pole_mat, snow_mat)
	
	# Horizontal split rails
	var rail_spacing := (post_height * 0.65) / float(maxi(1, rail_count))
	for r in rail_count:
		var ry := 0.35 + float(r) * rail_spacing
		var rail := _add_box(seg_root, "Rail_%d" % r, Vector3(0, ry, 0), Vector3(0.08, 0.09, length), pole_mat)
		# Snow strip along upper rail
		if r == rail_count - 1:
			_add_box(seg_root, "RailSnow", Vector3(0, ry + 0.055, 0), Vector3(0.09, 0.025, length * 0.98), snow_mat)

func _add_post(parent: Node3D, pos: Vector3, wood_mat: Material, snow_mat: Material) -> void:
	_add_box(parent, "FencePost", pos, Vector3(post_thickness, post_height, post_thickness), wood_mat)
	# Snow cap on post
	_add_box(parent, "PostSnowCap", pos + Vector3(0, post_height * 0.5 + 0.02, 0), Vector3(post_thickness + 0.03, 0.04, post_thickness + 0.03), snow_mat)

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

## Static helper to build a connected fence line from an array of Vector3 points with optional gaps.
static func create_fence_line(points: PackedVector3Array) -> MountainFence3D:
	var fence := MountainFence3D.new()
	fence.name = "FenceLine"
	for i in range(points.size() - 1):
		fence.build_segment(points[i], points[i + 1])
	return fence
