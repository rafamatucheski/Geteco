extends Node3D
## Efeitos visuais 3D de combate, com orçamento fixo. Filho de `Gameplay`.
##
## Fonte V1: `guns/combat/WeaponEffects.gd` (efeitos 2D desenhados com `_draw`). As cores, os tempos, as
## contagens e a física (ejeção de cápsula, gota de sangue, faísca por material) foram tiradas de lá,
## divididas por 16 (px → m); o desenho é 3D novo, porque `Node2D`/`_draw` não se reaproveita.
##
## Limites (nada é criado durante o jogo):
##   - impactos e sangue: UM emissor `CPUParticles3D` de disparo único por material, criado uma vez.
##     Um impacto novo do mesmo material reinicia o emissor (o anterior, se ainda vivo, é cortado).
##   - cápsulas: MAX_SHELLS nós reaproveitados em anel; simulação própria só enquanto há cápsula ativa.
##   - manchas no chão: MAX_STAINS quadros reaproveitados em anel, somem sozinhos.
##   - explosão: um emissor de fagulhas, um de fumaça e uma luz, reaproveitados.
##   - rastro de foguete: um emissor contínuo por projétil, liberado com ele.
## Custo em quadro não medido.
const MAX_SHELLS := 16
const MAX_STAINS := 12
const MAX_TRACERS := 32
const MAX_FLAME_PACKETS := 8
## Emissores por efeito disparados em rodízio. Com um emissor só, cada chumbo da
## escopeta reiniciava o anterior e só o último respingo/faísca aparecia.
const BURST_POOL := 4
const MAX_SCORCHES := 6
const SCORCH_LIFETIME := 30.0
const SHELL_LIFETIME := 1.6
const STAIN_LIFETIME := 20.0
## V1 ejeção: lateral 58–83 px/s, subida 72 px/s, gravidade 360 px/s², altura inicial 7 px (tudo ÷ 16).
const SHELL_SIDE_SPEED := 3.6
const SHELL_SIDE_SPREAD := 1.6
const SHELL_LIFT := 4.5
const SHELL_GRAVITY := 22.5
const SHELL_START_HEIGHT := 0.44
## V1 `_ImpactBurst`: cor por superfície.
const IMPACT_COLORS := {
	"world": Color(1.0, 0.74, 0.2), "flesh": Color(0.72, 0.04, 0.03), "concrete": Color(0.76, 0.74, 0.65),
	"metal": Color(1.0, 0.95, 0.55), "wood": Color(0.64, 0.39, 0.18), "glass": Color(0.65, 0.9, 1.0)}
const BLOOD_COLOR := Color(0.55, 0.02, 0.015)

var _impact: Dictionary = {}
var _impact_dust: Array[CPUParticles3D] = []
var _blood: Array[CPUParticles3D] = []
var _blood_mist: Array[CPUParticles3D] = []
var _next_burst: Dictionary = {}
var _blast_fire: CPUParticles3D
var _blast_debris: CPUParticles3D
var _scorches: Array[MeshInstance3D] = []
var _scorch_age: Array[float] = []
var _next_scorch := 0
var _flame_light: OmniLight3D
var _flame_light_time := 0.0
var _muzzle_smoke: CPUParticles3D
var _blast_sparks: CPUParticles3D
var _blast_smoke: CPUParticles3D
var _backblast: CPUParticles3D
var _blast_light: OmniLight3D
var _blast_light_time := 0.0
var _shells: Array[MeshInstance3D] = []
var _shell_state: Array[Dictionary] = []
var _next_shell := 0
var _stains: Array[MeshInstance3D] = []
var _stain_materials: Array[StandardMaterial3D] = []
var _stain_age: Array[float] = []
var _stain_target_radius: Array[float] = []
var _next_stain := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_state: Array[Dictionary] = []
var _next_tracer := 0
var _flame_packets: Array[CPUParticles3D] = []
var _next_flame := 0
var _flame_tongues: Array[MeshInstance3D] = []
var _flame_tongue_state: Array[Dictionary] = []
var _spark_mesh: BoxMesh
var _smoke_mesh: QuadMesh
var _flat_material: StandardMaterial3D

