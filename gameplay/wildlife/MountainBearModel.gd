extends "res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd"
## Low-poly anatomical masses, articulated jaw/paws and distinct cub proportions.
var is_cub := false
var alert := false
var charging := false
var dead := false
var hurt_flash := 0.0
var head: Node3D
var jaw: Node3D
var ears: Array[Node3D] = []
var fur_parts: Array[MeshInstance3D] = []
# Mais escuro que na V1: a exposição de inverno de Mountain deixava o pardo bege.
var fur_color := Color("3a2a1e")
var _flash_applied := false
var _fur_colors: Array[Color] = []
## Malhas compartilhadas por todas as peças (a escala é por nó): antes cada urso criava
## ~70 SphereMesh 20x10 e ~20 cilindros novos; o primeiro urso da serra custava 53 ms.
static var _sphere: SphereMesh
static var _claws := {}

func _ready() -> void:
	if is_cub:
		scale = Vector3.ONE * 0.53
		fur_color = Color("54402f")
	body = Node3D.new()
	body.name = "ShoulderMass"
	add_child(body)
	fur_parts.append(part(body,Vector3(0,0.86,-0.20),Vector3(0.97,0.96,1.54),fur_color))
	fur_parts.append(part(body,Vector3(0,1.05,0.40),Vector3(0.91,1.03,0.87),fur_color.darkened(0.08)))
	fur_parts.append(part(body,Vector3(0,1.26,0.28),Vector3(0.70,0.56,0.64),fur_color.lightened(0.04)))
	part(body,Vector3(0,0.63,-0.88),Vector3(0.24,0.26,0.22),fur_color.darkened(0.10))
	# Neck overlaps both skull and shoulder hump, avoiding disconnected round balls.
	fur_parts.append(part(body,Vector3(0,1.10,0.73),Vector3(0.71,0.63,0.66),fur_color))
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0,1.14,0.88)
	if is_cub: head.scale = Vector3.ONE * 1.12
	body.add_child(head)
	fur_parts.append(part(head,Vector3.ZERO,Vector3(0.63,0.63,0.65),fur_color))
	part(head,Vector3(0,-0.08,0.31),Vector3(0.40,0.26,0.47),Color("a38b6e"))
	part(head,Vector3(0,-0.025,0.52),Vector3(0.22,0.15,0.105),Color("242320"))
	for side in [-1.0,1.0]:
		part(head,Vector3(side*0.061,-0.013,0.567),Vector3(0.046,0.034,0.014),Color("090b0b"))
		part(head,Vector3(side*0.215,0.11,0.27),Vector3(0.062,0.047,0.040),Color("181611"))
		part(head,Vector3(side*0.21,0.123,0.292),Vector3(0.014,0.012,0.008),Color("ac9d77"))
		part(head,Vector3(side*0.215,0.163,0.20),Vector3(0.18,0.06,0.13),fur_color.darkened(0.08))
		var ear := Node3D.new()
		ear.position = Vector3(side*0.24,0.29,-0.01)
		head.add_child(ear)
		ears.append(ear)
		part(ear,Vector3.ZERO,Vector3(0.205,0.23,0.15),fur_color.darkened(0.20))
		part(ear,Vector3(0,0.02,0.065),Vector3(0.115,0.13,0.025),Color("4a372b"))
	jaw = Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0,-0.18,0.12)
	head.add_child(jaw)
	part(jaw,Vector3(0,0,0.20),Vector3(0.34,0.14,0.35),Color("7b634a"))
	part(jaw,Vector3(0,0.060,0.21),Vector3(0.29,0.018,0.25),Color("362226"))
	if not is_cub:
		for side in [-1.0,1.0]:
			_claw(jaw,Vector3(side*0.12,0.084,0.23),0.018,0.08,Color("c4b595"))
	for side in [-1.0,1.0]:
		for z in [-0.56,0.57]:
			var leg := Node3D.new()
			leg.position = Vector3(side*0.34,0.78,z)
			add_child(leg)
			limbs.append(leg)
			fur_parts.append(part(leg,Vector3(0,-0.21,0),Vector3(0.38,0.58,0.44),fur_color.darkened(0.06)))
			part(leg,Vector3(0,-0.49,0.01),Vector3(0.28,0.40,0.30),fur_color.darkened(0.12))
			part(leg,Vector3(0,-0.68,0.12),Vector3(0.34,0.20,0.43),Color("443b30"))
			for x in [-0.105,-0.035,0.035,0.105]:
				part(leg,Vector3(x,-0.69,0.28),Vector3(0.075,0.09,0.13),fur_color.darkened(0.25))
				_claw(leg,Vector3(x,-0.695,0.35),0.017,0.09,Color("bbab89"),true)
	# Small shoulder tufts enrich silhouette without hundreds of separate triangles.
	for side in [-1.0,1.0]:
		for i in 3:
			var tuft := part(body,Vector3(side*(0.34+i*0.02),1.11-i*0.10,0.44),Vector3(0.18,0.27,0.23),fur_color.darkened(i*0.025))
			tuft.rotation.z = side*0.4
	breath = part(head,Vector3(0,-0.08,0.72),Vector3(0.13,0.08,0.2),Color(0.82,0.89,0.93,0.0))
	breath.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mesh in fur_parts: _fur_colors.append(mesh.material_override.albedo_color)
	var shadow := part(self,Vector3(0,0.015,-0.02),Vector3(1.12,0.018,2.1),Color(0.04,0.035,0.025,0.20))
	shadow.name = "GroundContactShadow"
	shadow.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_keep_shader_variants(shadow)

