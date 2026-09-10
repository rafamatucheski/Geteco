extends Node3D
## A 1.80m silhouette: quilted parka, fur hood, scarf, gloves, boots,
## cheek/nose details, goggles and role-specific backpack or radio.
var coat_color := Color("3f6872")
var role := "ranger"
var limbs: Array[Node3D] = []
var breath: MeshInstance3D
var clock := 0.0
var walking := false

func _ready() -> void:
	scale = Vector3(randf_range(.92,1.08),randf_range(.93,1.08),1)
	var boots := Color("272c30")
	var fur := [Color("c5b9a1"),Color("8a8172"),Color("b6b4aa")].pick_random() as Color
	for side in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side*0.13,0.77,0)
		add_child(leg)
		limbs.append(leg)
		part(leg,Vector3(0,-0.3,0),Vector3(0.19,0.60,0.20),Color("38454c"))
		part(leg,Vector3(0,-0.66,0.07),Vector3(0.23,0.22,0.34),boots)
		var arm := Node3D.new()
		arm.position = Vector3(side*0.30,1.36,0)
		add_child(arm)
		limbs.append(arm)
		part(arm,Vector3(0,-0.23,0),Vector3(0.21,0.48,0.23),coat_color)
		part(arm,Vector3(0,-0.51,0.015),Vector3(0.18,0.16,0.19),boots)
	part(self,Vector3(0,1.07,0),Vector3(0.56,0.73,0.36),coat_color)
	for y in [0.88,1.07,1.26]:
		part(self,Vector3(0,y,0.189),Vector3(0.49,0.012,0.012),coat_color.darkened(0.2))
	part(self,Vector3(0,1.08,0.197),Vector3(0.025,0.65,0.025),Color("b7c4c6"))
	for x in [-0.16,0.16]:
		part(self,Vector3(x,0.92,0.21),Vector3(0.17,0.16,0.055),coat_color.darkened(0.12))
	part(self,Vector3(0,1.56,-0.055),Vector3(0.40,0.43,0.34),fur)
	part(self,Vector3(0,1.57,0.12),Vector3(0.32,0.32,0.18),Color("c99277"))
	part(self,Vector3(0,1.69,0.14),Vector3(0.36,0.15,0.22),coat_color.darkened(0.4))
	part(self,Vector3(0,1.58,0.226),Vector3(0.30,0.065,0.036),Color("263e48"))
	part(self,Vector3(0,1.53,0.245),Vector3(0.065,0.07,0.06),Color("ce897b"))
	part(self,Vector3(0,1.42,0.15),Vector3(0.40,0.14,0.30),Color("b57a50"))
	part(self,Vector3(0.14,1.25,0.22),Vector3(0.11,0.30,0.055),Color("b57a50"))
	if role == "logger":
		part(self,Vector3(0,1.12,-0.27),Vector3(0.42,0.45,0.25),Color("765d42"))
	else:
		part(self,Vector3(-0.17,1.30,0.22),Vector3(0.105,0.16,0.06),boots)
		part(self,Vector3(-0.19,1.43,0.22),Vector3(0.015,0.16,0.018),boots)
	breath = part(self,Vector3(0,1.48,0.42),Vector3(0.12,0.08,0.18),Color(0.8,0.9,1,0.14))
	breath.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for side in [-1,1]:
		part(self,Vector3(side*.125,1.12,-.19),Vector3(.055,.57,.055),boots)
		part(self,Vector3(side*.18,.91,.241),Vector3(.095,.028,.025),Color("bec6be"))
		part(limbs[0 if side<0 else 2],Vector3(0,-.56,.08),Vector3(.18,.045,.18),Color("5b615e"))
	part(self,Vector3(-.13,1.31,.20),Vector3(.09,.055,.025),Color("d7c48b"))

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
	var exhale := fposmod(clock,3.4)/3.4
	breath.position.z = 0.36 + exhale*0.38
	breath.material_override.albedo_color.a = sin(exhale*PI)*0.16
