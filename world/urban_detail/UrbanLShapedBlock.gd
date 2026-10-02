extends UrbanBuildingBase
class_name UrbanLShapedBlock

## Reconstructs L-shaped architectural blocks (e.g. FoundryLofts / Union Lofts & Works).
## Strictly preserves physical volume contract: North Main Wing and East Wing have collision,
## while the Southwest Courtyard remains fully open and accessible.
## Features Crittall loft windows, courtyard loading dock doors, and rooftop water tower.

const L_MAIN_DEPTH := 0.55
const L_WING_WIDTH := 0.50

func build() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	
	var main_d := building_size.y * L_MAIN_DEPTH
	var wing_d := building_size.y * (1.0 - L_MAIN_DEPTH)
	var wing_w := building_size.x * L_WING_WIDTH
	
	var brick_mat := UrbanMaterials.brick_brown()
	var trim_mat := UrbanMaterials.trim_stone()
	
	# 1. Main Wing (North portion across full building width)
	# Center Z for main wing: starts at -half_d, extends +main_d
	var main_center_z: float = -half_d + main_d * 0.5
	add_solid_box(visuals_root, "MainWing", Vector3(0, height * 0.5, main_center_z), Vector3(building_size.x, height, main_d), brick_mat)
	
	# 2. East Wing (South-East wing extending forward)
	# Center X: half_w - wing_w * 0.5
	# Center Z: half_d - wing_d * 0.5
	var wing_center_x: float = half_w - wing_w * 0.5
	var wing_center_z: float = half_d - wing_d * 0.5
	add_solid_box(visuals_root, "EastWing", Vector3(wing_center_x, height * 0.5, wing_center_z), Vector3(wing_w, height, wing_d), brick_mat)
	
	# L-Shaped Roof Surfaces: Main Wing and East Wing only (courtyard remains open to the sky)
	add_mesh_box(visuals_root, "MainWingRoof", Vector3(0, height + 0.025, main_center_z), Vector3(building_size.x - 0.2, 0.05, main_d - 0.2), UrbanMaterials.roof_tar())
	add_mesh_box(visuals_root, "EastWingRoof", Vector3(wing_center_x, height + 0.025, wing_center_z), Vector3(wing_w - 0.2, 0.05, wing_d - 0.2), UrbanMaterials.roof_tar())
	
	# Cornice only on the street-facing front of East Wing
	var front_cornice_z: float = half_d + 0.15
	add_mesh_box(visuals_root, "EastWingCornice", Vector3(wing_center_x, height - 0.05, front_cornice_z), Vector3(wing_w + 0.2, 0.38, 0.30), trim_mat)
	
	# L-shaped roof parapets around outer perimeter
	var py: float = height + 0.22
	var p_thick: float = 0.22
	var p_h: float = 0.44
	# North rim
	add_mesh_box(visuals_root, "ParapetNorth", Vector3(0, py, -half_d + p_thick * 0.5), Vector3(building_size.x, p_h, p_thick), trim_mat)
	# East rim
	add_mesh_box(visuals_root, "ParapetEast", Vector3(half_w - p_thick * 0.5, py, 0), Vector3(p_thick, p_h, building_size.y), trim_mat)
	# Main wing west rim
	add_mesh_box(visuals_root, "ParapetWestMain", Vector3(-half_w + p_thick * 0.5, py, main_center_z), Vector3(p_thick, p_h, main_d), trim_mat)
	# Courtyard inner walls parapets
	add_mesh_box(visuals_root, "ParapetCourtyardNorth", Vector3(-half_w * 0.5, py, -half_d + main_d - p_thick * 0.5), Vector3(building_size.x - wing_w, p_h, p_thick), trim_mat)
	add_mesh_box(visuals_root, "ParapetCourtyardEast", Vector3(wing_center_x - wing_w * 0.5 + p_thick * 0.5, py, wing_center_z), Vector3(p_thick, p_h, wing_d), trim_mat)
	# East wing south rim
	add_mesh_box(visuals_root, "ParapetSouth", Vector3(wing_center_x, py, half_d - p_thick * 0.5), Vector3(wing_w, p_h, p_thick), trim_mat)
	
	# 3. Courtyard (South-West corner is OPEN - NO COLLISION, NO ROOF)
	# Courtyard bounds: X from -half_w to (half_w - wing_w), Z from (-half_d + main_d) to half_d.
	
	# Courtyard loading dock doors on the recessed west-facing wall of the East Wing
	_build_courtyard_loading_dock(wing_center_x - wing_w * 0.5, wing_center_z, wing_d)
	
	# Crittall loft windows on Main Wing north/south and East Wing east/south facades
	_build_loft_windows(main_center_z, main_d, wing_center_x, wing_center_z, wing_w, wing_d)
	
	# Rooftop water tower on Main Wing
	add_water_tower(visuals_root, Vector3(-half_w * 0.45, height + 0.05, main_center_z))
	
	# Chimney on party wall
	add_chimney(visuals_root, Vector3(-half_w * 0.1, height + 0.05, main_center_z - main_d * 0.3), 1.5, 2)
	
	# Facade proper name signage on the street front
	if not proper_name.is_empty():
		var sign_node := UrbanSignage.create_sign_3d(proper_name, Vector2(minf(wing_w * 0.8, 3.8), 0.65), 0.08, trim_mat)
		if sign_node != null:
			sign_node.position = Vector3(wing_center_x, 3.8, half_d + 0.08)
			visuals_root.add_child(sign_node)

