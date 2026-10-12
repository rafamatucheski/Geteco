extends SceneTree
const COVERAGE := preload("res://runtime/atmosphere/PrecipitationCoverage.gd")
const REGIONAL := preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	root.size = Vector2i(1280,720)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var rain := GPUParticles3D.new()
	rain.emitting = false
	rain.process_material = ParticleProcessMaterial.new()
	root.add_child(rain)
	COVERAGE.configure(rain)
	# Independent expectation: every corner ray at the ground and above the
	# driver must lie within the falling volume, at maximum zoom and every orbit.
	for size in [22.0,39.0,52.0]:
		camera.size = size
		for heading in [0.0,PI/4.0,PI/2.0,PI]:
			var focus := Vector3(77,.1,96)
			camera.position = focus+Vector3(0,23,27.4).rotated(Vector3.UP,heading)
			camera.look_at(focus)
			COVERAGE.follow(rain,camera,focus)
			var extent: Vector3 = rain.process_material.emission_box_extents
			for screen in [Vector2.ZERO,Vector2(1280,0),Vector2(1280,720),Vector2(0,720)]:
				var origin := camera.project_ray_origin(screen)
				var ray := camera.project_ray_normal(screen)
				for height in [focus.y,focus.y+8.0]:
					var point: Vector3 = origin+ray*((height-origin.y)/ray.y)
					var relative := point-rain.global_position
					check(absf(relative.x)<extent.x and absf(relative.z)<extent.z,"Screen corner covered at size %s heading %s"%[size,heading])
			var drop := Vector3(3,-8,2)
			var before := rain.to_global(drop)
			# 300km/h, including a frame hitch: existing rain translates with view.
			var travel := Vector3(83.33*.1,0,0)
			camera.position += travel
			COVERAGE.follow(rain,camera,focus+travel)
			check(rain.local_coords and (rain.to_global(drop)-before).is_equal_approx(travel),"Living rain keeps up at high speed")
			check(rain.visibility_aabb.has_point(drop),"Living drop stays inside culling volume")
	check(REGIONAL.desert_weight(Vector3(345,0,-360))==0,"City end remains wet")
	check(REGIONAL.desert_weight(Vector3(345,0,-415))>.1 and REGIONAL.desert_weight(Vector3(345,0,-415))<.9,"Desert transition blends")
	check(REGIONAL.desert_weight(Vector3(345,0,-742))==1,"Desert interior is dry")
	var surface := preload("res://runtime/atmosphere/WeatherSurfaceEffects.gd").new()
	root.add_child(surface)
	for desert in [0.0, .5, 1.0]:
		for haze in [0.0, .04, .22, 1.0]:
			for covered in [false, true, false]:
				surface.set_conditions(Vector3(345,0,-742),0,haze,Color.WHITE,covered,desert,1)
				surface.follow_focus(Vector3(345,0,-750))
				check(not surface.mist.emitting and not surface.mist.visible,"No ground clouds across regions, haze, shelter and recovery")
				check(not surface.is_processing(),"No idle ground-cloud animation")
	surface.set_conditions(Vector3(718,0,-479),1,.22,Color.WHITE,false)
	check(surface.is_physics_processing() and surface.shards.visible,"Hail impacts remain enabled")
	surface.set_conditions(Vector3(718,0,-479),1,.22,Color.WHITE,true)
	check(not surface.is_physics_processing() and not surface.shards.visible,"Shelter still suspends hail impacts")
	surface.free()
	rain.free()
	camera.free()
	print("WEATHER_FOLLOW ",checks," checks; errors=",failures)
	quit(0 if failures.is_empty() else 1)
