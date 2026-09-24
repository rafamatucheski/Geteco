class_name MountainCabinInline3D
extends Node3D

## Seven compact rooms built at the physical scale of the mountain cabins.
var variant := 0
var materials: Dictionary = {}

func _ready() -> void:
	var wood: String = ["70513a", "765a45", "52656a", "755443", "69494c", "536671", "5f684d"][variant]
	var cloth: String = ["9f684f", "b4a07f", "718f8a", "aa7d63", "b68c6b", "7b737e", "697a7c"][variant]
	_box("Floor", Vector3(0, -.09, 0), Vector3(3.42, .18, 3.90), "8b7053")
	for i in 7:
		_box("Plank", Vector3(-1.43 + i * .47, .005, 0), Vector3(.44, .014, 3.78), "ab8a68" if i % 2 else "937556")
	_solid("BackWall", Vector3(0, 1.36, -1.90), Vector3(3.42, 2.72, .16), wood)
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(side * 1.69, 1.36, 0), Vector3(.16, 2.72, 3.82), wood)
		_solid("FrontWall%d" % int(side), Vector3(side * 1.10, 1.36, 1.88), Vector3(1.22, 2.72, .16), wood)
		_box("Window", Vector3(side * 1.68, 1.48, -.44), Vector3(.035, .72, .65), "718b91")
		_box("WindowFrame", Vector3(side * 1.69, 1.87, -.44), Vector3(.06, .07, .76), "312a24")
	_solid("Fireplace", Vector3(0, .55, -1.56), Vector3(.93, 1.10, .50), "586064")
	_box("Firebox", Vector3(0, .38, -1.26), Vector3(.56, .48, .035), "231b16")
	_box("Flames", Vector3(0, .34, -1.23), Vector3(.26, .36, .035), "e28a3f", true)
	_box("Mantel", Vector3(0, 1.13, -1.53), Vector3(1.12, .11, .63), "b18f65")
	var bed_left := not (variant in [1, 4])
	var bed_x := -1.16 if bed_left else 1.16
	_solid("Bed", Vector3(bed_x, .32, -.54), Vector3(.84, .64, 1.42), wood)
	_box("Blanket", Vector3(bed_x, .66, -.38), Vector3(.84, .08, .90), cloth)
	_box("Pillow", Vector3(bed_x, .67, -1.10), Vector3(.65, .08, .24), "d3c5a9")
	var furniture_x := 1.17 if bed_left else -1.17
	match variant:
		2:
			_solid("ForestMapDesk", Vector3(furniture_x, .52, -.38), Vector3(.72, 1.04, 1.18), "66523e")
			_box("ForestMap", Vector3(furniture_x, 1.07, -.38), Vector3(.65, .015, .94), "a4aa87")
		3:
			_solid("FishingBench", Vector3(furniture_x, .42, -.35), Vector3(.70, .84, 1.34), "6d5541")
			for z in [-.70, -.40, -.10]: _box("Rod", Vector3(furniture_x, 1.40, z), Vector3(.035, 1.95, .035), "c6aa78")
		4:
			_solid("SewingDesk", Vector3(furniture_x, .48, -.38), Vector3(.76, .96, 1.10), "76543e")
			_box("Fabric", Vector3(furniture_x, .98, -.30), Vector3(.60, .06, .66), "af6352")
		5:
			_solid("Piano", Vector3(furniture_x, .72, -.40), Vector3(.66, 1.44, 1.31), "302a29")
			_box("Keys", Vector3(furniture_x - .10, .80, -.40), Vector3(.45, .06, 1.12), "e6deca")
		6:
			_solid("PrintDesk", Vector3(furniture_x, .49, -.37), Vector3(.72, .98, 1.10), "5b5351")
			_box("Prints", Vector3(furniture_x, 1.00, -.37), Vector3(.60, .02, .68), "d9d1ba")
		_:
			_solid("WritingDesk", Vector3(furniture_x, .48, -.40), Vector3(.69, .96, 1.07), "71543e")
			_box("Journal", Vector3(furniture_x, .98, -.40), Vector3(.43, .025, .56), "d4c89d")
	_solid("LogSeat", Vector3(-1.08, .23, 1.17), Vector3(.74, .46, .51), "765338")
	_box("HearthRug", Vector3(0, .018, .55), Vector3(1.22, .014, 1.28), cloth)
	var fire := OmniLight3D.new()
	fire.position = Vector3(0, .65, -1.14)
	fire.light_color = Color("f2ad6b")
	fire.light_energy = 1.2
	fire.omni_range = 3.6
	fire.shadow_enabled = false
	add_child(fire)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-48, 30, 0)
	fill.light_color = Color("d8e5ea")
	fill.light_energy = .45
	fill.shadow_enabled = false
	add_child(fill)

func _material(color: String, emissive := false) -> StandardMaterial3D:
	var key := color + str(emissive)
	if materials.has(key): return materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = .78
	if emissive:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = .8
	materials[key] = material
	return material

func _box(id: String, point: Vector3, size: Vector3, color: String, emissive := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = id
	var shape := BoxMesh.new()
	shape.size = size
	part.mesh = shape
	part.material_override = _material(color, emissive)
	part.position = point
	add_child(part)
	return part

func _solid(id: String, point: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var part := _box(id, point, size, color)
	part.set_meta("interior_solid_id", StringName(id))
	return part