func _build_courtyard_loading_dock(dock_wall_x: float, dock_center_z: float, _dock_d: float) -> void:
	var dark_mat := UrbanMaterials.metal_dark()
	var wood_mat := UrbanMaterials.wood_door_green()
	
	var dock_w := 2.6
	var dock_h := 2.5
	var dock_y := dock_h * 0.5
	
	# Double loading doors on the courtyard wall
	add_mesh_box(visuals_root, "CourtyardDoorFrame", Vector3(dock_wall_x - 0.02, dock_y, dock_center_z), Vector3(0.08, dock_h + 0.15, dock_w + 0.2), dark_mat)
	add_mesh_box(visuals_root, "CourtyardDoorLeft", Vector3(dock_wall_x - 0.04, dock_y, dock_center_z - dock_w * 0.25), Vector3(0.05, dock_h, dock_w * 0.48), wood_mat)
	add_mesh_box(visuals_root, "CourtyardDoorRight", Vector3(dock_wall_x - 0.04, dock_y, dock_center_z + dock_w * 0.25), Vector3(0.05, dock_h, dock_w * 0.48), wood_mat)
	
	# Overhead loading hoist beam projecting into courtyard
	add_mesh_box(visuals_root, "HoistBeam", Vector3(dock_wall_x - 1.1, dock_h + 0.5, dock_center_z), Vector3(2.2, 0.15, 0.15), dark_mat)

func _build_loft_windows(_main_center_z: float, _main_d: float, wing_center_x: float, _wing_center_z: float, _wing_w: float, _wing_d: float) -> void:
	var dark_mat := UrbanMaterials.metal_dark()
	var glass_mat := UrbanMaterials.glass_window()
	var trim_mat := UrbanMaterials.trim_stone()
	
	var win_w := 1.8
	var win_h := 1.6
	
	# Windows on East Wing street-facing south facade
	var half_d := building_size.y * 0.5
	for floor_idx: int in 2:
		var wy: float = 1.8 + float(floor_idx) * 2.6
		var wx: float = wing_center_x
		
		add_mesh_box(visuals_root, "LoftSill", Vector3(wx, wy - win_h * 0.5 - 0.06, half_d + 0.08), Vector3(win_w + 0.2, 0.12, 0.20), trim_mat)
		add_mesh_box(visuals_root, "LoftFrame", Vector3(wx, wy, half_d + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
		var glass := add_mesh_box(visuals_root, "LoftGlass", Vector3(wx, wy, half_d + 0.04), Vector3(win_w - 0.1, win_h - 0.1, 0.02), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# 3x3 Crittall grid
		for i in range(1, 3):
			var gx: float = wx - win_w * 0.5 + float(i) * (win_w / 3.0)
			add_mesh_box(visuals_root, "LoftMullionV", Vector3(gx, wy, half_d + 0.05), Vector3(0.04, win_h - 0.1, 0.03), dark_mat)
			var gy: float = wy - win_h * 0.5 + float(i) * (win_h / 3.0)
			add_mesh_box(visuals_root, "LoftMullionH", Vector3(wx, gy, half_d + 0.05), Vector3(win_w - 0.1, 0.04, 0.03), dark_mat)