## Os ursos nascem perto da toca e somem ao se afastar; com o último material de uma variante
## liberado, o Godot descarta o shader dela e a volta seguinte recompilava tudo: serra no EXE
## de 17/10, quadro de 64-75 ms a cada volta com pipelines_delta.surface +6. Uma cópia de cada
## variante (pelo com borda, focinho/garras, bafo transparente, sombra sem luz) fica viva.
static var _kept: Array[Material] = []

func _keep_shader_variants(shadow: MeshInstance3D) -> void:
	if not _kept.is_empty(): return
	for source in [fur_parts[0], breath, shadow]:
		if is_instance_valid(source) and source.material_override != null: _kept.append(source.material_override.duplicate())
	for claw in find_children("*", "MeshInstance3D", true, false):
		if claw.mesh is CylinderMesh and claw.material_override != null:
			_kept.append(claw.material_override.duplicate())
			break

## Peça do urso: esfera mais lisa que a dos moradores (10x5 segmentos virava bolha
## facetada vista de perto) e material com brilho de borda, que imita a pelagem
## pegando luz no contorno. Tom levemente variado por peça para o corpo não ser
## uma cor só. StandardMaterial3D de propósito: hurt_flash troca albedo_color.
func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radial_segments = 20
		_sphere.rings = 10
		_sphere.height = 2
		_sphere.radius = 1
	mesh.mesh = _sphere
	mesh.scale = size * 0.5
	mesh.position = point
	var material := StandardMaterial3D.new()
	var jitter := fmod(absf(point.x * 7.3 + point.y * 3.1 + point.z * 5.7), 1.0) - 0.5
	material.albedo_color = color.darkened(jitter * 0.08) if color.a >= 1.0 else color
	material.roughness = 1.0
	material.rim_enabled = true
	material.rim = 0.2
	material.rim_tint = 0.6
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _claw(parent: Node3D, point: Vector3, radius: float, length: float, color: Color, forward := false) -> void:
	var part_node := MeshInstance3D.new()
	var key := Vector2(radius, length)
	if not _claws.has(key):
		var claw_mesh := CylinderMesh.new()
		claw_mesh.top_radius = 0.001
		claw_mesh.bottom_radius = radius
		claw_mesh.height = length
		claw_mesh.radial_segments = 6
		_claws[key] = claw_mesh
	part_node.mesh = _claws[key]
	part_node.position = point
	if forward: part_node.rotation.x = PI*0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	part_node.material_override = mat
	parent.add_child(part_node)

func _process(delta: float) -> void:
	if dead: return
	clock += delta
	hurt_flash = maxf(0,hurt_flash-delta)
	var rate := 12.0 if charging else 6.0
	for i in limbs.size():
		limbs[i].rotation.x = sin(clock*rate+(PI if i in [0,3] else 0.0))*(0.43 if charging else (0.26 if walking else 0.01))
	body.position.y = absf(sin(clock*rate))*0.045 if walking else sin(clock*1.8)*0.009
	body.rotation.x = lerpf(body.rotation.x,0.12 if charging else 0.0,minf(delta*8,1))
	head.rotation.x = lerpf(head.rotation.x,0.23 if alert else (-0.08 if charging else 0.0),minf(delta*7,1))
	jaw.rotation.x = lerpf(jaw.rotation.x,-0.33 if alert or charging else 0.0,minf(delta*9,1))
	for ear in ears: ear.rotation.x = -0.42 if alert or charging else 0.0
	var flashing := hurt_flash > 0
	if flashing != _flash_applied:
		_flash_applied = flashing
		for i in fur_parts.size():
			fur_parts[i].material_override.albedo_color = _fur_colors[i].lerp(Color("ac453c"),0.5 if flashing else 0.0)
	var exhale := fposmod(clock,3.5)/3.5
	breath.position.z = 0.62+exhale*0.28
	breath.material_override.albedo_color.a = sin(exhale*PI)*0.12