func _ready() -> void:
	var streak := StandardMaterial3D.new()
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.vertex_color_use_as_albedo = true
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Faísca alongada no eixo Y e alinhada à velocidade (`particle_flag_align_y`):
	# a caixa de 5 cm girando solta parecia confete, não risco de faísca.
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.012, 0.075, 0.012)
	_spark_mesh.material = streak
	# Fumaça em quadro de borda macia voltado à câmera. As esferas de 6 lados
	# anteriores apareciam como bolas facetadas, principalmente no sangue.
	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var soft_texture := GradientTexture2D.new()
	soft_texture.gradient = soft
	soft_texture.fill = GradientTexture2D.FILL_RADIAL
	soft_texture.fill_from = Vector2(0.5, 0.5)
	soft_texture.fill_to = Vector2(0.5, 0.0)
	soft_texture.width = 64
	soft_texture.height = 64
	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.vertex_color_use_as_albedo = true
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.albedo_texture = soft_texture
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(0.34, 0.34)
	_smoke_mesh.material = smoke_material
	# Gota: cápsula curta alinhada à velocidade, sombreada e lisa (líquido),
	# não um palito vermelho sem luz que brilhava igual à noite.
	var drop_material := StandardMaterial3D.new()
	drop_material.vertex_color_use_as_albedo = true
	drop_material.roughness = 0.18
	drop_material.metallic_specular = 0.7
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.011
	drop_mesh.height = 0.045
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	drop_mesh.material = drop_material
	var flame_gradient := Gradient.new()
	flame_gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.72, 1.0])
	# Núcleo preenchido; centro transparente produzia anéis/"bolhas" separados.
	flame_gradient.colors = PackedColorArray([Color(1,1,0.86,1), Color(1,0.94,0.55,1), Color(1,0.32,0.025,0.78), Color(0.2,0.16,0.13,0)])
	var flame_texture := GradientTexture2D.new()
	flame_texture.gradient = flame_gradient
	flame_texture.fill = GradientTexture2D.FILL_RADIAL
	flame_texture.fill_from = Vector2(0.5, 0.5)
	flame_texture.fill_to = Vector2(0.5, 0.0)
	flame_texture.width = 64
	flame_texture.height = 64
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.albedo_texture = flame_texture
	# BILLBOARD_ENABLED descartava a escala por partícula: todo pacote de chama
	# tinha 14 cm fixos. BILLBOARD_PARTICLES respeita a curva de crescimento.
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flame_material.vertex_color_use_as_albedo = true
	var flame_quad := QuadMesh.new()
	flame_quad.size = Vector2(0.22, 0.22)
	flame_quad.material = flame_material
	var fireball_quad := QuadMesh.new()
	fireball_quad.size = Vector2(0.9, 0.9)
	fireball_quad.material = flame_material
	for material_name in IMPACT_COLORS:
		var sparks: Array[CPUParticles3D] = []
		for slot in BURST_POOL:
			var spark := _emitter(7, 0.2, _spark_mesh, IMPACT_COLORS[material_name], 1.5, 3.4, 50.0, -6.0, 0.7, 1.3)
			spark.particle_flag_align_y = true
			sparks.append(spark)
		_impact[material_name] = sparks
	for slot in BURST_POOL:
		_impact_dust.append(_emitter(5, 0.5, _smoke_mesh, Color(0.72, 0.70, 0.64, 0.35), 0.5, 1.6, 45.0, 0.3, 0.5, 1.2, 1.9))
		var drops := _emitter(14, 0.55, drop_mesh, BLOOD_COLOR, 2.2, 5.5, 26.0, -9.8, 0.7, 1.5)
		drops.particle_flag_align_y = true
		_blood.append(drops)
		_blood_mist.append(_emitter(5, 0.32, _smoke_mesh, Color(0.42, 0.02, 0.015, 0.55), 0.3, 1.1, 40.0, -0.6, 0.35, 0.8, 2.2))
	_muzzle_smoke = _emitter(4, 0.6, _smoke_mesh, Color(0.65, 0.63, 0.60, 0.28), 0.6, 1.6, 24.0, 0.6, 0.4, 0.9, 2.4)
	_blast_sparks = _emitter(28, 0.6, _spark_mesh, Color(1.0, 0.62, 0.15), 5.0, 11.0, 180.0, -8.0, 1.0, 2.2)
	_blast_sparks.particle_flag_align_y = true
	_blast_fire = _emitter(16, 0.55, fireball_quad, Color(1.0, 0.85, 0.6), 1.2, 4.0, 180.0, 1.5, 0.8, 1.6, 2.6)
	_blast_fire.color_ramp = _fire_ramp()
	_blast_debris = _emitter(12, 1.1, _spark_mesh, Color(0.16, 0.14, 0.12), 4.0, 8.5, 70.0, -14.0, 1.4, 2.4)
	_blast_debris.particle_flag_align_y = true
	_blast_smoke = _emitter(14, 2.4, _smoke_mesh, Color(0.2, 0.19, 0.18, 0.6), 0.8, 2.6, 70.0, 0.9, 2.5, 4.5, 2.2)
	_backblast = _emitter(6, 0.6, _smoke_mesh, Color(0.52, 0.48, 0.40, 0.3), 1.0, 2.6, 25.0, 0.0, 0.8, 1.6, 2.0)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.55, 0.18)
	_flame_light.omni_range = 5.0
	_flame_light.shadow_enabled = false
	_flame_light.visible = false
	add_child(_flame_light)
	var scorch_texture := _make_scorch_texture()
	var scorch_quad := QuadMesh.new()
	scorch_quad.size = Vector2.ONE
	scorch_quad.orientation = PlaneMesh.FACE_Y
	for index in MAX_SCORCHES:
		var scorch_material := StandardMaterial3D.new()
		scorch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		scorch_material.albedo_texture = scorch_texture
		scorch_material.albedo_color = Color(0.05, 0.045, 0.04, 0.85)
		scorch_material.roughness = 1.0
		var scorch := MeshInstance3D.new()
		scorch.mesh = scorch_quad
		scorch.material_override = scorch_material
		scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scorch.top_level = true
		scorch.visible = false
		add_child(scorch)
		_scorches.append(scorch)
		_scorch_age.append(-1.0)
	_blast_light = OmniLight3D.new()
	_blast_light.light_color = Color(1.0, 0.62, 0.22)
	_blast_light.shadow_enabled = false
	_blast_light.visible = false
	add_child(_blast_light)
	var shell_mesh := BoxMesh.new()
	shell_mesh.size = Vector3(0.012, 0.012, 0.04)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.73, 0.44, 0.10)
	brass.metallic = 0.8
	brass.roughness = 0.4
	shell_mesh.material = brass
	for index in MAX_SHELLS:
		var casing := MeshInstance3D.new()
		casing.mesh = shell_mesh
		casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		casing.top_level = true
		casing.visible = false
		add_child(casing)
		_shells.append(casing)
		_shell_state.append({"life": 0.0})
	var blood_texture := _make_blood_texture()
	var flat := QuadMesh.new()
	flat.size = Vector2.ONE
	flat.orientation = PlaneMesh.FACE_Y
	for index in MAX_STAINS:
		# Poça sombreada e lisa: responde à luz como líquido. Sem sombreamento
		# ela ficava vermelho-vivo chapado, mais clara que a rua à noite.
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = blood_texture
		mat.albedo_color = Color(0.36, 0.015, 0.012, 0.92)
		mat.roughness = 0.12
		mat.metallic_specular = 0.8
		var patch := MeshInstance3D.new()
		patch.mesh = flat
		patch.material_override = mat
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.top_level = true
		patch.visible = false
		add_child(patch)
		_stains.append(patch)
		_stain_materials.append(mat)
		_stain_age.append(-1.0)
		_stain_target_radius.append(0.6)
	# V1: o projétil tinha núcleo e cauda curta em movimento. O V2 mantém o
	# acerto hitscan, mas a apresentação percorre a trajetória; não desenha uma
	# barra instantânea do jogador ao alvo.
	for index in MAX_TRACERS:
		var tracer := MeshInstance3D.new()
		var tracer_mesh := BoxMesh.new()
		tracer_mesh.size = Vector3(0.018, 0.018, 0.42)
		var tracer_material := StandardMaterial3D.new()
		tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer_material.emission_enabled = true
		tracer_mesh.material = tracer_material
		tracer.mesh = tracer_mesh
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.top_level = true
		tracer.visible = false
		add_child(tracer)
		_tracers.append(tracer)
		_tracer_state.append({"life": 0.0})
	for index in MAX_FLAME_PACKETS:
		var packet := _emitter(10, 0.34, flame_quad, Color.WHITE, 8.0, 12.0, 9.0, 1.6, 0.5, 1.1, 3.2)
		packet.color_ramp = _fire_ramp()
		_flame_packets.append(packet)
	var tongue_mesh := _build_flame_tongue_mesh()
	for index in MAX_FLAME_PACKETS:
		var tongue := MeshInstance3D.new()
		tongue.mesh = tongue_mesh
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tongue.top_level = true
		tongue.visible = false
		add_child(tongue)
		_flame_tongues.append(tongue)
		_flame_tongue_state.append({"life": 0.0})
	set_physics_process(false)

