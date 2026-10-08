extends SceneTree
## Cast against the actual triangle meshes, not just their shared height helper.
## A 16m approximation previously rose 0.534m above Harbor's 4m bridge water.
const OCEAN = preload("res://world/regions/HarborOcean.gd")
const DISTANT = preload("res://world/places/coastal_lookout/LookoutDistantSea.gd")
var scene: Node3D

func _initialize() -> void: run.call_deferred()

func add_surface(mesh: MeshInstance3D, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	scene.add_child(body)

func height_at(point: Vector2, layer: int) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,5,point.y),Vector3(point.x,-8,point.y),layer)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var original := OCEAN.new()
	original.configure([],[])
	var near_mesh := original.build_chunk(scene,Rect2(400,-368,160,160))
	var far_mesh := DISTANT.build()
	scene.add_child(far_mesh)
	add_surface(near_mesh,8)
	add_surface(far_mesh,16)
	await physics_frame
	await physics_frame
	var samples := PackedVector2Array([Vector2(424,-248)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 711026
	for i in 256: samples.append(Vector2(rng.randf_range(400.1,559.9),rng.randf_range(-367.9,-208.1)))
	var failures := 0
	var max_error := 0.0
	for point in samples:
		var near_y := height_at(point,8)
		var far_y := height_at(point,16)
		var error := absf((near_y-far_y)-.12)
		if not is_finite(near_y) or not is_finite(far_y) or error>.002:
			failures += 1
			push_error("Sea separation at %s near=%s far=%s"%[point,near_y,far_y])
		max_error = maxf(max_error,error)
	# These positions are beyond the old finite apron, inside optical far views
	# and outside authored land. The actual mesh must continue beneath each ray.
	for point in [Vector2(-3000,-900),Vector2(1600,-1700),Vector2(-2200,1400),Vector2(2000,1400)]:
		if not is_finite(height_at(point,16)):
			failures += 1
			push_error("Missing panorama ocean at "+str(point))
	# Distant water must never cover low terrain or the mine inside the desert.
	for point in [Vector2(-900,-1320),Vector2(-200,-900),Vector2(100,-1500)]:
		if is_finite(height_at(point,16)):
			failures += 1
			push_error("Panorama ocean covers authored desert at "+str(point))
	print("COASTAL_SEA_MESH checks=",samples.size()," failures=",failures," max_error_m=",max_error)
	quit(0 if failures==0 else 1)
