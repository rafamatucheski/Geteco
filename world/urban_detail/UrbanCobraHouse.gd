extends UrbanBuildingBase
class_name UrbanCobraHouse

## Reconstructs the 8 residential bungalows of the Cobra gang quarter in East Harbor.
## Features pitched corrugated tin/shingle roofs with overhanging eaves, covered wooden front porches,
## timber support posts, residential steps, and domestic window frames.

func build() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var porch_depth := 1.8
	var house_depth := building_size.y - porch_depth
	var house_center_z := -half_d + house_depth * 0.5
	var house_front_z := house_center_z + house_depth * 0.5
	
	var wall_mat := UrbanMaterials.material_for_color(base_color, 0.86)
	var roof_mat := UrbanMaterials.roof_tin_rusty() if building_id in ["TinRoofHouse", "PorchHouse", "CobraWorkshop"] else UrbanMaterials.roof_shingle()
	var wood_mat := UrbanMaterials.wood_porch()
	var trim_mat := UrbanMaterials.trim_stone()
	
	# Main enclosed house volume (solid collision)
	add_solid_box(visuals_root, "HouseBody", Vector3(0, height * 0.5, house_center_z), Vector3(building_size.x, height, house_depth), wall_mat)
	
	# Pitched Roof with overhanging eaves
	_build_pitched_roof(house_center_z, house_depth + porch_depth * 0.6, roof_mat)
	
	# Covered Front Porch
	_build_porch(house_front_z, porch_depth, wood_mat, roof_mat)
	
	# Front residential door and windows
	_build_facade_elements(house_front_z)
	
	# Side/Rear windows
	_build_side_windows(house_center_z, house_depth)
	
	# Stovepipe / brick chimney
	add_chimney(visuals_root, Vector3(half_w * 0.35, height + 0.8, house_center_z - 0.4), 1.2, 1)
	_build_authored_identity(house_center_z, house_front_z, house_depth)

func _build_authored_identity(house_center_z: float, house_front_z: float, house_depth: float) -> void:
	# The V1 sites are deliberately not eight copies of one bungalow. Preserve
	# their readable roof/plan distinctions while sharing the base construction.
	var dark := UrbanMaterials.trim_dark()
	var metal := UrbanMaterials.metal_steel()
	match building_id:
		"Duplex", "BrickDuplex":
			add_mesh_box(visuals_root,"DuplexPartyWall",Vector3(0,height+.78,house_center_z),Vector3(.16,1.45,house_depth+.55),dark)
			for side in [-1.0,1.0]: add_mesh_box(visuals_root,"DuplexEntryCanopy",Vector3(side*building_size.x*.23,2.45,house_front_z+.55),Vector3(building_size.x*.34,.12,1.15),metal)
		"CobraWorkshop":
			add_solid_box(visuals_root,"WorkshopRearBay",Vector3(0,1.65,house_center_z-house_depth*.42),Vector3(building_size.x*.82,3.3,house_depth*.36),UrbanMaterials.material_for_color(Color("4d5047")))
			add_mesh_box(visuals_root,"WorkshopForecourtAwning",Vector3(0,2.75,house_front_z+1.25),Vector3(building_size.x+1.0,.16,2.5),UrbanMaterials.roof_tin_rusty())
			for x in [-building_size.x*.43,building_size.x*.43]: add_mesh_box(visuals_root,"WorkshopAwningPost",Vector3(x,1.38,house_front_z+2.1),Vector3(.13,2.75,.13),dark)
		"CourtyardHouse":
			add_solid_box(visuals_root,"CourtyardWing",Vector3(-building_size.x*.38,1.45,house_center_z-house_depth*.18),Vector3(building_size.x*.36,2.9,house_depth*.68),UrbanMaterials.material_for_color(base_color.darkened(.08)))
			add_mesh_box(visuals_root,"CourtyardWingRoof",Vector3(-building_size.x*.38,3.02,house_center_z-house_depth*.18),Vector3(building_size.x*.42,.18,house_depth*.76),UrbanMaterials.roof_shingle())
		"TinRoofHouse":
			for rib in 7:
				var x := lerpf(-building_size.x*.43,building_size.x*.43,float(rib)/6.0)
				add_mesh_box(visuals_root,"TinRoofRib",Vector3(x,height+1.12,house_center_z),Vector3(.055,.06,house_depth+1.0),metal)
		"ShingleHouse":
			for row in 5:
				add_mesh_box(visuals_root,"ShingleCourse",Vector3(0,height+.42+row*.22,house_center_z+(2-row)*.22),Vector3(building_size.x+.65,.055,house_depth*.18),dark)
		"PorchHouse":
			add_mesh_box(visuals_root,"PorchHouseShade",Vector3(0,2.62,house_front_z+1.15),Vector3(building_size.x+.7,.14,2.25),UrbanMaterials.roof_tin_rusty())
		"CornerBungalow":
			add_mesh_box(visuals_root,"CornerBungalowSideShade",Vector3(building_size.x*.42,2.35,house_center_z),Vector3(1.35,.12,house_depth*.72),UrbanMaterials.roof_shingle())

