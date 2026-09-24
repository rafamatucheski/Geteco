extends UrbanBuildingBase
class_name UrbanIndustrialBuilding

## Reconstructs warehouses, freight depots, and artisan workshops in native 3D geometry.
## Features structural brick piers, double timber carriage doors with iron strap hinges,
## roll-up loading bays, sawtooth monitor roofs with skylights, and loading dock curbs.

func build() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var is_artisan := building_kind == "artisan_workshop"
	var wall_mat := UrbanMaterials.material_for_color(base_color,0.90 if is_artisan else 0.88)
	var trim_mat := UrbanMaterials.trim_stone()
	
	# Main structural body
	add_solid_box(visuals_root, "IndustrialBody", Vector3(0, height * 0.5, 0), Vector3(building_size.x, height, building_size.y), wall_mat)
	
	# Parapet rim and roof gravel
	add_roof_parapet(visuals_root, height, 0.45, 0.25, trim_mat)
	add_mesh_box(visuals_root,"V1RoofSurface",Vector3(0,height+.03,0),Vector3(building_size.x-.5,.06,building_size.y-.5),UrbanMaterials.material_for_color(v1_palette.roof,.92))
	
	# Only the custom artisan source owns a sawtooth monitor. Productive generic
	# warehouses use repeated flat roof bays/skylights.
	if is_artisan: _build_sawtooth_monitors(height)
	else: _build_warehouse_roof_bays(height)
	
	# Facade piers and openings
	if is_artisan:
		_build_artisan_facade(front_z)
	else:
		_build_warehouse_bays(front_z)
	
	# Facade proper name sign
	if not proper_name.is_empty():
		var sign_w := minf(building_size.x * 0.5, 4.5)
		var sign := UrbanSignage.create_sign_3d(proper_name, Vector2(sign_w, 0.65), 0.08, UrbanMaterials.trim_dark())
		if sign != null:
			sign.position = Vector3(0, height - 0.75, front_z + 0.12)
			visuals_root.add_child(sign)

