extends Node3D
## Vida da galeria do esgoto: água corrente no canal, deságue da tubulação,
## gotas, névoa rasteira, lâmpada com mau contato, ratos e o esconderijo da
## escopeta serrada da V1. Tudo é visual: nenhuma peça aqui cria sólido nem
## recebe "interior_solid_id", então o NativePlace não gera colisão para elas.
## Coordenadas em metros no espaço do SewerModel (V1 → (x-100)*.05, (y-17)*.05).

const CHANNEL_CENTER_X := 1.95
const CHANNEL_WIDTH := 2.7
const CHANNEL_LENGTH := 11.7
## A laje do piso do SewerModel vai até -0,08 m e cobre o canal inteiro (a caixa
## de água original fica enterrada nela); a lâmina precisa ficar acima disso.
const WATER_Y := -0.055
## Boca do deságue: passa por cima do cano horizontal do fundo (topo 0,59 m em
## z -4,85); atrás dele a câmera fixa não enxergaria a queda d'água.
const OUTFALL := Vector3(1.95, 0.84, -4.4)
## Mesmo ponto do SECRET_POSITION da V1 (265, 61).
const STASH := Vector3(8.25, 0.0, 2.2)
const RAT_SCARE_RADIUS := 2.2

const WATER_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.035, 0.1, 0.09, 1.0);
uniform vec4 shallow : source_color = vec4(0.1, 0.22, 0.17, 1.0);
uniform vec4 foam : source_color = vec4(0.36, 0.44, 0.38, 1.0);
uniform vec2 size_m = vec2(2.7, 11.7);
uniform float flow = 0.55;
uniform float landing = 1.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 m = UV * size_m;
	vec2 a = m * vec2(1.7, 0.8) + vec2(0.0, -TIME * flow * 1.2);
	vec2 b = m * vec2(2.3, 1.2) + vec2(0.7, -TIME * flow * 1.9);
	float n = noise(a) * 0.6 + noise(b) * 0.4;
	float streak = smoothstep(0.72, 0.95, noise(m * vec2(4.0, 0.5) + vec2(0.0, -TIME * flow * 2.6)));
	float edge = 1.0 - smoothstep(0.0, 0.24, min(UV.x, 1.0 - UV.x) * size_m.x);
	float head = (1.0 - smoothstep(0.0, 1.3, abs(UV.y * size_m.y - landing))) * (0.6 + 0.4 * noise(m * 4.0 + vec2(0.0, -TIME * 3.0)));
	vec3 col = mix(deep.rgb, shallow.rgb, n);
	col = mix(col, foam.rgb, clamp(edge * 0.35 * (0.5 + n) + streak * 0.2 + head * 0.6, 0.0, 1.0));
	ALBEDO = col;
	// Leve brilho próprio: sem ele a água some no escuro da galeria.
	EMISSION = col * 0.45;
	ROUGHNESS = 0.06 + n * 0.12;
	SPECULAR = 0.85;
	float dx = noise(a + vec2(0.07, 0.0)) - noise(a);
	float dz = noise(a + vec2(0.0, 0.07)) - noise(a);
	NORMAL_MAP = normalize(vec3(0.5 + dx * 3.5, 0.5 + dz * 3.5, 1.0));
}
"""

const SHEET_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float s = noise(vec2(UV.x * 9.0, UV.y * 2.2 - TIME * 3.8));
	float side = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	ALBEDO = mix(vec3(0.16, 0.30, 0.26), vec3(0.62, 0.72, 0.64), s);
	ALPHA = side * (0.42 + 0.45 * s);
}
"""

var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _soft: GradientTexture2D
var _ring: GradientTexture2D
var _haze: GradientTexture2D
var _drips: Array[Dictionary] = []
var _rats: Array[Dictionary] = []
var _flicker_light: OmniLight3D
var _flicker_bulb: StandardMaterial3D
var _flicker_base := 2.1
var _flicker_burst := 0.0
var _flicker_wait := 3.0
var _lantern: OmniLight3D
var _foam: MeshInstance3D
var _player: Node3D