## Três aletas irregulares formam um jato volumétrico contínuo. Cores por
## vértice reproduzem o núcleo branco, corpo amarelo/laranja e ponta apagando.
func _build_flame_tongue_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var positions := PackedFloat32Array([0.0, 0.16, 0.40, 0.68, 0.88, 1.0])
	var widths := PackedFloat32Array([0.035, 0.085, 0.15, 0.22, 0.14, 0.012])
	var colors := PackedColorArray([
		Color(1, 1, 0.86, 0.96), Color(1, 0.92, 0.28, 0.94),
		Color(1, 0.55, 0.045, 0.86), Color(1, 0.25, 0.015, 0.70),
		Color(0.72, 0.12, 0.01, 0.38), Color(0.25, 0.08, 0.02, 0.0),
	])
	for fin in 3:
		var side := Vector3(cos(float(fin) * PI / 3.0), sin(float(fin) * PI / 3.0), 0.0)
		var flutter_axis := Vector3(-side.y, side.x, 0.0)
		for segment in positions.size() - 1:
			var flutter_a := sin(float(segment * 5 + fin * 3)) * widths[segment] * 0.18
			var flutter_b := sin(float((segment + 1) * 5 + fin * 3)) * widths[segment + 1] * 0.18
			var center_a := flutter_axis * flutter_a + Vector3(0, 0, -positions[segment])
			var center_b := flutter_axis * flutter_b + Vector3(0, 0, -positions[segment + 1])
			var left_a := center_a - side * widths[segment]
			var right_a := center_a + side * widths[segment]
			var left_b := center_b - side * widths[segment + 1]
			var right_b := center_b + side * widths[segment + 1]
			for pair in [[left_a, colors[segment]], [left_b, colors[segment + 1]], [right_b, colors[segment + 1]], [left_a, colors[segment]], [right_b, colors[segment + 1]], [right_a, colors[segment]]]:
				surface.set_color(pair[1])
				surface.add_vertex(pair[0])
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)
	return surface.commit()

