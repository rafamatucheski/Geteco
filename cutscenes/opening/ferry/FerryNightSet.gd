extends Node3D
## Offline set extension and practical lighting, never instantiated by gameplay.
const OCEAN := preload("res://world/regions/HarborOcean.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var ferry: Node3D
var rain: GPUParticles3D
var background_models: Array = []
var frozen_bodies: Array = []
var activity := preload("res://cutscenes/opening/ferry/FerryHarborActivity.gd").new()

func configure(world, boat: Node3D) -> void:
	ferry = boat
	# Suspend both bodies and their route/spawn managers for this offline set.
	# Pausing only the bodies leaves transit managers driving detached physics RIDs.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	# Explicit ALWAYS/PAUSABLE modes override a disabled ancestor. Freeze those
	# owners too, or the session keeps changing shifts and freeing our cast.
	var director := get_parent()
	for node in world.find_children("*", "Node", true, false):
		if node == director or director.is_ancestor_of(node): continue
		node.process_mode = Node.PROCESS_MODE_DISABLED
	# The take supplies its own ferry passengers. Gameplay disembarkers would
	# otherwise remain suspended over the water when this ferry leaves its berth.
	for actor in world.session.urban_operations.passenger_terminal.passengers:
		if is_instance_valid(actor): actor.hide()
	activity.configure(world)
	# Only undirected extras hold a mark. Dock workers and machinery have an
	# authored work cycle, without waking the gameplay spawn/traffic managers.
	for body in world.find_children("*","CharacterBody3D",true,false):
		if body == world.player or body.is_queued_for_deletion(): continue
		if activity.owns(body): continue
		frozen_bodies.append({"node":body,"position":body.global_position})
		for model in body.find_children("*","Node3D",true,false):
			if model is CIVILIAN:
				model.activity = "idle"
				background_models.append(model)
	world.production.region.set_process(false)
	world.production.region.set_physics_process(false)
	var weather = world.session.weather
	weather.time_of_day = .94
	weather.weather_state = 1
	weather.rain_intensity = .25
	weather.atmosphere_step = 30.0
	weather._update()
	# Resolve the existing quay fixtures once at the authored night hour, before
	# holding their assignments for the take (no camera-dependent light popping).
	for lighting in world.find_children("CityLocalLighting", "Node3D", true, false):
		lighting.refresh()
	weather.set_process(false)
	weather.precipitation.emitting = false
	weather.precipitation.hide()
	var env: Environment = world.production.environment.environment
	env.background_mode = Environment.BG_COLOR
	# Fundo e névoa na mesma cor: de cima, o fim do mundo carregado não deixa borda.
	env.background_color = Color("17263a")
	env.ambient_light_color = Color("95afc9")
	env.ambient_light_energy = .43
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("17263a")
	env.fog_light_energy = 1.0
	env.fog_density = .02
	env.fog_depth_begin = 28
	env.fog_depth_end = 175
	env.fog_sky_affect = 1.0
	world.production.sun.light_energy = .3
	world.production.sun.light_color = Color("97b5d3")
	world.production.sun.rotation_degrees = Vector3(-48,-30,0)
	world.production.sun.directional_shadow_max_distance = 150.0
	_extend_ocean(world)
	_hide_stray_skirts(world)
	_wet_deck()
	_practicals()
	_rain()

func _extend_ocean(world) -> void:
	var source = world.production.region.harbor_ocean
	assert(source != null)
	for mesh in world.production.region.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override == source.material: mesh.hide()
	var material := source.material.duplicate() as ShaderMaterial
	material.set_shader_parameter("sky_color",Color("253d57"))
	material.set_shader_parameter("shallow_color",Color("064052"))
	material.set_shader_parameter("deep_color",Color("081d32"))
	# Continuous 1024 m ocean, independent of the gameplay streaming radius.
	# Tile UVs retain the production shader's periodic, low-coordinate precision.
	for tz in range(-2,2):
		for tx in range(-1,3):
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var uvs := PackedVector2Array()
			var indices := PackedInt32Array()
			for z in 17:
				for x in 17:
					var point := Vector2(tx*256+x*16,tz*256+z*16)
					# 12 cm acima da água de jogo: as bordas das placas submersas do canal
					# ficavam na superfície e, vistas do alto, riscavam o mar em linhas retas.
					vertices.append(Vector3(point.x,OCEAN.WATER_Y+.12,point.y))
					normals.append(Vector3.UP)
					colors.append(Color(source.shore_distance(point)/24.0,0,0,1))
					uvs.append(Vector2(x*16,z*16))
			for z in 16:
				for x in 16:
					var a := z*17+x
					indices.append_array([a,a+1,a+17,a+1,a+18,a+17])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			var surface := ArrayMesh.new()
			surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var water := MeshInstance3D.new()
			water.name = "ContinuousOcean_%d_%d"%[tx,tz]
			water.mesh = surface
			water.material_override = material
			water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(water)

func _hide_stray_skirts(world) -> void:
	# Três saias de placa (-0,3..0 m) dos lotes fundidos caem fora do próprio chunk de
	# 64 m, em água aberta (ex.: Chunk_2_1 desenhando em x=248..312 no canal). Vistas do
	# alto, riscavam o mar em linhas retas. Só na filmagem; as saias do cais ficam.
	for chunk in world.production.region.find_children("Chunk_*","Node3D",false,false):
		var parts := String(chunk.name).split("_")
		if parts.size() != 3: continue
		var origin := Vector2(int(parts[1])*64.0,int(parts[2])*64.0)
		for mesh in chunk.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if absf(box.position.y+.3) > .01 or absf(box.end.y) > .01: continue
			if box.position.x < origin.x-1 or box.position.z < origin.y-1 or box.end.x > origin.x+65 or box.end.z > origin.y+65:
				mesh.hide()

func _wet_deck() -> void:
	# Only this authoring instance: preserve the gameplay boat's shared materials.
	for mesh in ferry.find_children("*","MeshInstance3D",true,false):
		var original := mesh.material_override as StandardMaterial3D
		if original == null or original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
		var wet := original.duplicate() as StandardMaterial3D
		wet.roughness = .38
		wet.metallic_specular = .35
		mesh.material_override = wet

func _practicals() -> void:
	var fixture := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.6,.055,.085)
	fixture.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e1b878")
	material.emission_enabled = true
	material.emission = Color("ffcd86")
	material.emission_energy_multiplier = 2.0
	fixture.material_override = material
	fixture.position = Vector3(0,2.55,1.15)
	ferry.add_child(fixture)
	var light := SpotLight3D.new()
	light.position = fixture.position+Vector3(0,-.06,.06)
	light.light_color = Color("ffd5a2")
	light.light_energy = 4.5
	light.light_specular = .3
	light.spot_range = 9
	light.spot_angle = 65
	light.spot_attenuation = .8
	light.shadow_enabled = true
	ferry.add_child(light)
	light.look_at(ferry.to_global(Vector3(0,1.1,4.3)),Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.8,1.4,4.2)
	fill.light_color = Color("8caed0")
	fill.light_energy = .85
	fill.omni_range = 6.0
	fill.light_specular = .15
	ferry.add_child(fill)

