extends UrbanBuildingBase
class_name UrbanLandmarkFrontage3D

## Faithful native replacements for the three accessible North Frontage exteriors
## whose V1 positions already agree with the V2 catalog. Small facade details stay
## visual-only; only the architectural shell owns collision.

const V1_PUMP_OFFSET_X := 70.0 / 16.0
const V1_PUMP_OFFSET_Z := 140.0 / 16.0
var open_amount := 0.0
var entrance_door: Node3D

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount, 0.0, 1.0)
	if is_instance_valid(entrance_door): entrance_door.rotation.y = -PI * .5 * open_amount

func build() -> void:
	match building_id:
		"NorthFrontage0": _build_north_pier_bank()
		"NorthFrontage3": _build_union_clothing()
		"NorthFrontage4": _build_fuel_store()
		_: _build_default_box()

func _build_north_pier_bank() -> void:
	height = 4.8
	var stone := UrbanMaterials.material_for_color(Color("c7c6b5"), 0.86)
	var light_stone := UrbanMaterials.material_for_color(Color("e0dfce"), 0.82)
	var shadow_stone := UrbanMaterials.material_for_color(Color("92978b"), 0.88)
	var bronze := UrbanMaterials.metal_brass()
	var ink := UrbanMaterials.material_for_color(Color("263d3c"), 0.72)
	var glass := UrbanMaterials.glass_window()
	var front_z := building_size.y * 0.5

	# The native transfer vestibule needs standing depth behind the real leaf.
	# The previous back wall was only six centimetres behind its closed face.
	_build_recessed_shell(stone, 1.55, 1.65)
	add_roof_parapet(visuals_root, height, 0.34, 0.24, light_stone)
	add_roof_gravel(visuals_root, height)

	# V1 BankFacade: paired ATMs, four columns, deep glazing and a central pediment.
	for side in [-1.0, 1.0]:
		var window_x: float = side * building_size.x * 0.29
		add_mesh_box(visuals_root, "BankWindowFrame", Vector3(window_x, 2.05, front_z + 0.07), Vector3(2.35, 2.45, 0.16), shadow_stone)
		var pane := add_mesh_box(visuals_root, "BankWindowGlass", Vector3(window_x, 2.08, front_z + 0.17), Vector3(1.96, 1.94, 0.04), glass)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for bar in [-0.55, 0.0, 0.55]:
			add_mesh_box(visuals_root, "BankWindowBar", Vector3(window_x + bar, 2.08, front_z + 0.20), Vector3(0.045, 1.96, 0.05), bronze)
		_build_atm(Vector3(window_x, 0.92, front_z + 0.33), ink, shadow_stone, glass, "West" if side < 0.0 else "East")

	var column_xs: Array[float] = [
		-building_size.x * 0.43,
		-building_size.x * 0.15,
		building_size.x * 0.15,
		building_size.x * 0.43,
	]
	for index in column_xs.size():
		var x := column_xs[index]
		add_mesh_box(visuals_root, "BankColumnShaft_%d" % index, Vector3(x, 2.15, front_z + 0.42), Vector3(0.48, 3.45, 0.48), stone)
		add_mesh_box(visuals_root, "BankColumnBase_%d" % index, Vector3(x, 0.24, front_z + 0.42), Vector3(0.78, 0.28, 0.68), shadow_stone)
		add_mesh_box(visuals_root, "BankColumnCapital_%d" % index, Vector3(x, 3.95, front_z + 0.42), Vector3(0.82, 0.30, 0.68), light_stone)

	add_mesh_box(visuals_root, "BankEntablature", Vector3(0, 4.23, front_z + 0.28), Vector3(building_size.x + 0.18, 0.46, 0.48), light_stone)
	add_mesh_box(visuals_root, "BankPedimentLower", Vector3(0, 4.60, front_z + 0.30), Vector3(building_size.x * 0.58, 0.24, 0.54), shadow_stone)
	add_mesh_box(visuals_root, "BankPedimentTop", Vector3(0, 4.92, front_z + 0.30), Vector3(building_size.x * 0.36, 0.42, 0.50), light_stone)
	add_mesh_box(visuals_root, "BankRosette", Vector3(0, 4.72, front_z + 0.59), Vector3(0.42, 0.42, 0.08), bronze)
	_build_glazed_door(front_z, 0.0, 1.42, 2.52, ink, glass, bronze)
	_add_proper_name_sign(Vector3(0, 4.22, front_z + 0.57), Vector2(3.9, 0.58), ink)

	# Low copper-framed skylight from the original authored bank roof.
	var skylight := Node3D.new()
	skylight.name = "BankSkylight"
	skylight.position = Vector3(0, height + 0.12, -building_size.y * 0.18)
	add_mesh_box(skylight, "SkylightCurb", Vector3.ZERO, Vector3(4.25, 0.22, 1.85), bronze)
	var sky_glass := add_mesh_box(skylight, "SkylightGlass", Vector3(0, 0.14, 0), Vector3(3.82, 0.08, 1.45), glass)
	sky_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals_root.add_child(skylight)