## Emissor de disparo único, criado uma vez. A direção de emissão é o eixo local +Y (ver `_aim`).
## `growth` > 1 faz a partícula crescer ao longo da vida (fumaça que se abre, chama que se expande).
func _emitter(amount: int, life: float, mesh: Mesh, color: Color, speed_min: float, speed_max: float, spread: float, gravity_y: float, scale_min: float, scale_max: float, growth: float = 1.0) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.amount = amount
	emitter.lifetime = life
	emitter.local_coords = false
	emitter.mesh = mesh
	emitter.direction = Vector3.UP
	emitter.spread = spread
	emitter.initial_velocity_min = speed_min
	emitter.initial_velocity_max = speed_max
	emitter.gravity = Vector3(0.0, gravity_y, 0.0)
	emitter.scale_amount_min = scale_min
	emitter.scale_amount_max = scale_max
	emitter.color = color
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	emitter.color_ramp = fade
	if not is_equal_approx(growth, 1.0):
		var curve := Curve.new()
		curve.max_value = maxf(growth, 1.0)
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, growth))
		emitter.scale_amount_curve = curve
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emitter)
	return emitter

## Núcleo branco-amarelo, corpo laranja, ponta vermelha escura apagando em fumaça.
static func _fire_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1, 0.75, 0.35, 0.95), Color(0.9, 0.3, 0.06, 0.6), Color(0.25, 0.1, 0.05, 0)])
	return ramp

## Próximo emissor do rodízio `pool` (ver BURST_POOL).
func _take(key: String, pool: Array) -> CPUParticles3D:
	var index := int(_next_burst.get(key, 0))
	_next_burst[key] = (index + 1) % pool.size()
	return pool[index]

## Coloca o emissor em `point` com o eixo +Y apontando para `direction` e o dispara.
func _fire(emitter: CPUParticles3D, point: Vector3, direction: Vector3) -> void:
	var up := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	emitter.global_transform = Transform3D(Basis(side, up, side.cross(up)), point)
	emitter.restart()

## Gera textura procedural orgânica de poça de sangue com contorno multi-lobular e respingos satélites.
static func _make_blood_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var cx := 31.5
	var cy := 31.5
	var satellites := [
		Vector2(0.68, 0.28), Vector2(-0.62, -0.42), Vector2(0.28, -0.72),
		Vector2(-0.48, 0.65), Vector2(0.55, -0.55), Vector2(-0.72, 0.15)
	]
	var satellite_radii := [0.10, 0.08, 0.09, 0.11, 0.07, 0.08]
	for y in 64:
		for x in 64:
			var dx := (float(x) - cx) / 26.0
			var dy := (float(y) - cy) / 26.0
			var r := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var boundary := 0.70 + 0.14 * sin(angle * 5.0) + 0.08 * cos(angle * 3.0 + 1.2) + 0.04 * sin(angle * 7.0 - 0.6)
			var alpha := 0.0
			if r <= boundary:
				alpha = smoothstep(boundary, boundary - 0.07, r)
			else:
				var p := Vector2(dx, dy)
				for i in satellites.size():
					var dist := p.distance_to(satellites[i])
					var s_radius: float = satellite_radii[i]
					if dist <= s_radius:
						var s_alpha := smoothstep(s_radius, s_radius * 0.2, dist)
						alpha = maxf(alpha, s_alpha)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