func _rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "FerryRain"
	rain.amount = 1900
	rain.lifetime = 1.6
	rain.preprocess = 1.6
	rain.fixed_fps = 30
	rain.visibility_aabb = AABB(Vector3(-22,-20,-22),Vector3(44,40,44))
	var quad := QuadMesh.new()
	quad.size = Vector2(.022,.28)
	var material := ShaderMaterial.new()
	material.shader = preload("res://cutscenes/opening/ferry/ferry_rain.gdshader")
	material.set_shader_parameter("rain_texture",preload("res://runtime/atmosphere/WeatherParticleTextures.gd").texture("rain"))
	quad.material = material
	rain.draw_pass_1 = quad
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(18,1,18)
	motion.direction = Vector3(.12,-1,.04)
	motion.spread = 1
	motion.initial_velocity_min = 12
	motion.initial_velocity_max = 15
	motion.gravity = Vector3(0,-3,0)
	rain.process_material = motion
	add_child(rain)

func sample(t: float, delta: float) -> void:
	rain.global_position = ferry.global_position+Vector3.UP*10
	activity.sample(t,delta)
	for i in background_models.size():
		var model = background_models[i]
		if not is_instance_valid(model): continue
		model.clock = t+i*.7
		model._speed = 0.0
		model._travel = 0.0
		model._pose(delta)
