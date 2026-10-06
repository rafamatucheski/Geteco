extends SceneTree
## Real CameraRig + authored WorldConnection: covers the final blended transform.
## This collision/environment fixture complements rendered Main.tscn evidence.
const CAMERA := preload("res://scripts/CameraRig.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")

class FixtureWorld extends Node3D:
	var gameplay: Node
	var hud: Control
	var production: Node

class Walker extends CharacterBody3D:
	var visual := Node3D.new()
	func _ready() -> void: add_child(visual)

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var fixture := FixtureWorld.new()
	root.add_child(fixture)
	fixture.add_child(CONNECTION.new())
	var actor := Walker.new()
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fixture.add_child(actor)
	var camera := CAMERA.new()
	fixture.add_child(camera)
	camera.set_process(false)
	camera.target = actor
	var weather := WorldEnvironment.new()
	var source := Environment.new()
	source.background_mode = Environment.BG_COLOR
	source.background_color = Color("829da6")
	source.fog_enabled = false
	source.fog_density = .12
	weather.environment = source
	fixture.add_child(weather)
	var lens := SphereShape3D.new()
	lens.radius = .25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = lens
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var checked := 0
	var active_haze := 0
	for direction in [-1.0, 1.0]:
		var from_x: float = CONNECTION.TUNNEL_START_X-25.0 if direction > 0.0 else CONNECTION.TUNNEL_END_X+25.0
		var to_x: float = CONNECTION.TUNNEL_END_X+25.0 if direction > 0.0 else CONNECTION.TUNNEL_START_X-25.0
		for side_offset in [-6.3, 0.0, 6.3]:
			for facing in [-PI*.5, PI*.5, 0.0, PI]:
				camera.initialized = false
				camera._tunnel_chase_blend = 0.0
				camera.locked = false
				actor.visual.rotation.y = facing
				var steps := ceili(absf(to_x-from_x))
				for step in range(steps+1):
					actor.position = Vector3(lerpf(from_x,to_x,float(step)/steps),.07,CONNECTION.CENTER_Z+side_offset)
					actor.reset_physics_interpolation()
					camera._process(1.0/60.0)
					if camera._tunnel_chase_blend > .001:
						query.transform = camera.global_transform
						var collisions := space.intersect_shape(query,1)
						check(collisions.is_empty(),"blended lens clear x=%.2f side=%.1f facing=%.2f blend=%.3f" % [actor.position.x,side_offset,facing,camera._tunnel_chase_blend])
						if camera._tunnel_chase_blend >= .99:
							check(absf(camera.global_position.z-CONNECTION.CENTER_Z) <= CONNECTION.TUNNEL_CLEAR_HALF_WIDTH-.25-.15+.001,"low lens stays on corridor side of guard rail")
						checked += 1
						if camera.environment != null:
							active_haze += 1
							check(camera.environment != source,"camera never mutates source environment")
					check(not source.fog_enabled and is_equal_approx(source.fog_density,.12),"source fog remains authored")
				for frame in 90: camera._process(1.0/60.0)
				check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"both exits restore street projection")
				check(camera.environment == null,"both exits restore world environment")
	check(checked > 1000,"route covered both portals, sidewalks and four headings")
	check(active_haze > 1000,"mountain low view supplies local distance haze")
	actor.position = Vector3((CONNECTION.TUNNEL_START_X+CONNECTION.TUNNEL_END_X)*.5,.07,CONNECTION.CENTER_Z)
	actor.reset_physics_interpolation()
	camera.initialized = false
	camera._process(1.0/60.0)
	check(camera.environment != null,"inside tunnel activates local view")
	camera.locked = true
	camera._process(1.0/60.0)
	check(camera.environment == null,"locked view immediately restores original environment")
	camera.locked = false
	camera._process(1.0/60.0)
	camera.target = null
	camera._process(1.0/60.0)
	check(camera.environment == null,"missing target releases camera-local weather")
	print("MOUNTAIN_TUNNEL_CAMERA_SAFETY samples=",checked," haze=",active_haze," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