## Marca de queimado: centro escuro, borda irregular esfumada.
static func _make_scorch_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (float(x) - 31.5) / 31.5
			var dy := (float(y) - 31.5) / 31.5
			var angle := atan2(dy, dx)
			var edge := 0.78 + 0.1 * sin(angle * 7.0) + 0.06 * cos(angle * 11.0 + 0.7)
			var r := sqrt(dx * dx + dy * dy) / edge
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r * r, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Faísca/poeira do material atingido. `normal` aponta para fora da superfície.
func impact(point: Vector3, normal: Vector3, material: String, damage: float) -> void:
	var key := material if _impact.has(material) else "world"
	var emitter := _take("impact_" + key, _impact[key])
	emitter.initial_velocity_max = 3.4 * clampf(0.7 + damage / 55.0, 0.7, 1.8)
	_fire(emitter, point, normal)
	if material == "concrete" or material == "world" or material == "wood":
		var dust := _take("dust", _impact_dust)
		dust.color = Color(0.58, 0.40, 0.22, 0.35) if material == "wood" else Color(0.72, 0.70, 0.64, 0.35)
		_fire(dust, point, normal)

## Gotas e névoa aerossolizada (V1 `_BloodBurst`): saem na direção do tiro, com mais força para mais dano.
func blood(point: Vector3, direction: Vector3, damage: float) -> void:
	var strength := clampf(0.6 + damage / 45.0, 0.6, 1.7)
	var drops := _take("blood", _blood)
	drops.amount = clampi(int(6.0 + damage * 0.35), 6, 14)
	drops.initial_velocity_min = 1.6 * strength
	drops.initial_velocity_max = 4.2 * strength
	_fire(drops, point, direction + Vector3.UP * 0.35)
	var mist := _take("blood_mist", _blood_mist)
	mist.initial_velocity_min = 0.3 * strength
	mist.initial_velocity_max = 1.1 * strength
	_fire(mist, point, direction * 0.6 + Vector3.UP * 0.2)

## Tufo de fumaça de pólvora saindo do cano ao disparar.
func muzzle_smoke(origin: Vector3, direction: Vector3) -> void:
	_fire(_muzzle_smoke, origin, direction * 0.8 + Vector3.UP * 0.5)

## Mancha orgânica expansiva no chão sob `foot` (anel de MAX_STAINS; pooling gradual de 2,4s e fade final).
func stain(foot: Vector3, radius: float) -> void:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.6, foot - Vector3.UP * 1.5, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty(): return
	var index := _next_stain
	_next_stain = (_next_stain + 1) % MAX_STAINS
	var node := _stains[index]
	var mat := _stain_materials[index]
	_stain_age[index] = 0.0
	_stain_target_radius[index] = radius
	var initial_r := radius * 0.2
	node.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(initial_r, 1.0, initial_r)), hit.position + Vector3.UP * 0.02)
	node.rotation = Vector3(0.0, randf() * TAU, 0.0)
	mat.albedo_color = Color(0.36, 0.015, 0.012, 0.92)
	node.visible = true
	set_physics_process(true)

## Cápsula ejetada (V1 `_ShellCasing`): sai pelo lado direito da arma, sobe, quica até duas vezes e some.
func shell(origin: Vector3, aim: Vector3, floor_y: float) -> void:
	var side := aim.cross(Vector3.UP).normalized()
	var seed_value := randf() * 2.0 - 1.0
	var index := _next_shell
	_next_shell = (_next_shell + 1) % MAX_SHELLS
	var node := _shells[index]
	node.global_position = origin + side * 0.25
	node.rotation = Vector3(0.0, randf() * TAU, 0.0)
	node.visible = true
	_shell_state[index] = {
		"life": SHELL_LIFETIME, "floor": floor_y + 0.012, "bounces": 0,
		"velocity": side * (SHELL_SIDE_SPEED + absf(seed_value) * SHELL_SIDE_SPREAD) + aim * (1.1 * seed_value) + Vector3.UP * SHELL_LIFT,
		"spin": randf_range(-16.0, 16.0)}
	set_physics_process(true)