func _build_pitched_roof(center_z: float, depth: float, roof_mat: StandardMaterial3D) -> void:
	var pitch_h := 1.5
	var overhang := 0.45
	var roof_w := building_size.x + overhang * 2.0
	var roof_d := depth + overhang * 2.0
	
	# Sloped roof planes (front and rear slopes)
	var half_rd := roof_d * 0.5
	var slope_y := height + pitch_h * 0.5
	
	# Front slope
	var front_slope := add_mesh_box(visuals_root, "RoofFrontSlope", Vector3(0, slope_y, center_z + half_rd * 0.5), Vector3(roof_w, 0.08, half_rd), roof_mat)
	front_slope.rotation.x = -0.38
	
	# Rear slope
	var rear_slope := add_mesh_box(visuals_root, "RoofRearSlope", Vector3(0, slope_y, center_z - half_rd * 0.5), Vector3(roof_w, 0.08, half_rd), roof_mat)
	rear_slope.rotation.x = 0.38
	
	# Ridge cap
	add_mesh_box(visuals_root, "RoofRidge", Vector3(0, height + pitch_h + 0.04, center_z), Vector3(roof_w + 0.08, 0.10, 0.22), UrbanMaterials.metal_dark())
	
	# Gable end triangles / side fascia boards
	for side in [-building_size.x * 0.5 - 0.02, building_size.x * 0.5 + 0.02]:
		add_mesh_box(visuals_root, "GableTrim", Vector3(side, height + pitch_h * 0.45, center_z), Vector3(0.08, pitch_h * 0.9, depth), UrbanMaterials.trim_dark())

func _build_porch(house_front_z: float, porch_depth: float, wood_mat: StandardMaterial3D, roof_mat: StandardMaterial3D) -> void:
	var porch := Node3D.new()
	porch.name = "FrontPorch"
	porch.position = Vector3(0, 0, house_front_z)
	
	var porch_w := building_size.x
	var deck_h := 0.35
	var porch_center_z := porch_depth * 0.5
	
	# Wooden porch deck (raised floor)
	add_mesh_box(porch, "PorchDeck", Vector3(0, deck_h * 0.5, porch_center_z), Vector3(porch_w, deck_h, porch_depth), wood_mat)
	
	# Front steps down to grade
	var step_w := 1.8
	var steps := 2
	for s in steps:
		var sy := float(s) * (deck_h / 2.0) + (deck_h / 4.0)
		var sz := porch_depth + float(steps - 1 - s) * 0.32 + 0.16
		add_mesh_box(porch, "PorchStep_%d" % s, Vector3(0, sy, sz), Vector3(step_w, deck_h * 0.5, 0.32), wood_mat)
	
	# Timber support posts along front edge of porch
	var post_mat := UrbanMaterials.wood_door_brown()
	var post_h := 2.4
	var post_count := 4
	var post_step := (porch_w - 0.5) / float(post_count - 1)
	
	for p in post_count:
		var px := -porch_w * 0.5 + 0.25 + float(p) * post_step
		add_mesh_box(porch, "PorchPost_%d" % p, Vector3(px, deck_h + post_h * 0.5, porch_depth - 0.15), Vector3(0.14, post_h, 0.14), post_mat)
	
	# Porch balustrade / railing (left and right of center steps)
	var rail_h := 0.75
	var rail_y := deck_h + rail_h * 0.5
	var half_pw := porch_w * 0.5
	var left_rail_w := (half_pw - step_w * 0.5) - 0.2
	var right_rail_w := left_rail_w
	
	if left_rail_w > 0.6:
		add_mesh_box(porch, "PorchRailLeft", Vector3(-half_pw + 0.2 + left_rail_w * 0.5, rail_y, porch_depth - 0.15), Vector3(left_rail_w, 0.08, 0.06), post_mat)
		add_mesh_box(porch, "PorchRailRight", Vector3(half_pw - 0.2 - right_rail_w * 0.5, rail_y, porch_depth - 0.15), Vector3(right_rail_w, 0.08, 0.06), post_mat)
	
	# Porch shed roof
	var porch_roof_y := deck_h + post_h
	var p_roof := add_mesh_box(porch, "PorchRoof", Vector3(0, porch_roof_y, porch_center_z), Vector3(porch_w + 0.3, 0.08, porch_depth + 0.3), roof_mat)
	p_roof.rotation.x = 0.18
	
	visuals_root.add_child(porch)

