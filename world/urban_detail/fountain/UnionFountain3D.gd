extends Node3D
## Chafariz da Union Plaza, em frente ao Bay Medical, com água de verdade: espelho
## d'água animado na bacia, taça superior que transborda em cortina, jato central
## em partículas, respingo onde a cortina bate e som contínuo de água.
##
## A bacia (raio 3,75 m, topo 0,60) e o pedestal (raio 0,81, topo 1,24) continuam
## em HarborPublicRealm3D, com a colisão; aqui fica só o que é água e a taça.
## Coordenadas locais ao centro do chafariz.

const WATER_SHADER := preload("res://world/urban_detail/fountain/FountainWater.gdshader")
const CURTAIN_SHADER := preload("res://world/urban_detail/fountain/FountainCurtain.gdshader")
const STONE := Color("c4c4ad")
const BASIN_WATER_Y := 0.70
const BOWL_TOP_Y := 2.0
const BOWL_RADIUS := 1.25
const CURTAIN_RADIUS := 1.3

func _ready() -> void:
	name = "UnionFountain"
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.8
	# Borda da bacia: a água fica abaixo dela, não pintada no topo como na V1 2D.
	var rim := MeshInstance3D.new()
	rim.name = "FountainRim"
	var torus := TorusMesh.new()
	torus.inner_radius = 3.3
	torus.outer_radius = 3.78
	torus.rings = 48
	torus.ring_segments = 10
	rim.mesh = torus
	rim.scale = Vector3(1, 0.5, 1)
	rim.position.y = 0.64
	rim.material_override = stone
	add_child(rim)
	_cylinder("FountainStem", Vector3(0, 1.5, 0), 0.22, 0.26, 0.52, stone)
	_cylinder("FountainBowl", Vector3(0, BOWL_TOP_Y - 0.16, 0), BOWL_RADIUS, 0.5, 0.32, stone)
	_cylinder("FountainNozzle", Vector3(0, BOWL_TOP_Y + 0.05, 0), 0.07, 0.1, 0.16, stone)
	_water("FountainBasinWater", BASIN_WATER_Y, 3.34, CURTAIN_RADIUS + 0.05, 0.018)
	_water("FountainBowlWater", BOWL_TOP_Y + 0.012, BOWL_RADIUS - 0.08, 0.0, 0.01)
	_curtain()
	_jet()
	_landing_splash()
	var audio := AudioStreamPlayer3D.new()
	audio.name = "FountainSound"
	var stream := (load("res://audio/living_city/water_0.ogg") as AudioStream).duplicate()
	if stream is AudioStreamOggVorbis: stream.loop = true
	audio.stream = stream
	audio.position.y = 1.0
	audio.unit_size = 5.0
	audio.max_distance = 38.0
	audio.volume_db = -8.0
	audio.autoplay = true
	if AudioServer.get_bus_index("SFX") >= 0: audio.bus = &"SFX"
	add_child(audio)

func _cylinder(label: String, center: Vector3, top: float, bottom: float, height: float, material: Material) -> void:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 32
	item.mesh = mesh
	item.position = center
	item.material_override = material
	add_child(item)

func _water(label: String, y: float, radius: float, impact: float, strength: float) -> void:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * radius * 2.0
	# Subdividido para as ondas do vertex shader aparecerem no contorno do reflexo.
	mesh.subdivide_width = 40
	mesh.subdivide_depth = 40
	item.mesh = mesh
	item.position.y = y
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("impact_radius", impact)
	material.set_shader_parameter("wave_strength", strength)
	item.material_override = material
	add_child(item)

func _curtain() -> void:
	var item := MeshInstance3D.new()
	item.name = "FountainCurtain"
	var mesh := CylinderMesh.new()
	mesh.top_radius = BOWL_RADIUS + 0.02
	mesh.bottom_radius = CURTAIN_RADIUS + 0.08
	var height := BOWL_TOP_Y - BASIN_WATER_Y
	mesh.height = height
	mesh.radial_segments = 48
	mesh.cap_top = false
	mesh.cap_bottom = false
	item.mesh = mesh
	item.position.y = BASIN_WATER_Y + height * 0.5
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = CURTAIN_SHADER
	item.material_override = material
	add_child(item)

func _drop_material(color: Color) -> StandardMaterial3D:
	var drop := StandardMaterial3D.new()
	drop.albedo_color = color
	drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	drop.vertex_color_use_as_albedo = true
	return drop

func _jet() -> void:
	# ~1,5 m de altura: v²/2g com v ≈ 5,4 m/s. A água sobe e cai de volta na taça.
	var jet := GPUParticles3D.new()
	jet.name = "FountainJet"
	jet.amount = 220
	jet.lifetime = 1.15
	jet.position.y = BOWL_TOP_Y + 0.12
	jet.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 2.5, 3))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 4.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 5.6
	process.gravity = Vector3(0, -9.8, 0)
	process.scale_min = 0.7
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(0.9, 0.97, 1.0, 0.85))
	fade.set_color(1, Color(0.8, 0.92, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	jet.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.22)
	quad.material = _drop_material(Color.WHITE)
	jet.draw_pass_1 = quad
	add_child(jet)

func _landing_splash() -> void:
	# Respingo contínuo no anel onde a cortina encontra a bacia.
	var splash := GPUParticles3D.new()
	splash.name = "FountainLandingSplash"
	splash.amount = 90
	splash.lifetime = 0.45
	splash.position.y = BASIN_WATER_Y + 0.02
	splash.visibility_aabb = AABB(Vector3(-2.5, -0.2, -2.5), Vector3(5, 1.2, 5))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = CURTAIN_RADIUS + 0.08
	process.emission_ring_inner_radius = CURTAIN_RADIUS - 0.05
	process.emission_ring_height = 0.0
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, -9.8, 0)
	splash.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = _drop_material(Color(0.92, 0.97, 1.0, 0.7))
	splash.draw_pass_1 = quad
	add_child(splash)
