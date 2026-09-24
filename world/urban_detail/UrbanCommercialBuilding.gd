extends UrbanBuildingBase
class_name UrbanCommercialBuilding

## Reconstructs commercial office buildings, civic structures, and urban towers in native 3D.
## Features stepped roof penthouses, multi-story curtain window bands, entrance porticos,
## rooftop HVAC chillers, and communication antennas.

func build() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var wall_mat := wall_material(base_color, 0.82)
	var trim_mat := UrbanMaterials.trim_stone()
	
	# Main commercial structural body
	add_solid_box(visuals_root, "CommercialBody", Vector3(0, height * 0.5, 0), Vector3(building_size.x, height, building_size.y), wall_mat)
	
	# Roof parapet and gravel surface
	add_roof_parapet(visuals_root, height, 0.50, 0.28, trim_mat)
	add_mesh_box(visuals_root,"V1RoofSurface",Vector3(0,height+.03,0),Vector3(building_size.x-.55,.06,building_size.y-.55),UrbanMaterials.material_for_color(v1_palette.roof,.92))
	
	# Projecting stone water table / ground base course
	add_mesh_box(visuals_root, "PlinthCourse", Vector3(0, 0.45, front_z + 0.08), Vector3(building_size.x + 0.16, 0.90, 0.20), trim_mat)
	
	# Ground-floor commercial entrance portico
	_build_entrance_lobby(front_z)
	
	# Multi-story window grid
	_build_commercial_windows(front_z)
	
	# Setback rooftop penthouse volume (as authored in ProceduralBuilding:296)
	var penthouse_w := building_size.x * 0.42
	var penthouse_d := building_size.y * 0.35
	var penthouse_h := 2.2
	var penthouse_pos := Vector3(half_w * 0.35, height + penthouse_h * 0.5, -half_d * 0.25)
	add_solid_box(visuals_root, "Penthouse", penthouse_pos, Vector3(penthouse_w, penthouse_h, penthouse_d), wall_mat)
	add_mesh_box(visuals_root, "PenthouseCap", Vector3(penthouse_pos.x, height + penthouse_h + 0.06, penthouse_pos.z), Vector3(penthouse_w + 0.15, 0.12, penthouse_d + 0.15), trim_mat)
	
	# ProceduralBuilding._draw_roof_detail publishes only 1..3 seeded plant
	# units here; antennas and access bulkheads were not part of the V1 source.
	var unit_count: int = 1 + posmod(variant_seed, 3)
	for unit_index in unit_count:
		var unit_x: float = lerpf(-half_w * 0.48, half_w * 0.18, float(unit_index) / maxf(1.0, float(unit_count - 1)))
		add_hvac_chiller(visuals_root,Vector3(unit_x,height+.05,-half_d*.18),Vector3(1.5,.72,1.05))
	
	# Facade proper name architectural sign
	if not proper_name.is_empty():
		var sign_w := minf(building_size.x * 0.65, 5.5)
		var sign := UrbanSignage.create_sign_3d(proper_name, Vector2(sign_w, 0.75), 0.10, UrbanMaterials.trim_dark())
		if sign != null:
			sign.position = Vector3(0, 3.75, front_z + 0.12)
			visuals_root.add_child(sign)

func _build_entrance_lobby(front_z: float) -> void:
	var trim_mat := UrbanMaterials.trim_stone()
	var dark_mat := UrbanMaterials.metal_dark()
	var glass_mat := UrbanMaterials.glass_display()
	
	var lobby_w := minf(building_size.x * 0.5, 4.8)
	var lobby_h := 3.2
	
	# Stone entrance portico surround
	add_mesh_box(visuals_root, "PorticoSurround", Vector3(0, lobby_h * 0.5, front_z + 0.06), Vector3(lobby_w + 0.4, lobby_h + 0.3, 0.15), trim_mat)
	
	# Glazed lobby entrance (double doors + sidelights)
	var glass_panel := add_mesh_box(visuals_root, "LobbyGlass", Vector3(0, lobby_h * 0.5, front_z + 0.08), Vector3(lobby_w, lobby_h, 0.06), glass_mat)
	glass_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Door framing mullions
	add_mesh_box(visuals_root, "DoorMullionLeft", Vector3(-lobby_w * 0.25, lobby_h * 0.5, front_z + 0.10), Vector3(0.08, lobby_h, 0.08), dark_mat)
	add_mesh_box(visuals_root, "DoorMullionRight", Vector3(lobby_w * 0.25, lobby_h * 0.5, front_z + 0.10), Vector3(0.08, lobby_h, 0.08), dark_mat)
	add_mesh_box(visuals_root, "DoorTransomBar", Vector3(0, 2.35, front_z + 0.10), Vector3(lobby_w, 0.08, 0.08), dark_mat)
	
	# Brass pull handles
	for side in [-0.08, 0.08]:
		add_mesh_box(visuals_root, "Handle", Vector3(side, 1.15, front_z + 0.14), Vector3(0.04, 0.36, 0.05), UrbanMaterials.metal_brass())

func _build_commercial_windows(front_z: float) -> void:
	var dark_mat := UrbanMaterials.metal_dark()
	var spandrel_mat := UrbanMaterials.wall_slate()
	
	var floor_h := 2.2
	var floor_start_y := 4.4
	var available_h := height - floor_start_y
	var floors := maxi(1, int(available_h / floor_h))
	
	var margin_x := 1.2
	var usable_w := building_size.x - margin_x * 2.0
	var col_count := maxi(2, int(usable_w / 2.4))
	var col_step := usable_w / float(col_count)
	var win_w := col_step * 0.72
	var win_h := 1.35
	
	for f in floors:
		var fy := floor_start_y + float(f) * floor_h + win_h * 0.5
		
		# Continuous horizontal spandrel band under each window row
		add_mesh_box(visuals_root, "SpandrelBand_%d" % f, Vector3(0, fy - win_h * 0.5 - 0.25, front_z + 0.04), Vector3(building_size.x - 0.4, 0.50, 0.10), spandrel_mat)
		
		# Windows in the row
		for c in col_count:
			var wx: float = -usable_w * 0.5 + col_step * 0.5 + float(c) * col_step
			
			# Window frame and dark backing
			add_mesh_box(visuals_root, "WinFrame", Vector3(wx, fy, front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
			var glass_mat := window_glass_material("f%d_c%d" % [f, c], 0.22)
			var glass := add_mesh_box(visuals_root, "WinGlass", Vector3(wx, fy, front_z + 0.04), Vector3(win_w - 0.12, win_h - 0.12, 0.02), glass_mat)
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
			# Center mullion
			add_mesh_box(visuals_root, "Mullion", Vector3(wx, fy, front_z + 0.05), Vector3(0.04, win_h - 0.12, 0.03), dark_mat)

func _build_antenna(at: Vector3) -> void:
	var ant := Node3D.new()
	ant.name = "CommunicationsAntenna"
	ant.position = at
	var mat := UrbanMaterials.metal_steel()
	
	var ant_h := 3.6
	add_mesh_box(ant, "Mast", Vector3(0, ant_h * 0.5, 0), Vector3(0.08, ant_h, 0.08), mat)
	
	# Horizontal cross dipoles
	for offset_y in [ant_h * 0.6, ant_h * 0.8, ant_h * 0.95]:
		add_mesh_box(ant, "Dipole", Vector3(0, offset_y, 0), Vector3(1.1, 0.04, 0.04), mat)
	
	visuals_root.add_child(ant)