func _build_union_clothing() -> void:
	height = 6.8
	var masonry := UrbanMaterials.material_for_color(Color("59665f"), 0.88)
	var trim := UrbanMaterials.material_for_color(Color("bca275"), 0.74)
	var glass := UrbanMaterials.glass_display()
	var dark := UrbanMaterials.material_for_color(Color("172a2b"), 0.78)
	var front_z := building_size.y * 0.5

	_build_recessed_shell(masonry, 1.45, 1.65)
	add_roof_parapet(visuals_root, height, 0.42, 0.24, UrbanMaterials.trim_stone())
	add_roof_gravel(visuals_root, height)
	add_cornice(visuals_root, height - 0.08, 0.34, 0.34, true, trim)

	# Upper brownstone volume remains recognizable above the fitted V1 storefront.
	for x in [-building_size.x * 0.28, 0.0, building_size.x * 0.28]:
		add_mesh_box(visuals_root, "UnionUpperFrame", Vector3(x, 5.10, front_z + 0.08), Vector3(1.48, 1.34, 0.14), trim)
		var upper_glass := add_mesh_box(visuals_root, "UnionUpperGlass", Vector3(x, 5.10, front_z + 0.17), Vector3(1.22, 1.08, 0.04), UrbanMaterials.glass_window())
		upper_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_mesh_box(visuals_root, "UnionFascia", Vector3(0, 3.55, front_z + 0.20), Vector3(building_size.x - 0.66, 0.58, 0.18), dark)
	_build_glazed_door(front_z, 0.0, 1.36, 2.46, dark, glass, trim)

	for side in [-1.0, 1.0]:
		var bay_x: float = side * building_size.x * 0.29
		add_mesh_box(visuals_root, "UnionDisplayFrame", Vector3(bay_x, 1.78, front_z + 0.23), Vector3(3.05, 2.72, 0.14), trim)
		var display_glass := add_mesh_box(visuals_root, "UnionDisplayGlass", Vector3(bay_x, 1.78, front_z + 0.32), Vector3(2.76, 2.43, 0.04), glass)
		display_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# V1 draws each dressed mannequin inside the display glass. In 3D, keep
		# it between the opaque shell and the pane so it remains visible yet enclosed.
		_build_dressed_mannequin(Vector3(bay_x, 0.0, front_z + 0.24), side > 0.0, "West" if side < 0.0 else "East")

	add_mesh_box(visuals_root, "UnionWelcomeMat", Vector3(0, 0.025, front_z + 0.86), Vector3(1.55, 0.05, 0.62), UrbanMaterials.material_for_color(Color("74644a"), 0.95))
	_add_proper_name_sign(Vector3(0, 3.55, front_z + 0.34), Vector2(4.7, 0.60), dark)
	var local_proper_name := Label3D.new()
	local_proper_name.name = "UnionProperName"
	local_proper_name.text = "Union"
	local_proper_name.font_size = 96
	local_proper_name.pixel_size = .006
	local_proper_name.outline_size = 0
	local_proper_name.modulate = Color("f5eedb")
	local_proper_name.position = Vector3(0, 3.55, front_z + .40)
	visuals_root.add_child(local_proper_name)

func _build_fuel_store() -> void:
	height = 5.2
	var masonry := UrbanMaterials.material_for_color(Color("a9b9a5"), 0.86)
	var trim := UrbanMaterials.material_for_color(Color("5f716a"), 0.78)
	var dark := UrbanMaterials.material_for_color(Color("25332f"), 0.78)
	var glass := UrbanMaterials.glass_display()
	var pump_red := UrbanMaterials.material_for_color(Color("b65c43"), 0.68)
	var front_z := building_size.y * 0.5

	_build_recessed_shell(masonry, 1.45, 1.65)
	add_roof_parapet(visuals_root, height, 0.34, 0.24, trim)
	add_roof_gravel(visuals_root, height)
	add_mesh_box(visuals_root, "FuelStoreFascia", Vector3(0, 3.72, front_z + 0.14), Vector3(building_size.x - 0.52, 0.58, 0.20), trim)
	_build_glazed_door(front_z, 0.0, 1.36, 2.44, dark, glass, UrbanMaterials.metal_steel())

	for side in [-1.0, 1.0]:
		var window_x: float = side * building_size.x * 0.27
		add_mesh_box(visuals_root, "FuelStoreWindowFrame", Vector3(window_x, 1.72, front_z + 0.15), Vector3(3.05, 2.45, 0.14), dark)
		var pane := add_mesh_box(visuals_root, "FuelStoreWindow", Vector3(window_x, 1.72, front_z + 0.24), Vector3(2.76, 2.16, 0.04), glass)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# The productive V1 adds exactly two pumps at (+/-70, 140) relative pixels.
	# They remain visual-only as in V1, so the central access corridor cannot snag.
	for side in [-1.0, 1.0]:
		_build_v1_fuel_pump(Vector3(side * V1_PUMP_OFFSET_X, 0.0, V1_PUMP_OFFSET_Z), pump_red, dark, glass, "West" if side < 0.0 else "East")

