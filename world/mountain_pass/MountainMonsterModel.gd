extends Node3D

var walking := false
var charging := false
var clock := 0.0
var torso: Node3D
var head: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []

func _ready() -> void:
	var fur := _mat(Color("a9b5b5"), 0.98)
	var shadow_fur := _mat(Color("657176"), 0.98)
	var skin := _mat(Color("394348"), 0.92)
	var eye := _mat(Color("cf493f"), 0.42, 2.8)
	torso = Node3D.new()
	torso.name = "Torso"
	add_child(torso)
	_sphere(torso, Vector3(0, 1.48, 0), Vector3(0.92, 1.35, 0.62), fur)
	_sphere(torso, Vector3(0, 2.18, -0.03), Vector3(0.72, 0.63, 0.54), shadow_fur)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 2.52, -0.02)
	torso.add_child(head)
	_sphere(head, Vector3.ZERO, Vector3(0.55, 0.62, 0.50), fur)
	_sphere(head, Vector3(0, -0.10, -0.38), Vector3(0.34, 0.24, 0.30), skin)
	for side in [-1.0, 1.0]:
		_sphere(head, Vector3(side * 0.18, 0.08, -0.45), Vector3(0.07, 0.055, 0.045), eye)
		var horn := _cylinder(head, Vector3(side * 0.34, 0.37, -0.02), 0.07, 0.62, skin)
		horn.rotation_degrees = Vector3(0, 0, side * -36)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.67, 1.98, 0)
		add_child(arm)
		arms.append(arm)
		_cylinder(arm, Vector3(side * 0.08, -0.72, 0), 0.18, 1.62, shadow_fur)
		_sphere(arm, Vector3(side * 0.14, -1.53, -0.02), Vector3(0.30, 0.34, 0.25), skin)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.35, 0.94, 0)
		add_child(leg)
		legs.append(leg)
		_cylinder(leg, Vector3(0, -0.43, 0), 0.23, 1.05, shadow_fur)
		_sphere(leg, Vector3(0, -1.02, -0.14), Vector3(0.33, 0.24, 0.52), skin)
	var contact := _sphere(self, Vector3(0, 0.03, 0), Vector3(0.95, 0.025, 0.65), _mat(Color(0.02, 0.03, 0.04, 0.30), 1.0))
	contact.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func animate(delta: float) -> void:
	clock += delta
	var rate := 10.0 if charging else 5.0
	var amount := 0.48 if charging else (0.24 if walking else 0.025)
	for i in legs.size():
		legs[i].rotation.x = sin(clock * rate + i * PI) * amount
	for i in arms.size():
		arms[i].rotation.x = sin(clock * rate + (i + 1) * PI) * amount * 0.75
	if torso:
		torso.position.y = absf(sin(clock * rate)) * (0.055 if walking else 0.012)
		torso.rotation.x = lerpf(torso.rotation.x, 0.20 if charging else 0.0, minf(1.0, delta * 6.0))
	if head:
		head.rotation.x = lerpf(head.rotation.x, -0.18 if charging else 0.04, minf(1.0, delta * 7.0))

func _mat(color: Color, roughness: float, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _sphere(parent: Node3D, point: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 7
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.scale = scale_value
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.84
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 9
	node.mesh = mesh
	node.material_override = material
	node.position = point
	parent.add_child(node)
	return node
