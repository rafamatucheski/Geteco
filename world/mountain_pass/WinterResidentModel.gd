extends Node3D
## Moradores com casacos, gorros/capuzes, luvas e identidade por profissão.
## O construtor de peças abaixo também é usado pelos animais da serra.
var coat_color := Color("3f6872")
var role := "ranger"
var limbs: Array[Node3D] = []
var breath: MeshInstance3D
var clock := 0.0
var walking := false
var appearance_variant := 0
var appearance_female := false

func _ready() -> void:
	preload("res://world/shared/pedestrians/WinterWardrobe.gd").build(self)

func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.mesh.radial_segments = 10
	mesh.mesh.rings = 5
	mesh.mesh.height = 2
	mesh.mesh.radius = 1
	mesh.scale = size * 0.5
	mesh.position = point
	mesh.material_override = StandardMaterial3D.new()
	mesh.material_override.albedo_color = color
	mesh.material_override.roughness = 0.9
	parent.add_child(mesh)
	return mesh

func _process(delta: float) -> void:
	clock += delta
	for i in limbs.size():
		limbs[i].rotation.x = sin(clock*6.0 + (PI if i in [0,3] else 0.0)) * (0.30 if walking else 0.015)
	if not is_instance_valid(breath): return
	var exhale := fposmod(clock,3.4)/3.4
	breath.position.z = 0.36 + exhale*0.38
	breath.material_override.albedo_color.a = sin(exhale*PI)*0.16