func _ready() -> void:
	name = "SewerAtmosphere"
	_rng.seed = 2114
	_soft = _radial([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	# Queda quadrática: disco com borda suave, sem o "platô" do gradiente linear.
	_haze = _radial([[0.0, Color(1, 1, 1, 1)], [0.3, Color(1, 1, 1, 0.55)], [0.65, Color(1, 1, 1, 0.15)], [1.0, Color(1, 1, 1, 0)]])
	_ring = _radial([[0.0, Color(1, 1, 1, 0)], [0.62, Color(1, 1, 1, 0)], [0.82, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	_build_water()
	_build_outfall()
	_build_mist()
	_build_drips()
	_build_lamps()
	_build_stash()
	_build_rats()
	_build_player_sensor()

func _radial(stops: Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	gradient.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture

func _solid(color: String, metal := false, roughness := 0.8) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.metallic = 0.5 if metal else 0.0
	material.roughness = roughness
	return material

func _sprite(color: Color, texture: Texture2D, billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	if billboard: material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return material

func _add(mesh: Mesh, at: Vector3, material: Material, label := "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if not label.is_empty(): instance.name = label
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _box(size: Vector3, at: Vector3, material: Material, label := "") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, at, material, label)

func _cylinder(radius: float, length: float, at: Vector3, material: Material, segments := 14) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	return _add(mesh, at, material)

func _flat(size: float, at: Vector3, material: Material, label := "") -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.orientation = PlaneMesh.FACE_Y
	return _add(mesh, at, material, label)

# --- Canal -----------------------------------------------------------------

func _build_water() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(CHANNEL_WIDTH, CHANNEL_LENGTH)
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = WATER_SHADER
	material.set_shader_parameter("size_m", Vector2(CHANNEL_WIDTH, CHANNEL_LENGTH))
	_add(mesh, Vector3(CHANNEL_CENTER_X, WATER_Y, 0), material, "FlowingWater")

func _build_outfall() -> void:
	# Boca de tubulação saindo da parede do fundo, despejando no canal.
	var iron := _solid("#46564f", true, 0.55)
	var rust := _solid("#7d4a2c", true, 0.7)
	var run := -5.85 - OUTFALL.z
	var pipe := _cylinder(0.24, absf(run), OUTFALL + Vector3(0, 0, run * 0.5), iron, 18)
	pipe.name = "OutfallPipe"
	pipe.rotation.x = PI * 0.5
	var lip := TorusMesh.new()
	lip.inner_radius = 0.22
	lip.outer_radius = 0.29
	lip.rings = 20
	lip.ring_segments = 8
	var collar := _add(lip, OUTFALL, rust, "OutfallLip")
	collar.rotation.x = PI * 0.5
	var mouth := _cylinder(0.2, 0.01, OUTFALL + Vector3(0, 0, 0.01), _solid("#050908"), 18)
	mouth.rotation.x = PI * 0.5
	# Abraçadeira apoiando o cano sobre a tubulação do fundo.
	_box(Vector3(0.56, 0.05, 0.08), Vector3(OUTFALL.x, OUTFALL.y - 0.25, -4.95), rust, "OutfallBracket")
	# Bigodes de limo escorrendo da boca.
	for x in [-0.16, -0.05, 0.09, 0.18]:
		_box(Vector3(0.035, 0.22 + absf(x), 0.012), OUTFALL + Vector3(x, -0.2 - absf(x) * 0.5, 0.0), _solid("#2e4a30"))
	var sheet_material := ShaderMaterial.new()
	sheet_material.shader = Shader.new()
	sheet_material.shader.code = SHEET_SHADER
	var sheet_mesh := QuadMesh.new()
	sheet_mesh.size = Vector2(0.32, OUTFALL.y - 0.18 - WATER_Y)
	_add(sheet_mesh, Vector3(OUTFALL.x, (OUTFALL.y - 0.18 + WATER_Y) * 0.5, OUTFALL.z + 0.05), sheet_material, "OutfallSheet")
	_foam = _flat(0.9, Vector3(OUTFALL.x, WATER_Y + 0.012, OUTFALL.z + 0.12), _sprite(Color(0.75, 0.82, 0.74, 0.55), _soft, false), "OutfallFoam")
	var splash := CPUParticles3D.new()
	splash.name = "OutfallSplash"
	splash.position = Vector3(OUTFALL.x, WATER_Y + 0.02, OUTFALL.z + 0.08)
	splash.amount = 18
	splash.lifetime = 0.55
	splash.direction = Vector3(0, 1, 0.35)
	splash.spread = 38
	splash.initial_velocity_min = 0.7
	splash.initial_velocity_max = 1.4
	splash.gravity = Vector3(0, -9.8, 0)
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.1
	splash.scale_amount_min = 0.5
	splash.scale_amount_max = 1.0
	var droplet := SphereMesh.new()
	droplet.radius = 0.022
	droplet.height = 0.044
	droplet.radial_segments = 6
	droplet.rings = 3
	splash.mesh = droplet
	splash.material_override = _sprite(Color(0.7, 0.8, 0.74, 0.85), null, false)
	add_child(splash)
	# Brilho esverdeado sob a boca: o único ponto frio da galeria.
	var glow := OmniLight3D.new()
	glow.name = "OutfallGlow"
	glow.position = OUTFALL + Vector3(0, -0.45, 0.6)
	glow.light_color = Color("#5fcfae")
	glow.light_energy = 0.7
	glow.omni_range = 3.2
	glow.shadow_enabled = false
	add_child(glow)

func _build_mist() -> void:
	var mist := CPUParticles3D.new()
	mist.name = "ChannelMist"
	mist.position = Vector3(CHANNEL_CENTER_X, 0.05, -0.8)
	mist.amount = 10
	mist.lifetime = 8.0
	mist.preprocess = 8.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(1.1, 0.04, 4.2)
	mist.direction = Vector3(0, 0.15, 1)
	mist.spread = 25
	mist.gravity = Vector3.ZERO
	mist.initial_velocity_min = 0.05
	mist.initial_velocity_max = 0.14
	mist.scale_amount_min = 0.8
	mist.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	mist.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	mist.mesh = quad
	mist.material_override = _sprite(Color(0.6, 0.76, 0.7, 0.07), _haze, true)
	add_child(mist)

# --- Gotas -----------------------------------------------------------------

func _build_drips() -> void:
	# Juntas da tubulação do fundo, beirada da passarela sobre o canal e duas
	# goteiras do teto (fora do corte da câmera) que explicam as poças.
	var sources := [
		[Vector3(-9.15, 0.24, -4.85), 0.006], [Vector3(-3.3, 0.24, -4.85), 0.006],
		[Vector3(5.15, 0.24, -4.85), 0.006], [Vector3(8.8, 0.24, -4.85), 0.006],
		[Vector3(1.1, 0.03, 0.3), WATER_Y + 0.01], [Vector3(2.9, 0.03, -2.05), WATER_Y + 0.01],
		[Vector3(-8.25, 2.6, 3.4), 0.006], [Vector3(-2.4, 2.6, 4.35), 0.006],
	]
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.02
	drop_mesh.height = 0.06
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var drop_material := _solid("#a9c4bc", false, 0.1)
	drop_material.emission_enabled = true
	drop_material.emission = Color("#3b5550")
	for source in sources:
		var drop := _add(drop_mesh, source[0], drop_material, "Drip")
		drop.visible = false
		var ring_material := _sprite(Color(0.72, 0.84, 0.8, 0.0), _ring, false)
		var ring := _flat(0.5, Vector3(source[0].x, source[1], source[0].z), ring_material, "DripRipple")
		ring.visible = false
		_drips.append({"drop": drop, "ring": ring, "ring_material": ring_material, "origin": source[0], "floor": source[1], "wait": _rng.randf_range(0.2, 3.0), "fall": -1.0, "ripple": -1.0})

func _update_drips(delta: float) -> void:
	for drip in _drips:
		if drip.fall >= 0.0:
			drip.fall += delta
			var y: float = drip.origin.y - 4.9 * drip.fall * drip.fall
			if y <= drip.floor:
				drip.fall = -1.0
				drip.drop.visible = false
				drip.ripple = 0.0
				drip.ring.visible = true
			else:
				drip.drop.position.y = y
		elif drip.ripple >= 0.0:
			drip.ripple += delta
			var k: float = drip.ripple / 0.75
			drip.ring.scale = Vector3.ONE * lerpf(0.12, 1.0, k)
			drip.ring_material.albedo_color.a = 0.75 * (1.0 - k)
			if k >= 1.0:
				drip.ripple = -1.0
				drip.ring.visible = false
				drip.wait = _rng.randf_range(1.2, 4.5)
		else:
			drip.wait -= delta
			if drip.wait <= 0.0:
				drip.fall = 0.0
				drip.drop.position = drip.origin
				drip.drop.visible = true

# --- Luz -------------------------------------------------------------------

func _build_lamps() -> void:
	var lamps: Array[OmniLight3D] = []
	for child in get_parent().get_children():
		if child is OmniLight3D: lamps.append(child)
	for lamp in lamps:
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color("#ffe2a8")
		bulb.emission_enabled = true
		bulb.emission = Color("#ffc46e")
		bulb.emission_energy_multiplier = 3.0
		_box(Vector3(0.3, 0.035, 0.09), Vector3(lamp.position.x, 0.76, lamp.position.z - 0.52), bulb, "LampTube")
		# Halo quente na parede do fundo, onde a luz bate.
		var halo := _sprite(Color(1.0, 0.78, 0.45, 0.16), _soft, false)
		halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var quad := QuadMesh.new()
		quad.size = Vector2(2.6, 0.62)
		_add(quad, Vector3(lamp.position.x, 0.33, -5.83), halo, "LampHalo")
		# A lâmpada do lado leste é a que tem mau contato.
		if lamp.position.x > 0.0:
			_flicker_light = lamp
			_flicker_bulb = bulb
			_flicker_base = lamp.light_energy

func _update_flicker(delta: float) -> void:
	if _flicker_light == null: return
	var level := 1.0
	if _flicker_burst > 0.0:
		_flicker_burst -= delta
		# Sequência de liga/desliga irregular, como reator de fluorescente velho.
		level = 0.08 if sin(_time * 47.0) + sin(_time * 23.0) > 0.4 else 0.9
		if _flicker_burst <= 0.0: _flicker_wait = _rng.randf_range(2.5, 7.0)
	else:
		_flicker_wait -= delta
		level = 0.96 + 0.04 * sin(_time * 90.0)
		if _flicker_wait <= 0.0: _flicker_burst = _rng.randf_range(0.25, 0.9)
	_flicker_light.light_energy = _flicker_base * level
	_flicker_bulb.emission_energy_multiplier = 3.0 * level
	if _lantern != null: _lantern.light_energy = 0.95 + 0.12 * sin(_time * 7.3) + 0.06 * sin(_time * 17.1)
	if _foam != null: _foam.scale = Vector3.ONE * (1.0 + 0.08 * sin(_time * 5.0))

# --- Esconderijo -----------------------------------------------------------

func _build_stash() -> void:
	# Lona rasgada, laje do piso arrancada e um lampião: alguém usa este canto.
	var tarp := _box(Vector3(1.25, 0.012, 0.85), STASH + Vector3(0, 0.006, 0.05), _solid("#3d4630", false, 0.95), "StashTarp")
	tarp.rotation.y = 0.18
	var hole := _box(Vector3(0.5, 0.01, 0.36), STASH + Vector3(-0.72, 0.004, -0.42), _solid("#0a0f0e"), "StashHole")
	hole.rotation.y = 0.06
	var slab := _box(Vector3(0.5, 0.07, 0.36), STASH + Vector3(-1.22, 0.07, -0.3), _solid("#5b6557"), "StashSlab")
	slab.rotation = Vector3(0.0, -0.4, 0.28)
	for i in 3:
		var brick := _box(Vector3(0.2, 0.08, 0.1), STASH + Vector3(0.72 + i * 0.04, 0.04 + i * 0.075, -0.45), _solid("#7a5a44"), "StashBrick")
		brick.rotation.y = 0.2 * i
	var body := _cylinder(0.07, 0.2, STASH + Vector3(0.7, 0.1, 0.52), _solid("#9a8040", true, 0.5))
	body.name = "StashLantern"
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color("#ffd28a")
	flame.emission_enabled = true
	flame.emission = Color("#ffab4a")
	flame.emission_energy_multiplier = 4.0
	_cylinder(0.045, 0.08, STASH + Vector3(0.7, 0.24, 0.52), flame)
	_lantern = OmniLight3D.new()
	_lantern.name = "StashLanternLight"
	_lantern.position = STASH + Vector3(0.7, 0.4, 0.52)
	_lantern.light_color = Color("#ffb45c")
	_lantern.light_energy = 1.0
	_lantern.omni_range = 2.0
	_lantern.shadow_enabled = false
	add_child(_lantern)

# --- Ratos -----------------------------------------------------------------

func _build_rats() -> void:
	# Oeste: rodapé do fundo, atrás do cano, e a beirada do canal.
	# Leste: entre os caixotes e a parede sul, subindo pela parede leste.
	var routes := [
		[Vector3(-10.1, 0, -5.45), Vector3(-5.0, 0, -5.45), Vector3(0.35, 0, -5.45), Vector3(0.35, 0, -2.5)],
		[Vector3(3.8, 0, 5.5), Vector3(7.0, 0, 5.52), Vector3(10.3, 0, 5.5), Vector3(10.3, 0, 1.6)],
	]
	for route in routes:
		var rat := _make_rat()
		rat.position = route[0]
		_rats.append({"node": rat, "route": route, "index": 0, "target": 1, "pause": _rng.randf_range(0.5, 2.5), "speed": 0.0, "phase": _rng.randf() * TAU})

func _make_rat() -> Node3D:
	var rat := Node3D.new()
	rat.name = "Rat"
	add_child(rat)
	var fur := _solid("#4a4038", false, 0.95)
	var skin := _solid("#b38c84", false, 0.8)
	var parts := Node3D.new()
	parts.name = "Body"
	rat.add_child(parts)
	var torso := CapsuleMesh.new()
	torso.radius = 0.06
	torso.height = 0.26
	torso.radial_segments = 10
	torso.rings = 4
	var body := MeshInstance3D.new()
	body.mesh = torso
	body.material_override = fur
	body.rotation.x = PI * 0.5
	body.position = Vector3(0, 0.06, 0)
	body.scale = Vector3(1.0, 1.0, 0.8)
	parts.add_child(body)
	var skull := SphereMesh.new()
	skull.radius = 0.045
	skull.height = 0.08
	skull.radial_segments = 8
	skull.rings = 4
	var head := MeshInstance3D.new()
	head.mesh = skull
	head.material_override = fur
	head.position = Vector3(0, 0.06, -0.15)
	head.scale = Vector3(0.9, 0.85, 1.3)
	parts.add_child(head)
	for side in [-1, 1]:
		var ear := MeshInstance3D.new()
		var ear_mesh := SphereMesh.new()
		ear_mesh.radius = 0.02
		ear_mesh.height = 0.02
		ear.mesh = ear_mesh
		ear.material_override = skin
		ear.position = Vector3(side * 0.03, 0.1, -0.13)
		parts.add_child(ear)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.006
	tail.bottom_radius = 0.014
	tail.height = 0.26
	tail.radial_segments = 5
	var tail_pivot := Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0, 0.04, 0.12)
	parts.add_child(tail_pivot)
	var tail_mesh := MeshInstance3D.new()
	tail_mesh.mesh = tail
	tail_mesh.material_override = skin
	tail_mesh.rotation.x = PI * 0.5 - 0.15
	tail_mesh.position = Vector3(0, -0.015, 0.13)
	tail_pivot.add_child(tail_mesh)
	for mesh in parts.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rat

func _update_rats(delta: float) -> void:
	for rat in _rats:
		var node: Node3D = rat.node
		var route: Array = rat.route
		var scared := _player != null and is_instance_valid(_player) and to_local(_player.global_position).distance_to(node.position) < RAT_SCARE_RADIUS
		if scared and rat.speed < 3.0:
			# Foge para a ponta da rota mais distante do Dante.
			var local_player := to_local(_player.global_position)
			rat.target = 0 if route[0].distance_to(local_player) > route[-1].distance_to(local_player) else route.size() - 1
			rat.pause = 0.0
			rat.speed = 3.6
		if rat.pause > 0.0:
			rat.pause -= delta
			# Parado, só a cauda e o focinho mexem.
			node.get_node("Body/TailPivot").rotation.y = 0.35 * sin(_time * 2.2 + rat.phase)
			node.get_node("Body").position.y = 0.0
			continue
		if rat.speed <= 0.0: rat.speed = _rng.randf_range(1.2, 2.2)
		var goal: Vector3 = route[rat.target]
		var offset: Vector3 = goal - node.position
		var step: float = rat.speed * delta
		if offset.length() <= step:
			node.position = goal
			rat.index = rat.target
			rat.speed = 0.0
			rat.pause = _rng.randf_range(0.6, 3.5)
			if rat.index == 0: rat.target = 1
			elif rat.index == route.size() - 1: rat.target = route.size() - 2
			else: rat.target = rat.index + (1 if _rng.randf() < 0.5 else -1)
			continue
		node.position += offset.normalized() * step
		node.rotation.y = atan2(-offset.x, -offset.z)
		node.get_node("Body").position.y = absf(sin(_time * 28.0 + rat.phase)) * 0.012
		node.get_node("Body/TailPivot").rotation.y = 0.5 * sin(_time * 14.0 + rat.phase)

func _build_player_sensor() -> void:
	var sensor := Area3D.new()
	sensor.name = "RatSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 2
	sensor.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(23.0, 2.0, 13.5)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	sensor.add_child(shape)
	add_child(sensor)
	sensor.body_entered.connect(func(body: Node3D):
		if body.get_meta("gameplay_role", "") == "player": _player = body)
	sensor.body_exited.connect(func(body: Node3D):
		if body == _player: _player = null)

func _process(delta: float) -> void:
	_time += delta
	_update_drips(delta)
	_update_flicker(delta)
	_update_rats(delta)
