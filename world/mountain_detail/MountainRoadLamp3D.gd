extends Node3D

## Small roadside lantern. The weather clock controls its shadowless light.
func _ready() -> void:
	name = "MountainRoadLamp"
	var pole := _box("Pole",Vector3(0,1.65,0),Vector3(.16,3.3,.16),Color("403e37"))
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box("LanternFrame",Vector3(0,3.45,0),Vector3(.42,.48,.42),Color("323b3d"))
	_box("LanternGlass",Vector3(0,3.45,0),Vector3(.30,.36,.30),Color("d1ab68"))
	_box("LanternCap",Vector3(0,3.75,0),Vector3(.5,.10,.5),Color("323b3d"))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.24,3.5,.24)
	collider.shape = shape
	collider.position.y = 1.75
	body.add_child(collider)
	add_child(body)
	var light := OmniLight3D.new()
	light.name = "RoadNightLight"
	light.position.y = 3.45
	light.light_color = Color("ffe0ab")
	light.omni_range = 10.0
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.set_meta("night_energy",1.15)
	light.add_to_group("mountain_night_light")
	add_child(light)

func _box(label: String,at: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	mesh.material_override = material
	add_child(mesh)
	return mesh