## Cauda compacta que viaja à velocidade autorada da arma. O dano continua
## hitscan e é aplicado uma única vez por Gameplay; este nó é só apresentação.
func tracer(origin: Vector3, destination: Vector3, speed: float, color: Color, damage: float) -> void:
	var distance := origin.distance_to(destination)
	if distance < 0.05: return
	var index := _next_tracer
	_next_tracer = (_next_tracer + 1) % MAX_TRACERS
	var node := _tracers[index]
	var direction := origin.direction_to(destination)
	var duration := clampf(distance / maxf(speed, 1.0), 0.045, 0.48)
	var material := node.mesh.material as StandardMaterial3D
	material.albedo_color = Color.WHITE.lerp(color, 0.55)
	material.emission = color
	material.emission_energy_multiplier = clampf(1.3 + damage / 45.0, 1.3, 3.2)
	node.global_position = origin
	node.look_at(origin + direction)
	node.scale = Vector3(1.0, 1.0, clampf(0.7 + damage / 80.0, 0.7, 1.5))
	node.visible = true
	_tracer_state[index] = {"life": duration, "duration": duration, "from": origin, "to": destination, "direction": direction}
	set_physics_process(true)

## Police rounds own their swept flight in Gameplay, including impact timing.
## A token prevents a reused visual slot from being moved by an older round.
func police_tracer(origin: Vector3, direction: Vector3, speed := 55.0) -> Dictionary:
	var index := _next_tracer
	tracer(origin, origin + direction, 55.0, Color(1.0, 0.9, 0.2), 6.0)
	var token := {"index": index, "state": _tracer_state[index]}
	_tracer_state[index]["manual"] = true
	# V1 ordinary tracer is a compact tail behind the collision front.
	var tail := speed * 0.025 * 0.25
	_tracers[index].scale.z = tail / 0.42
	_tracers[index].global_position = origin - direction * tail * 0.5
	_tracer_state[index]["tail"] = tail
	_tracer_state[index]["direction"] = direction
	return token

func move_police_tracer(token: Dictionary, point: Vector3, finished := false) -> void:
	var index := int(token.index)
	if not is_same(_tracer_state[index], token.state): return
	_tracers[index].global_position = point - (token.state.direction as Vector3) * float(token.state.tail) * 0.5
	if finished:
		_tracers[index].hide()
		_tracer_state[index].life = 0.0

## Pacote de chama com núcleo, expansão e borda irregular, usando o mesmo
## alcance do raio de dano. O anel evita cortar o pacote anterior a 20 Hz.
func flame(origin: Vector3, direction: Vector3, distance: float) -> void:
	var index := _next_flame
	var packet := _flame_packets[index]
	var tongue := _flame_tongues[index]
	_next_flame = (_next_flame + 1) % MAX_FLAME_PACKETS
	packet.initial_velocity_min = maxf(6.0, distance / 0.32 * 0.70)
	packet.initial_velocity_max = maxf(8.0, distance / 0.32)
	_fire(packet, origin, direction + Vector3.UP * 0.02)
	tongue.global_position = origin
	tongue.look_at(origin + direction.normalized(), Vector3.UP)
	# Mesh length is exactly one metre along local -Z. Scale it to the actual
	# hitscan distance; the previous normalized span capped every visible jet at
	# ~0.2 m, even when the flame ray hit several metres away.
	var span := clampf(distance * 0.20, 0.35, 2.5)
	tongue.scale = Vector3(1.0, 1.0, span)
	tongue.transparency = 0.0
	tongue.visible = true
	_flame_tongue_state[index] = {
		"life": 0.34, "duration": 0.34, "distance": distance, "span": span,
		"origin": origin, "direction": direction.normalized(),
	}
	# Uma luz só, a meio caminho do jato, que tremula enquanto o gatilho segue.
	_flame_light.global_position = origin + direction.normalized() * minf(distance * 0.5, 2.5) + Vector3.UP * 0.3
	_flame_light.visible = true
	_flame_light_time = 0.12
	set_physics_process(true)

## Sopro traseiro do RPG (V1 `RocketBackblast`): fumaça atrás do cano.
func backblast(muzzle: Vector3, aim: Vector3) -> void:
	_fire(_backblast, muzzle - aim * 0.3, -aim + Vector3.UP * 0.2)