func _build_recessed_shell(material: Material, door_width: float, recess_depth: float) -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var rear_depth := building_size.y - recess_depth
	var rear_center_z := -half_d + rear_depth * 0.5
	add_solid_box(visuals_root, "LandmarkRearBody", Vector3(0, height * 0.5, rear_center_z), Vector3(building_size.x, height, rear_depth), material)

	var opening_width := door_width + 0.44
	var left_width := half_w - opening_width * 0.5
	var front_center_z := half_d - recess_depth * 0.5
	if left_width > 0.1:
		add_solid_box(visuals_root, "LandmarkFrontLeft", Vector3(-half_w + left_width * 0.5, height * 0.5, front_center_z), Vector3(left_width, height, recess_depth), material)
		add_solid_box(visuals_root, "LandmarkFrontRight", Vector3(half_w - left_width * 0.5, height * 0.5, front_center_z), Vector3(left_width, height, recess_depth), material)
	var lintel_height := height - 2.62
	if lintel_height > 0.1:
		add_solid_box(visuals_root, "LandmarkDoorLintel", Vector3(0, 2.62 + lintel_height * 0.5, front_center_z), Vector3(opening_width, lintel_height, recess_depth), material)

func _build_glazed_door(front_z: float, x: float, width: float, door_height: float, frame_mat: Material, glass_mat: Material, handle_mat: Material) -> void:
	var door_z := front_z - 0.72
	_build_walkup_door(Vector3(x, 0, door_z), width, door_height, frame_mat, glass_mat, handle_mat)

func _build_walkup_door(at: Vector3, width: float, door_height: float, frame_mat: Material, glass_mat: Material, handle_mat: Material) -> void:
	for side in [-1.0, 1.0]:
		add_solid_box(visuals_root, "BankDoorJamb", at + Vector3(side * (width * .5 + .055), door_height * .5, 0), Vector3(.11, door_height + .2, .12), frame_mat)
	add_mesh_box(visuals_root, "BankDoorHeader", at + Vector3(0, door_height + .05, 0), Vector3(width + .22, .1, .12), frame_mat)
	entrance_door = Node3D.new()
	entrance_door.name = "EntranceDoorHinge"
	entrance_door.position = at + Vector3(-width * .5, 0, 0)
	visuals_root.add_child(entrance_door)
	var pane := add_mesh_box(entrance_door, "EntranceDoorGlass", Vector3(width * .5, door_height * .5, 0), Vector3(width, door_height, .055), glass_mat)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [.045, width - .045]:
		add_mesh_box(entrance_door, "EntranceDoorLeafSide", Vector3(x, door_height * .5, 0), Vector3(.09, door_height, .10), frame_mat)
	for y in [.045, door_height - .045]:
		add_mesh_box(entrance_door, "EntranceDoorLeafRail", Vector3(width * .5, y, 0), Vector3(width, .09, .10), frame_mat)
	add_mesh_box(entrance_door, "EntranceDoorHandle", Vector3(width * .84, 1.08, .1), Vector3(.045, .34, .055), handle_mat)
	var body := StaticBody3D.new()
	body.name = "BankDoorSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, door_height, .10)
	collision.shape = shape
	collision.position = Vector3(width * .5, door_height * .5, 0)
	body.add_child(collision)
	entrance_door.add_child(body)
	set_open_amount(open_amount)

func _build_atm(at: Vector3, frame_mat: Material, body_mat: Material, screen_mat: Material, suffix: String) -> void:
	add_mesh_box(visuals_root, "BankATMBody_" + suffix, at, Vector3(0.86, 1.55, 0.48), body_mat)
	var screen := add_mesh_box(visuals_root, "BankATMScreen_" + suffix, at + Vector3(0, 0.37, 0.27), Vector3(0.57, 0.34, 0.04), screen_mat)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_mesh_box(visuals_root, "BankATMTray_" + suffix, at + Vector3(0, -0.10, 0.31), Vector3(0.61, 0.12, 0.16), frame_mat)
	add_mesh_box(visuals_root, "BankATMSlot_" + suffix, at + Vector3(0, -0.48, 0.27), Vector3(0.48, 0.08, 0.04), frame_mat)

