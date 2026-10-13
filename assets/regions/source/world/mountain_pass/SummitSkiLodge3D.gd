extends Node3D

## Chalé de ski do cume em escala humana real. As duas portas correspondem à
## chegada rodoviária (+Z) e à saída para as pistas na outra face (-Z).
const FINISH := preload("res://world/places/FacadeFinish.gd")
const SURFACE := preload("res://world/places/ShopInteriorMaterials.gd")
const SURFACE_FINISH := preload("res://assets/regions/source/world/mountain_pass/MountainSurfaceFinish.gd")
const ROOF_RIDGE := 5.85
const ROOF_RUN := 7.35
const ROOF_ANGLE := 18.0
const GROUND := preload("res://assets/regions/source/world/mountain_pass/MountainGroundMaterials.gd")
var footprint_size := Vector2(13.8, 8.4)
var front_entrance_local_position := Vector3(0, 0, 4.55)
var slope_entrance_local_position := Vector3(0, 0, -4.55)
var materials: Dictionary = {}

func _ready() -> void:
	_build_lodge()

func _mat(id: String, color: Color, roughness := 0.82, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	if materials.has(id): return materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	SURFACE_FINISH.apply(material, id)
	materials[id] = material
	return material

func _box(p_name: String, point: Vector3, size: Vector3, material: Material, p_rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = p_name
	node.set_meta("lodge_part", p_name)
	if p_name == "Roof": node.set_meta("exterior_part", "roof_slope")
	elif p_name == "RoofSnow": node.set_meta("exterior_part", "roof_snow")
	if p_name == "MainHall": node.set_meta("interior_solid_id",&"LodgeStructure")
	elif p_name == "PorchPost": node.set_meta("interior_solid_id",StringName(p_name+str(point)))
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation_degrees = p_rotation
	add_child(node)
	return node

func _cylinder(p_name: String, point: Vector3, radius: float, height: float, material: Material, p_rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = p_name
	node.set_meta("lodge_part", p_name)
	if p_name == "Roof": node.set_meta("exterior_part", "roof_slope")
	elif p_name == "RoofSnow": node.set_meta("exterior_part", "roof_snow")
	if p_name == "MainHall": node.set_meta("interior_solid_id",&"LodgeStructure")
	elif p_name == "PorchPost": node.set_meta("interior_solid_id",StringName(p_name+str(point)))
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation_degrees = p_rotation
	add_child(node)
	return node

func _build_lodge() -> void:
	var stone := _mat("stone", Color("59636a"), 0.95)
	var wood := _mat("wood", Color("6a432b"), 0.9)
	var timber := _mat("timber", Color("2e2119"), 0.94)
	var roof := _mat("roof", Color("26343e"), 0.82)
	var snow := GROUND.material_3d("snow")
	var glass := _mat("glass", Color(0.38, 0.66, 0.78, 0.74), 0.16, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var warm := _mat("warm", Color("ffd08a"), 0.35, 0.0, 0.65)
	var red := _mat("red", Color("a84b3e"), 0.75)
	# Acabamento por papel (tábua, telha, pedra, tecido) em vez do reboco único de antes.
	SURFACE_FINISH.apply(red, "red", "fabric")

	_box("Foundation", Vector3(0, 0.12, 0), Vector3(14.4, 0.24, 9.0), stone)
	_box("MainHall", Vector3(0, 1.75, 0), Vector3(13.6, 3.25, 8.1), wood)
	# The lower face clears the wall tops; both waters meet exactly at X=0.
	var angle := deg_to_rad(ROOF_ANGLE)
	var center_y := ROOF_RIDGE - ROOF_RUN * .5 * tan(angle)
	for side in [-1.0, 1.0]:
		var roof_center := Vector3(side * ROOF_RUN * .5, center_y, 0)
		_box("Roof", roof_center, Vector3(ROOF_RUN / cos(angle), .22, 9.2), roof, Vector3(0, 0, side * -ROOF_ANGLE))
		# Offset along the roof normal so the snow rests on, rather than crosses, it.
		var normal := Vector3(side * sin(angle), cos(angle), 0)
		_box("RoofSnow", roof_center + normal * .175, Vector3(ROOF_RUN / cos(angle), .13, 9.25), snow, Vector3(0, 0, side * -ROOF_ANGLE))
	_box("RoofRidge", Vector3(0, ROOF_RIDGE + .06, 0), Vector3(.25, .22, 9.25), roof)
	_box("RoofSnowRidge", Vector3(0, ROOF_RIDGE + .22, 0), Vector3(.32, .12, 9.3), snow)
	var underside_ridge := ROOF_RIDGE - .11 / cos(angle)
	var gable_base := underside_ridge - 6.8 * tan(angle)
	for side in [-1.0, 1.0]:
		_box("GableKnee", Vector3(0, (3.375 + gable_base) * .5, side * 4.02), Vector3(13.6, gable_base - 3.375, .08), wood)
		FINISH.gable(self, "LodgeGable", 6.8, gable_base, underside_ridge, side * 4.02, .08, wood)
		_box("EaveBeam", Vector3(side * 6.75, (3.375 + gable_base) * .5, 0), Vector3(.10, gable_base - 3.375, 8.1), timber)
	for x in [-6.45, 6.45]:
		_box("CornerTimber", Vector3(x, 1.8, 0), Vector3(0.35, 3.5, 8.25), timber)
	for z in [-3.9, 3.9]:
		for x in [-4.5, -2.7, 2.7, 4.5]:
			var face := 4.05 if z > 0 else -4.05
			FINISH.window(self, Vector3(x, 1.9, face), 0.0 if z > 0 else PI, 1.35, 1.55, timber, glass)
			_box("WindowWarmth", Vector3(x, 1.9, face + (.04 if z > 0 else -.04)), Vector3(.96, 1.12, .01), warm)
		# Vão visual das duas entradas; a interação acontece do lado de fora.
		_box("Door", Vector3(0, 1.25, z + (0.08 if z > 0 else -0.08)), Vector3(1.45, 2.35, 0.16), timber)
		_box("DoorWindow", Vector3(0, 1.6, z + (0.18 if z > 0 else -0.18)), Vector3(0.8, 0.72, 0.04), glass)
		_box("Porch", Vector3(0, 0.18, z + (0.75 if z > 0 else -0.75)), Vector3(4.3, 0.18, 1.45), timber)
		for x in [-1.85, 1.85]:
			_box("PorchPost", Vector3(x, 1.35, z + (0.92 if z > 0 else -0.92)), Vector3(0.22, 2.5, 0.22), timber)
		_box("PorchCanopy", Vector3(0, 2.7, z + (0.85 if z > 0 else -0.85)), Vector3(4.6, 0.18, 1.8), roof, Vector3(8.0 if z > 0 else -8.0, 0, 0))
	for side in [-1.0, 1.0]:
		for z in [-2.55, 0.0, 2.55]:
			FINISH.window(self, Vector3(side * 6.8, 1.9, z), side * PI * .5, 1.35, 1.55, timber, glass)
	_box("Chimney", Vector3(4.5, 4.5, -1.6), Vector3(1.1, 3.0, 1.1), stone)
	_box("ChimneySnow", Vector3(4.5, 6.03, -1.6), Vector3(1.3, 0.15, 1.3), snow)

	# Equipamentos visíveis junto à saída das pistas.
	for i in 5:
		var color: Material = [red, _mat("ski_blue", Color("3f7792")), _mat("ski_gold", Color("d0aa55"))][i % 3]
		_box("OutsideSki", Vector3(-5.65 + i * 0.28, 1.05, -4.45), Vector3(0.10, 0.10, 1.85), color, Vector3(-8, 0, -5))
	_box("SkiRack", Vector3(-5.1, 0.8, -4.25), Vector3(2.1, 0.12, 0.18), timber)

	var sign_node := Label3D.new()
	sign_node.name = "LodgeName"
	sign_node.text = "CUME BRANCO"
	sign_node.font_size = 72
	sign_node.pixel_size = 0.007
	sign_node.modulate = Color("f2e7cb")
	sign_node.outline_size = 0
	sign_node.position = Vector3(0, 3.15, 4.08)
	add_child(sign_node)

	for point in [Vector3(-4.5, 3.1, 4.25), Vector3(4.5, 3.1, 4.25), Vector3(0, 2.8, -4.25)]:
		var light := OmniLight3D.new()
		light.position = point
		light.light_color = Color("ffd6a0")
		light.light_energy = 0.75
		light.omni_range = 4.5
		add_child(light)