## Explosão: fagulhas, fumaça e um clarão curto de luz. A esfera emissiva continua sendo de `Gameplay.explode`.
## Bola de fogo aditiva, fagulhas, detritos escuros, fumaça que sobe e se abre, clarão e marca de queimado.
## Antes só havia fagulhas e fumaça: `Gameplay.explode` não criava a esfera que o comentário prometia.
func explosion(point: Vector3, radius: float) -> void:
	var size := clampf(radius / 7.5, 0.6, 1.6)
	_blast_fire.scale_amount_min = 0.8 * size
	_blast_fire.scale_amount_max = 1.6 * size
	_blast_fire.initial_velocity_max = 4.0 * size
	_fire(_blast_fire, point + Vector3.UP * 0.4, Vector3.UP)
	_fire(_blast_sparks, point + Vector3.UP * 0.3, Vector3.UP)
	_fire(_blast_debris, point + Vector3.UP * 0.2, Vector3.UP)
	_fire(_blast_smoke, point + Vector3.UP * 0.5, Vector3.UP)
	_blast_light.global_position = point + Vector3.UP * 1.0
	_blast_light.omni_range = maxf(6.0, radius * 2.0)
	_blast_light.light_energy = 8.0
	_blast_light.visible = true
	_blast_light_time = 0.3
	_scorch(point, clampf(radius * 0.45, 1.2, 3.5))
	set_physics_process(true)

func _scorch(point: Vector3, radius: float) -> void:
	if not is_inside_tree(): return
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point - Vector3.UP * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6: return
	var index := _next_scorch
	_next_scorch = (_next_scorch + 1) % MAX_SCORCHES
	var node := _scorches[index]
	node.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(radius, 1.0, radius)), hit.position + Vector3.UP * 0.015)
	(node.material_override as StandardMaterial3D).albedo_color.a = 0.85
	node.visible = true
	_scorch_age[index] = 0.0

## Rastro de fumaça contínuo no foguete; o emissor morre com o projétil.
func attach_rocket_trail(projectile: Node3D) -> void:
	var trail := CPUParticles3D.new()
	trail.amount = 16
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.mesh = _smoke_mesh
	trail.direction = Vector3.UP
	trail.spread = 20.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.6
	trail.color = Color(0.55, 0.5, 0.45, 0.4)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	trail.color_ramp = fade
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	projectile.add_child(trail)
	trail.emitting = true

## Zera tudo (troca de região, descarga): esconde cápsulas e manchas, PARA e LIMPA as partículas vivas
## (`restart` descarta as partículas em voo; em seguida `emitting = false`), apaga a luz e desliga o passo.
func clear() -> void:
	for index in MAX_SHELLS:
		_shells[index].visible = false
		_shell_state[index] = {"life": 0.0}
	for index in MAX_STAINS:
		_stains[index].visible = false
		_stain_age[index] = -1.0
	for index in MAX_TRACERS:
		_tracers[index].visible = false
		_tracer_state[index] = {"life": 0.0}
	for index in MAX_FLAME_PACKETS:
		_flame_tongues[index].visible = false
		_flame_tongue_state[index] = {"life": 0.0}
	for index in MAX_SCORCHES:
		_scorches[index].visible = false
		_scorch_age[index] = -1.0
	if is_instance_valid(_flame_light): _flame_light.visible = false
	_flame_light_time = 0.0
	var emitters: Array = _all_emitters()
	for emitter in emitters:
		if not is_instance_valid(emitter): continue
		emitter.restart()
		emitter.emitting = false
	if is_instance_valid(_blast_light): _blast_light.visible = false
	_blast_light_time = 0.0
	set_physics_process(false)

## Descarga: sem `restart()` (os emissores filhos podem já ter saído da árvore); só para a emissão, esconde e apaga a luz.
func shutdown() -> void:
	for node in _shells + _stains + _scorches:
		if is_instance_valid(node): node.visible = false
	if is_instance_valid(_flame_light): _flame_light.visible = false
	for tracer_node in _tracers:
		if is_instance_valid(tracer_node): tracer_node.visible = false
	for tongue in _flame_tongues:
		if is_instance_valid(tongue): tongue.visible = false
	var emitters: Array = _all_emitters()
	for emitter in emitters:
		if is_instance_valid(emitter): emitter.emitting = false
	if is_instance_valid(_blast_light): _blast_light.visible = false

func _all_emitters() -> Array:
	var list: Array = []
	for pool in _impact.values(): list.append_array(pool)
	list.append_array(_blood + _blood_mist + _impact_dust + _flame_packets)
	list.append_array([_muzzle_smoke, _blast_sparks, _blast_fire, _blast_debris, _blast_smoke, _backblast])
	return list

func _exit_tree() -> void:
	shutdown()