func _build_artisan_facade(front_z: float) -> void:
	var half_w := building_size.x * 0.5
	var pier_mat := UrbanMaterials.brick_dark()
	var trim_mat := UrbanMaterials.trim_stone()
	var iron_mat := UrbanMaterials.metal_iron()
	var wood_mat := UrbanMaterials.wood_door_brown()
	var glass_mat := UrbanMaterials.glass_window()
	var dark_mat := UrbanMaterials.window_interior_dark()
	
	# Structural masonry piers (left, center, right)
	for px in [-half_w + 0.4, 0.0, half_w - 0.4]:
		add_mesh_box(visuals_root, "MasonryPier", Vector3(px, height * 0.5, front_z + 0.08), Vector3(0.80, height + 0.2, 0.20), pier_mat)
	
	# Stone lintel beam band across first story
	add_mesh_box(visuals_root, "StoreyBand", Vector3(0, 3.2, front_z + 0.06), Vector3(building_size.x, 0.28, 0.14), trim_mat)
	
	# Left Bay: Double timber carriage doors with iron strap hinges
	var door_center_x := -half_w * 0.5
	var door_w := 2.6
	var door_h := 2.8
	var door_y := door_h * 0.5
	
	add_mesh_box(visuals_root, "DoorFrame", Vector3(door_center_x, door_y, front_z + 0.02), Vector3(door_w + 0.2, door_h + 0.15, 0.10), pier_mat)
	# Left and right wooden door leaves
	add_mesh_box(visuals_root, "DoorLeafLeft", Vector3(door_center_x - door_w * 0.25 - 0.01, door_y, front_z + 0.04), Vector3(door_w * 0.48, door_h, 0.06), wood_mat)
	add_mesh_box(visuals_root, "DoorLeafRight", Vector3(door_center_x + door_w * 0.25 + 0.01, door_y, front_z + 0.04), Vector3(door_w * 0.48, door_h, 0.06), wood_mat)
	
	# Iron strap hinges
	for hy: float in [door_h * 0.25, door_h * 0.75]:
		for leaf_side: float in [-1.0, 1.0]:
			var hx: float = door_center_x + leaf_side * door_w * 0.25
			add_mesh_box(visuals_root, "Hinge", Vector3(hx, hy, front_z + 0.08), Vector3(door_w * 0.42, 0.07, 0.02), iron_mat)
			add_mesh_box(visuals_root, "HingePin", Vector3(door_center_x + leaf_side * (door_w * 0.5 - 0.04), hy, front_z + 0.09), Vector3(0.06, 0.10, 0.04), iron_mat)
	
	# Ring pull handles
	for side in [-0.15, 0.15]:
		add_mesh_box(visuals_root, "DoorRing", Vector3(door_center_x + side, 1.15, front_z + 0.09), Vector3(0.10, 0.12, 0.03), UrbanMaterials.metal_brass())
	
	# Right Bay: Craft display window with steel Crittall multi-pane grid
	var win_center_x := half_w * 0.5
	var win_w := 2.6
	var win_h := 2.0
	var win_y := 1.7
	
	add_mesh_box(visuals_root, "CraftWinFrame", Vector3(win_center_x, win_y, front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
	var win_glass := add_mesh_box(visuals_root, "CraftWinGlass", Vector3(win_center_x, win_y, front_z + 0.04), Vector3(win_w - 0.1, win_h - 0.1, 0.02), glass_mat)
	win_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 3x2 iron mullion grid
	for i in range(1, 3):
		var mx := win_center_x - win_w * 0.5 + float(i) * (win_w / 3.0)
		add_mesh_box(visuals_root, "MullionV_%d" % i, Vector3(mx, win_y, front_z + 0.05), Vector3(0.04, win_h - 0.1, 0.03), iron_mat)
	add_mesh_box(visuals_root, "MullionH", Vector3(win_center_x, win_y, front_z + 0.05), Vector3(win_w - 0.1, 0.04, 0.03), iron_mat)
	
	# Clerestory transom windows under the roofline
	for cx in [door_center_x, win_center_x]:
		var cl_w := 2.2
		var cl_h := 0.75
		var cl_y := height - 1.1
		add_mesh_box(visuals_root, "ClerestoryFrame", Vector3(cx, cl_y, front_z + 0.02), Vector3(cl_w, cl_h, 0.06), dark_mat)
		var cl_glass := add_mesh_box(visuals_root, "ClerestoryGlass", Vector3(cx, cl_y, front_z + 0.04), Vector3(cl_w - 0.08, cl_h - 0.08, 0.02), glass_mat)
		cl_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_warehouse_bays(front_z: float) -> void:
	var dark_mat := UrbanMaterials.metal_dark()
	var shutter_mat := UrbanMaterials.metal_corrugated()
	var trim_mat := UrbanMaterials.trim_stone()
	
	var bay_count := maxi(2, int(building_size.x / 4.5))
	var bay_step := building_size.x / float(bay_count)
	var bay_w := bay_step * 0.75
	var bay_h := 3.4
	
	# Concrete loading dock platform
	var dock_h := 0.40
	var dock_depth := 1.2
	add_mesh_box(visuals_root, "LoadingDockPlatform", Vector3(0, dock_h * 0.5, front_z + dock_depth * 0.5), Vector3(building_size.x, dock_h, dock_depth), UrbanMaterials.wall_concrete())
	# Dock edge rubber bumper curb
	add_mesh_box(visuals_root, "DockBumper", Vector3(0, dock_h * 0.5, front_z + dock_depth + 0.04), Vector3(building_size.x, dock_h * 0.6, 0.08), dark_mat)
	
	for b in bay_count:
		var bx: float = -building_size.x * 0.5 + bay_step * 0.5 + float(b) * bay_step
		var by: float = dock_h + bay_h * 0.5
		
		# Heavy steel bay frame
		add_mesh_box(visuals_root, "BayFrame", Vector3(bx, by, front_z + 0.02), Vector3(bay_w + 0.3, bay_h + 0.25, 0.12), dark_mat)
		
		# Roll-up corrugated metal shutter door
		add_mesh_box(visuals_root, "ShutterDoor", Vector3(bx, by, front_z + 0.04), Vector3(bay_w, bay_h, 0.06), shutter_mat)
		
		# Horizontal slats detail on shutter
		for s in range(1, int(bay_h / 0.45)):
			var sy := dock_h + float(s) * 0.45
			add_mesh_box(visuals_root, "ShutterSlat", Vector3(bx, sy, front_z + 0.07), Vector3(bay_w - 0.1, 0.03, 0.02), dark_mat)

func _build_warehouse_roof_bays(roof_y: float) -> void:
	# ProceduralBuilding._draw_roof_surface divides the inner roof every 42 V1
	# pixels and places one flat skylight in each bay. World data is converted at
	# the same 16 px/m scale used by NativeRegion.
	var source_bay_width_m: float = 42.0 / 16.0
	var bay_count: int = maxi(2, int(building_size.x / source_bay_width_m))
	var inner_width: float = maxf(1.0, building_size.x - 1.0)
	var bay_width: float = inner_width / float(bay_count)
	var glass_mat: StandardMaterial3D = UrbanMaterials.material_for_color(Color("50646a"), 0.46)
	var edge_mat: StandardMaterial3D = UrbanMaterials.material_for_color(Color("252e32"), 0.88)
	for bay_index in bay_count:
		var bay_left: float = -inner_width * 0.5 + float(bay_index) * bay_width
		var skylight_width: float = maxf(10.0 / 16.0, bay_width - 14.0 / 16.0)
		var skylight_x: float = bay_left + 7.0 / 16.0 + skylight_width * 0.5
		add_mesh_box(visuals_root, "RoofBaySeam", Vector3(bay_left, roof_y + 0.075, 0.0), Vector3(0.08, 0.05, building_size.y - 1.0), edge_mat)
		add_mesh_box(visuals_root, "RoofSkylightEdge", Vector3(skylight_x, roof_y + 0.10, -building_size.y * 0.5 + 1.35), Vector3(skylight_width + 0.12, 0.10, 0.82), edge_mat)
		var glass: MeshInstance3D = add_mesh_box(visuals_root, "RoofSkylight", Vector3(skylight_x, roof_y + 0.16, -building_size.y * 0.5 + 1.35), Vector3(skylight_width, 0.04, 0.62), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_sawtooth_monitors(roof_y: float) -> void:
	var glass_mat := UrbanMaterials.glass_window()
	var roof_mat := UrbanMaterials.roof_tin()
	var dark_mat := UrbanMaterials.metal_dark()
	
	var monitor_count := maxi(2, int(building_size.y / 4.0))
	var monitor_step := (building_size.y - 1.8) / float(monitor_count)
	var monitor_w := building_size.x - 2.4
	
	for m in monitor_count:
		var mz := -building_size.y * 0.5 + 1.2 + monitor_step * 0.5 + float(m) * monitor_step
		var my := roof_y + 0.65
		
		# Angled roof back slope
		var back_slope := add_mesh_box(visuals_root, "SawtoothBack", Vector3(0, my, mz - 0.4), Vector3(monitor_w, 0.08, 1.2), roof_mat)
		back_slope.rotation.x = -0.45
		
		# Vertical north-facing clerestory glass
		var glass := add_mesh_box(visuals_root, "SawtoothGlass", Vector3(0, my + 0.3, mz + 0.2), Vector3(monitor_w - 0.2, 0.65, 0.04), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Triangular gable end caps
		for side in [-monitor_w * 0.5, monitor_w * 0.5]:
			add_mesh_box(visuals_root, "SawtoothGable", Vector3(side, my + 0.15, mz), Vector3(0.08, 0.75, 1.1), dark_mat)