func _build_facade_elements(house_front_z: float) -> void:
	var wood_door_mat := UrbanMaterials.wood_door_brown()
	var trim_mat := UrbanMaterials.trim_stone()
	var glass_mat := UrbanMaterials.glass_window()
	var dark_mat := UrbanMaterials.window_interior_dark()
	
	var door_w := 0.95
	var door_h := 2.10
	var door_y := 0.35 + door_h * 0.5
	
	# Centered front entry door
	add_mesh_box(visuals_root, "FrontDoorFrame", Vector3(0, door_y, house_front_z + 0.02), Vector3(door_w + 0.18, door_h + 0.18, 0.08), trim_mat)
	add_mesh_box(visuals_root, "FrontDoor", Vector3(0, door_y, house_front_z + 0.04), Vector3(door_w, door_h, 0.05), wood_door_mat)
	add_mesh_box(visuals_root, "FrontDoorknob", Vector3(door_w * 0.35, door_y - 0.1, house_front_z + 0.07), Vector3(0.05, 0.05, 0.05), UrbanMaterials.metal_brass())
	
	# Flanking domestic double-hung windows
	var win_w := 1.05
	var win_h := 1.45
	var win_y := 0.35 + 1.25
	var half_w := building_size.x * 0.5
	var win_span := (half_w - door_w * 0.5) * 0.55
	
	for side in [-win_span - door_w * 0.5, win_span + door_w * 0.5]:
		add_mesh_box(visuals_root, "WinSill", Vector3(side, win_y - win_h * 0.5 - 0.05, house_front_z + 0.08), Vector3(win_w + 0.18, 0.10, 0.18), trim_mat)
		add_mesh_box(visuals_root, "WinFrame", Vector3(side, win_y, house_front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
		var glass := add_mesh_box(visuals_root, "WinGlass", Vector3(side, win_y, house_front_z + 0.04), Vector3(win_w - 0.12, win_h - 0.12, 0.02), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Timber decorative shutters
		for shutter_side in [-win_w * 0.5 - 0.18, win_w * 0.5 + 0.18]:
			add_mesh_box(visuals_root, "Shutter", Vector3(side + shutter_side, win_y, house_front_z + 0.04), Vector3(0.32, win_h, 0.04), wood_door_mat)

func _build_side_windows(center_z: float, depth: float) -> void:
	var dark_mat := UrbanMaterials.window_interior_dark()
	var glass_mat := UrbanMaterials.glass_window()
	var trim_mat := UrbanMaterials.trim_stone()
	
	var half_w := building_size.x * 0.5
	var win_w := 0.95
	var win_h := 1.25
	var win_y := 1.7
	
	for side_x in [-half_w, half_w]:
		var rot := -PI * 0.5 if side_x < 0 else PI * 0.5
		var normal := -1.0 if side_x < 0 else 1.0
		for wz in [center_z - depth * 0.25, center_z + depth * 0.25]:
			add_mesh_box(visuals_root, "SideWinFrame", Vector3(side_x + normal * 0.02, win_y, wz), Vector3(0.08, win_h, win_w), dark_mat)
			var glass := add_mesh_box(visuals_root, "SideWinGlass", Vector3(side_x + normal * 0.04, win_y, wz), Vector3(0.02, win_h - 0.1, win_w - 0.1), glass_mat)
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