func _physics_process(delta: float) -> void:
	var active := false
	for index in MAX_FLAME_PACKETS:
		var flame_state: Dictionary = _flame_tongue_state[index]
		if float(flame_state.get("life", 0.0)) <= 0.0: continue
		active = true
		flame_state.life = float(flame_state.life) - delta
		var tongue := _flame_tongues[index]
		if float(flame_state.life) <= 0.0:
			tongue.visible = false
			continue
		var flame_progress := 1.0 - float(flame_state.life) / float(flame_state.duration)
		# Cada língua é um pacote curto em movimento. A cadência sustentada
		# sobrepõe os pacotes e forma o jato franjado do V1, sem uma cunha rígida.
		tongue.global_position = (flame_state.origin as Vector3) + (flame_state.direction as Vector3) * (float(flame_state.distance) * 0.86 * flame_progress)
		tongue.scale.z = float(flame_state.span) * minf(1.0, 0.18 + flame_progress * 4.0)
		tongue.transparency = smoothstep(0.66, 1.0, flame_progress)
	for index in MAX_TRACERS:
		var tracer_data: Dictionary = _tracer_state[index]
		if float(tracer_data.get("life", 0.0)) <= 0.0: continue
		active = true
		if tracer_data.get("manual", false): continue
		tracer_data.life = float(tracer_data.life) - delta
		var tracer_node := _tracers[index]
		if float(tracer_data.life) <= 0.0:
			tracer_node.visible = false
			continue
		var progress := 1.0 - float(tracer_data.life) / float(tracer_data.duration)
		tracer_node.global_position = (tracer_data.from as Vector3).lerp(tracer_data.to, progress)
	for index in MAX_SHELLS:
		var state: Dictionary = _shell_state[index]
		if float(state.life) <= 0.0: continue
		active = true
		state.life = float(state.life) - delta
		var node := _shells[index]
		if float(state.life) <= 0.0:
			node.visible = false
			continue
		var velocity: Vector3 = state.velocity
		velocity.y -= SHELL_GRAVITY * delta
		node.global_position += velocity * delta
		if node.global_position.y <= float(state.floor):
			node.global_position.y = float(state.floor)
			if velocity.y < -1.5 and int(state.bounces) < 2:
				velocity.y = -velocity.y * 0.35
				velocity.x *= 0.52
				velocity.z *= 0.52
				state.bounces = int(state.bounces) + 1
			else:
				velocity = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 10.0 * delta)
		state.velocity = velocity
		node.rotate_y(float(state.spin) * delta)
	for index in MAX_STAINS:
		if _stain_age[index] < 0.0: continue
		active = true
		_stain_age[index] += delta
		var age: float = _stain_age[index]
		if age >= STAIN_LIFETIME:
			_stain_age[index] = -1.0
			_stains[index].visible = false
			continue
		var pool_t := clampf(age / 2.4, 0.0, 1.0)
		var grow := lerpf(0.2, 1.0, smoothstep(0.0, 1.0, pool_t))
		var cur_r: float = _stain_target_radius[index] * grow
		_stains[index].scale = Vector3(cur_r, 1.0, cur_r)
		var color_t := clampf(age / 3.0, 0.0, 1.0)
		var base_color := Color(0.36, 0.015, 0.012).lerp(Color(0.14, 0.01, 0.01), color_t)
		var alpha := 0.92
		if age > (STAIN_LIFETIME - 4.0):
			alpha = lerpf(0.92, 0.0, (age - (STAIN_LIFETIME - 4.0)) / 4.0)
		_stain_materials[index].albedo_color = Color(base_color.r, base_color.g, base_color.b, alpha)
	for index in MAX_SCORCHES:
		if _scorch_age[index] < 0.0: continue
		active = true
		_scorch_age[index] += delta
		if _scorch_age[index] >= SCORCH_LIFETIME:
			_scorch_age[index] = -1.0
			_scorches[index].visible = false
		elif _scorch_age[index] > SCORCH_LIFETIME - 5.0:
			(_scorches[index].material_override as StandardMaterial3D).albedo_color.a = 0.85 * (SCORCH_LIFETIME - _scorch_age[index]) / 5.0
	if _flame_light_time > 0.0:
		active = true
		_flame_light_time -= delta
		_flame_light.light_energy = randf_range(1.6, 2.6)
		if _flame_light_time <= 0.0: _flame_light.visible = false
	if _blast_light_time > 0.0:
		active = true
		_blast_light_time -= delta
		_blast_light.light_energy = 8.0 * pow(maxf(0.0, _blast_light_time / 0.3), 1.6)
		if _blast_light_time <= 0.0: _blast_light.visible = false
	if not active: set_physics_process(false)
