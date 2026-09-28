extends SceneTree
const Forest := preload("res://gameplay/urban_v1/FreightOutskirts.gd")
class Snapshot extends "res://gameplay/urban_v1/FreightOutskirts.gd":
	var rows: Dictionary
	func _flush():
		rows = _batches.duplicate(true)
		super._flush()
var checks := 0
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run():
	var forest := Snapshot.new()
	root.add_child(forest)
	for i in 3: await physics_frame
	check(not forest.is_processing() and not forest.is_physics_processing(),"Woodland stays entirely static")
	check(forest.tree_positions.size() > 100,"Rural extension retains substantial woodland")
	check(forest._trunks.get_child_count() == forest.tree_positions.size(),"One real trunk collider per tree")
	var wood_count := 0
	var canopy_count := 0
	var tones := {}
	var minimum_height := INF
	var maximum_height := 0.0
	for row in forest.rows.values():
		check(forest._meshes.has(row.kind) and forest._materials.has(row.kind),"CPU batch keeps editor mesh/material contract")
		check(row.transforms.size() == row.colors.size(),"CPU batch colors match transforms")
		if row.kind == "trunk":
			wood_count += row.transforms.size()
			for transform in row.transforms:
				var height: float = transform.basis.y.length()
				minimum_height = minf(minimum_height,height)
				maximum_height = maxf(maximum_height,height)
		if str(row.kind).begins_with("crown_"):
			canopy_count += row.transforms.size()
			tones[forest._materials[row.kind].albedo_color] = true
	check(wood_count == forest.tree_positions.size() and canopy_count == wood_count,"Each tree uses just two batched instances including branches")
	check(tones.size() == 3,"Three explicit foliage material tones survive render/editor paths")
	check(maximum_height-minimum_height > 4.0,"Tree silhouettes vary naturally in height")
	for variant in 3:
		var mesh: ArrayMesh = forest._meshes["crown_%d"%variant]
		var arrays := mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_VERTEX].size()/3 <= 240,"Baked irregular canopy has bounded triangle count")
		check(mesh.get_aabb().size.x > .9 and mesh.get_aabb().size.y > .8,"Five foliage masses form broad tall asymmetric canopy")
	var wood: ArrayMesh = forest._meshes.trunk
	var reversed_faces := 0
	var wood_arrays := wood.surface_get_arrays(0)
	var wood_points: PackedVector3Array = wood_arrays[Mesh.ARRAY_VERTEX]
	var wood_normals: PackedVector3Array = wood_arrays[Mesh.ARRAY_NORMAL]
	for i in range(0,wood_points.size(),3):
		if (wood_points[i+2]-wood_points[i]).cross(wood_points[i+1]-wood_points[i]).dot(wood_normals[i])<-.000001: reversed_faces += 1
	check(reversed_faces==0,"Bark front faces agree with outward normals, without hollow floating trunks")
	check(wood.get_aabb().size.x > .25 and wood.get_aabb().size.z > .25,"Shared wood mesh includes lateral fork branches")
	var bark := {}
	for color in wood.surface_get_arrays(0)[Mesh.ARRAY_COLOR]: bark[color] = true
	check(bark.size() >= 4,"Bark has alternating rough furrow tones")
	var space := forest.get_world_3d().direct_space_state
	for index in forest.tree_positions.size():
		var point: Vector3 = forest.tree_positions[index]
		var body_shape: CollisionShape3D = forest._trunks.get_child(index)
		check(Forest._available(Vector2(point.x,point.z),11.0),"Trunk outside roads, company and village paths")
		check(body_shape.shape.radius >= .24 and body_shape.shape.radius <= .39,"Solid radius retains original physical trunk envelope")
		if index % 25 != 0: continue
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3(-1,.8,0),point+Vector3(1,.8,0),1)
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider == forest._trunks,"Physical trunk blocks horizontal passage")
		if not hit.is_empty(): check(absf(hit.position.x-point.x) <= body_shape.shape.radius+.01,"Collision surface matches authored tree radius")
	forest.free()
	print("FREIGHT_WOODLAND_TREES checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
