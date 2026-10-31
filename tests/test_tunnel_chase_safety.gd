extends SceneTree
## Contratos focados de colisão da lente e névoa local à câmera; a aprovação visual é à parte.
const SAFETY := preload("res://scripts/camera/TunnelChaseSafety.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body

func run() -> void:
	var safety := SAFETY.new()
	var wall := box(Vector3(0,1.5,3),Vector3(12,3,.2))
	box(Vector3(0,3,0),Vector3(12,.2,12))
	var camera := Camera3D.new()
	root.add_child(camera)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("829da6")
	environment.fog_enabled = false
	environment.fog_density = .12
	world_environment.environment = environment
	root.add_child(world_environment)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var eye := Vector3(0,1.3,0)
	var wall_pose := safety.resolve_position(space,eye,Vector3(0,2.4,6))
	check(wall_pose.z < 2.65,"lens sphere remains inside side wall")
	var roof_pose := safety.resolve_position(space,eye,Vector3(0,8,-4))
	check(roof_pose.y < 2.65,"blended street pose cannot cross solid roof")
	var free_pose := Vector3(0,2.2,-4)
	check(safety.resolve_position(space,eye,free_pose).is_equal_approx(free_pose),"unobstructed chase distance stays intact")
	var excluded: Array[RID] = [wall.get_rid()]
	check(safety.resolve_position(space,eye,Vector3(0,2.2,6),excluded).z > 5.9,"target collision RID is excluded")
	var overlap_pose := safety.resolve_position(space,Vector3(0,1.3,2.85),Vector3(0,2.2,6))
	check(safety.clear_origin_found and overlap_pose.z < 2.65,"overlap at origin retreats before sweep instead of ignoring wall")
	var near_roof_pose := safety.resolve_position(space,Vector3(0,2.75,0),Vector3(0,8,-4))
	check(safety.clear_origin_found and near_roof_pose.y < 2.65,"initial roof overlap resolves on accessible side")
	# O limite lateral da montanha deixava a lente exatamente tangente a
	# um apoio de nervura de .20m: cast_motion aceitava, enquanto as consultas de sobreposição não.
	var support := box(Vector3(20,2.42,7.15),Vector3(.20,3.96,.30))
	await physics_frame
	await physics_frame
	var lens := SphereShape3D.new()
	lens.radius = .25
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = lens
	overlap.collision_mask = 1
	for x_offset in [-.15,-.10,-.075,0.0,.075,.10,.15]:
		var at := Vector3(20.0+x_offset,1.37,6.3)
		var endpoint := safety.resolve_position(space,at,Vector3(at.x,2.27,6.75))
		overlap.transform = Transform3D(Basis.IDENTITY,endpoint)
		check(space.intersect_shape(overlap,1).is_empty(),"grazing support keeps full lens clear offset %.3f" % x_offset)
	support.queue_free()
	camera.position = Vector3(0,2.4,-6)
	safety.update_environment(camera,1.0,.1,Vector3.ZERO)
	check(camera.environment != null and camera.environment != environment,"haze uses camera-local environment")
	check(not environment.fog_enabled and is_equal_approx(environment.fog_density,.12),"world weather is untouched")
	check(camera.environment.fog_enabled and is_equal_approx(camera.environment.fog_density,1.0),"streaming boundary is fully covered")
	check(camera.environment.fog_depth_end <= 54.0,"depth closes before nearest unloaded cell")
	check(camera.environment.fog_light_color.is_equal_approx(environment.background_color),"distance haze matches plain sky color")
	environment.background_color = Color("111d30")
	environment.ambient_light_energy = .43
	safety.update_environment(camera,1.0,.1,Vector3.ZERO)
	check(camera.environment.background_color.is_equal_approx(environment.background_color),"day-night color changes propagate")
	environment.ambient_light_energy = .52
	safety.update_environment(camera,1.0,.001,Vector3.ZERO)
	check(is_equal_approx(camera.environment.ambient_light_energy,.52),"lightning ambient envelope propagates every frame")
	safety.update_environment(camera,0.0,.1,Vector3.ZERO)
	check(camera.environment == null,"exit restores implicit world environment")
	var original := environment.duplicate() as Environment
	camera.environment = original
	safety.update_environment(camera,1.0,.1,Vector3.ZERO)
	safety.restore_environment()
	check(camera.environment == original,"existing authored camera override is restored")
	print("TUNNEL_CHASE_SAFETY failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