func _build_dressed_mannequin(at: Vector3, long_coat: bool, suffix: String) -> void:
	var rig := Node3D.new()
	rig.name = "DressedMannequin_" + suffix
	rig.position = at
	var skin := UrbanMaterials.material_for_color(Color("e3d8c3"), 0.80)
	var outfit := UrbanMaterials.material_for_color(Color("c09868") if long_coat else Color("6595a5"), 0.76)
	var trousers := UrbanMaterials.material_for_color(Color("343a42") if long_coat else Color("243745"), 0.82)
	var shoes := UrbanMaterials.material_for_color(Color("172329"), 0.78)
	add_mesh_box(rig, "DisplayBase", Vector3(0, 0.035, 0), Vector3(0.54, 0.07, 0.42), dark_material())
	add_mesh_box(rig, "LeftShoe", Vector3(-0.10, 0.11, 0.04), Vector3(0.13, 0.12, 0.28), shoes)
	add_mesh_box(rig, "RightShoe", Vector3(0.10, 0.11, 0.04), Vector3(0.13, 0.12, 0.28), shoes)
	add_mesh_box(rig, "LeftLeg", Vector3(-0.10, 0.48, 0), Vector3(0.12, 0.66, 0.13), trousers)
	add_mesh_box(rig, "RightLeg", Vector3(0.10, 0.48, 0), Vector3(0.12, 0.66, 0.13), trousers)
	var coat_height := 0.72 if long_coat else 0.54
	add_mesh_box(rig, "OutfitTorso", Vector3(0, 1.06, 0), Vector3(0.43, coat_height, 0.22), outfit)
	add_mesh_box(rig, "Shoulders", Vector3(0, 1.31, 0), Vector3(0.50, 0.13, 0.24), outfit)
	for side in [-1.0, 1.0]:
		var arm := add_mesh_box(rig, "Sleeve", Vector3(side * 0.28, 1.02, 0), Vector3(0.10, 0.58, 0.12), outfit)
		arm.rotation.z = side * 0.08
		add_mesh_box(rig, "Hand", Vector3(side * 0.31, 0.72, 0), Vector3(0.09, 0.13, 0.10), skin)
	add_mesh_box(rig, "Neck", Vector3(0, 1.48, 0), Vector3(0.10, 0.14, 0.10), skin)
	_add_sphere(rig, "Head", Vector3(0, 1.66, 0), 0.16, skin)
	visuals_root.add_child(rig)

func _build_v1_fuel_pump(at: Vector3, pump_mat: Material, dark_mat: Material, glass_mat: Material, suffix: String) -> void:
	var pump := Node3D.new()
	pump.name = "FuelPump_" + suffix
	pump.position = at
	add_mesh_box(pump, "PumpPlinth", Vector3(0, 0.06, 0), Vector3(1.04, 0.12, 0.78), UrbanMaterials.sidewalk_stone())
	add_mesh_box(pump, "PumpBody", Vector3(0, 0.82, 0), Vector3(0.78, 1.52, 0.58), pump_mat)
	var display := add_mesh_box(pump, "PumpDisplay", Vector3(0, 1.10, 0.31), Vector3(0.54, 0.34, 0.04), glass_mat)
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_mesh_box(pump, "PumpMeter", Vector3(0, 0.72, 0.32), Vector3(0.42, 0.18, 0.04), dark_mat)
	add_mesh_box(pump, "PumpHose", Vector3(0.49, 0.74, 0), Vector3(0.06, 0.92, 0.07), dark_mat)
	add_mesh_box(pump, "PumpNozzle", Vector3(0.49, 1.18, 0.12), Vector3(0.13, 0.24, 0.08), UrbanMaterials.metal_steel())
	visuals_root.add_child(pump)

func _add_proper_name_sign(at: Vector3, size: Vector2, frame_mat: StandardMaterial3D) -> void:
	var canonical := UrbanSignage.extract_proper_name(building_id, str(data.get("name", "")))
	if canonical.is_empty():
		return
	var sign_node := UrbanSignage.create_sign_3d(canonical, size, 0.08, frame_mat)
	if sign_node != null:
		sign_node.position = at
		visuals_root.add_child(sign_node)

func _add_sphere(parent: Node3D, node_name: String, center: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	instance.mesh = sphere
	instance.position = center
	instance.material_override = material
	parent.add_child(instance)
	return instance

func dark_material() -> Material:
	return UrbanMaterials.material_for_color(Color("263b3d"), 0.84)
