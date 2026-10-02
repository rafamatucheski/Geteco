extends UrbanBuildingBase
class_name UrbanBrownstoneBuilding

## Reconstructs authentic brownstone, rowhouse, and terrace architecture in native 3D geometry.
## Features raised stone stoops, multi-pane sash windows with lintels, dentil cornices,
## rooftop water towers, and chimney stacks with clay flue pots.

func build() -> void:
	if building_kind == "rowhouse_terrace":
		_build_v1_terrace()
		return
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	# Determine unit count based on width: single unit or twin terrace
	var unit_count := 1
	var unit_w := building_size.x / float(unit_count)
	
	# Productive Foundry terraces have four authored unit identities. Other
	# brownstones use their exact seeded V1 palette instead of a generic red row.
	var wall_colors: Array[Color]
	var roof_colors: Array[Color]
	var door_mats: Array[StandardMaterial3D]
	wall_colors=[base_color,base_color.darkened(.12)]
	var source_roof: Color=v1_palette.roof
	roof_colors=[source_roof,source_roof.lightened(.04)]
	door_mats=[UrbanMaterials.wood_door_green(),UrbanMaterials.wood_door_burgundy()]
	var brick_mats: Array[StandardMaterial3D]=[]
	for color in wall_colors: brick_mats.append(wall_material(color,.88))
	
	# Main structural body
	add_solid_box(visuals_root, "BrownstoneBody", Vector3(0, height * 0.5, 0), Vector3(building_size.x, height, building_size.y), brick_mats[0])
	
	# Roof features
	add_roof_parapet(visuals_root, height, 0.45, 0.22, UrbanMaterials.trim_stone())
	for unit_index in unit_count:
		var roof_center_x: float = -half_w + unit_w * 0.5 + float(unit_index) * unit_w
		add_mesh_box(visuals_root,"V1UnitRoof_%d"%unit_index,Vector3(roof_center_x,height+.04,0),Vector3(unit_w-.08,.08,building_size.y-.38),UrbanMaterials.material_for_color(roof_colors[unit_index%roof_colors.size()],.92))
	add_cornice(visuals_root, height - 0.05, 0.40, 0.45, true, UrbanMaterials.trim_stone())
	
	# Build each bay / terrace unit
	for u in unit_count:
		var u_center_x: float = -half_w + unit_w * 0.5 + float(u) * unit_w
		var u_mat: StandardMaterial3D = brick_mats[u % brick_mats.size()]
		var u_door_mat: StandardMaterial3D = door_mats[u % door_mats.size()]
		
		# Individual facade face veneer to give subtle unit distinction
		if unit_count > 1:
			add_mesh_box(visuals_root, "UnitFacade_%d" % u, Vector3(u_center_x, height * 0.5, front_z + 0.01), Vector3(unit_w - 0.04, height - 0.5, 0.04), u_mat)
		
		# Raised entrance Stoop
		_build_stoop(Vector3(u_center_x - unit_w * 0.22, 0, front_z), u_door_mat, u)
		
		# Windows on ground floor and upper floor(s)
		_build_unit_windows(u_center_x, unit_w, front_z, -1.0, 4, "u%d" % u)
		
		# Metade dos brownstones ganha uma bay window saliente para
		# quebrar a silhueta de caixa lisa (varia por variant_seed, nao
		# por unidade, para nao empilhar saliencia em vitrines vizinhas).
		if (variant_seed + u) % 2 == 0:
			_build_bay_window(Vector3(u_center_x + unit_w * 0.22, 0, front_z), u_mat)
	
	# Rooftop water tower on party line
	add_water_tower(visuals_root, Vector3(half_w * 0.25, height + 0.05, -half_d * 0.25))
	
	# Chimneys on party walls
	# Facade proper name signage if available
	if not proper_name.is_empty():
		var sign_node := UrbanSignage.create_sign_3d(proper_name, Vector2(minf(unit_w * 0.7, 3.2), 0.55), 0.06, UrbanMaterials.trim_stone())
		if sign_node != null:
			sign_node.position = Vector3(0, height - 0.75, front_z + 0.08)
			visuals_root.add_child(sign_node)

func _build_v1_terrace() -> void:
	# HarborBuilding._draw_rowhouse_terrace publishes four distinct units. The
	# 2D facade-band heights are mapped proportionally around the established
	# 6.8 m V2 datum so their relative skyline survives the 3D conversion.
	var east := building_id.ends_with("East") or "East" in building_id
	var profiles := [
		{"height":6.40,"wall":Color("7c463b"),"roof":Color("343840"),"door":UrbanMaterials.wood_door_green(),"transom":"fanlight","prop":"flower_pot","panes":2,"flues":2,"dormer":false},
		{"height":6.85,"wall":Color("685447"),"roof":Color("38423f"),"door":UrbanMaterials.wood_door_burgundy(),"transom":"square","prop":"stone_rail","panes":6,"flues":1,"dormer":false},
	] if not east else [
		{"height":7.05,"wall":Color("8e7a65"),"roof":Color("3a3e46"),"door":UrbanMaterials.wood_door_navy(),"transom":"fanlight","prop":"bicycle","panes":1,"flues":2,"dormer":false},
		{"height":6.50,"wall":Color("78614e"),"roof":Color("404642"),"door":UrbanMaterials.wood_door_brown(),"transom":"arched","prop":"milk_crate","panes":4,"flues":1,"dormer":true},
	]
	var half_w := building_size.x*.5
	var half_d := building_size.y*.5
	var unit_w := building_size.x*.5
	for unit_index in 2:
		var profile: Dictionary = profiles[unit_index] as Dictionary
		var unit_height := float(profile.height)
		var center_x := -half_w+unit_w*.5+float(unit_index)*unit_w
		var wall_mat := UrbanMaterials.material_for_color(profile.wall,.88)
		add_solid_box(visuals_root,"TerraceUnitBody_%d"%unit_index,Vector3(center_x,unit_height*.5,0),Vector3(unit_w-.08,unit_height,building_size.y),wall_mat)
		add_mesh_box(visuals_root,"TerraceUnitRoof_%d"%unit_index,Vector3(center_x,unit_height+.04,0),Vector3(unit_w-.18,.08,building_size.y-.38),UrbanMaterials.material_for_color(profile.roof,.92))
		add_mesh_box(visuals_root,"TerraceCornice_%d"%unit_index,Vector3(center_x,unit_height-.08,half_d+.16),Vector3(unit_w+.02,.34,.32),UrbanMaterials.trim_stone())
		for dentil_index in maxi(3,int(unit_w/.55)):
			var dentil_x := center_x-unit_w*.42+float(dentil_index)*(unit_w*.84/float(maxi(1,maxi(3,int(unit_w/.55))-1)))
			add_mesh_box(visuals_root,"TerraceDentil_%d_%d"%[unit_index,dentil_index],Vector3(dentil_x,unit_height-.27,half_d+.30),Vector3(.16,.14,.16),UrbanMaterials.trim_dark())
		_build_stoop(Vector3(center_x-unit_w*.22,0,half_d),profile.door,unit_index,String(profile.transom),String(profile.prop))
		_build_unit_windows(center_x,unit_w,half_d,unit_height,int(profile.panes),"terrace%d"%unit_index)
		add_chimney(visuals_root,Vector3(center_x+unit_w*.30,unit_height+.05,-half_d*.45),1.35,int(profile.flues))
		if bool(profile.dormer): _build_roof_dormer(center_x,unit_height,half_d)
	if not proper_name.is_empty():
		var sign_node := UrbanSignage.create_sign_3d(proper_name,Vector2(minf(building_size.x*.55,4.4),.52),.06,UrbanMaterials.trim_stone())
		if sign_node != null:
			sign_node.position=Vector3(0,5.55,half_d+.10)
			visuals_root.add_child(sign_node)

func _build_roof_dormer(center_x: float, unit_height: float, half_d: float) -> void:
	var dormer := Node3D.new()
	dormer.name="V1Dormer"
	dormer.position=Vector3(center_x-unit_w_for_dormer()*.18,unit_height+.05,half_d*.15)
	add_mesh_box(dormer,"DormerBody",Vector3(0,.48,0),Vector3(1.25,.96,1.05),UrbanMaterials.material_for_color(Color("3f4a47"),.9))
	add_mesh_box(dormer,"DormerWindow",Vector3(0,.48,.55),Vector3(.78,.56,.06),UrbanMaterials.glass_window())
	var cap:=add_mesh_box(dormer,"DormerCap",Vector3(0,1.03,0),Vector3(1.48,.16,1.25),UrbanMaterials.material_for_color(Color("2b3230"),.94))
	cap.rotation.z=.10
	visuals_root.add_child(dormer)

func unit_w_for_dormer() -> float:
	return building_size.x*.5

func _build_stoop(at: Vector3, door_mat: StandardMaterial3D, unit_index: int, transom_kind := "fanlight", prop_kind := "") -> void:
	var stoop := Node3D.new()
	stoop.name = "Stoop_%d" % unit_index
	stoop.position = at
	
	var stoop_mat := UrbanMaterials.stoop_stone()
	var rail_mat := UrbanMaterials.metal_iron()
	var trim_mat := UrbanMaterials.trim_stone()
	
	var steps := 4
	var step_h := 0.22
	var step_run := 0.32
	var stoop_w := 1.5
	var landing_depth := 1.1
	var landing_h := float(steps) * step_h
	
	# Raised door landing
	add_mesh_box(stoop, "Landing", Vector3(0, landing_h * 0.5, landing_depth * 0.5), Vector3(stoop_w, landing_h, landing_depth), stoop_mat)
	
	# Steps descending toward street (+Z)
	for s in steps:
		var sy := float(s) * step_h + step_h * 0.5
		var sz := landing_depth + float(steps - 1 - s) * step_run + step_run * 0.5
		add_mesh_box(stoop, "Step_%d" % s, Vector3(0, sy, sz), Vector3(stoop_w - 0.1, step_h, step_run), stoop_mat)
	
	# Flanking stone side walls / cheek walls
	var total_d := landing_depth + float(steps) * step_run
	for side in [-stoop_w * 0.5, stoop_w * 0.5]:
		add_mesh_box(stoop, "CheekWall", Vector3(side, (landing_h + 0.35) * 0.5, total_d * 0.5), Vector3(0.18, landing_h + 0.35, total_d), trim_mat)
		# Wrought iron handrail on cheek wall
		add_mesh_box(stoop, "Handrail", Vector3(side, landing_h + 0.75, total_d * 0.5), Vector3(0.06, 0.06, total_d), rail_mat)
	
	# Recessed Entry Door on facade
	var door_w := 1.05
	var door_h := 2.25
	var door_y := landing_h + door_h * 0.5
	
	# Stone door surround / architrave
	add_mesh_box(stoop, "DoorArchitrave", Vector3(0, door_y + 0.1, 0.02), Vector3(door_w + 0.28, door_h + 0.45, 0.12), trim_mat)
	# Entry door panel
	add_mesh_box(stoop, "DoorPanel", Vector3(0, door_y, 0.04), Vector3(door_w, door_h, 0.06), door_mat)
	# Source-specific square/arched/fanlight transom.
	if transom_kind in ["fanlight","arched"]:
		var transom := MeshInstance3D.new()
		transom.name="FanlightTransom" if transom_kind=="fanlight" else "ArchedTransom"
		var transom_mesh:=CylinderMesh.new()
		transom_mesh.top_radius=door_w*.38
		transom_mesh.bottom_radius=door_w*.38
		transom_mesh.height=.05
		transom_mesh.radial_segments=18
		transom.mesh=transom_mesh
		transom.rotation_degrees.x=90
		transom.position=Vector3(0,landing_h+door_h+.12,.08)
		transom.material_override=UrbanMaterials.glass_window()
		stoop.add_child(transom)
	else:
		add_mesh_box(stoop,"SquareTransom",Vector3(0,landing_h+door_h+.18,.06),Vector3(door_w*.85,.32,.04),UrbanMaterials.glass_window())
	# Brass doorknob
	add_mesh_box(stoop, "Doorknob", Vector3(door_w * 0.35, landing_h + 0.95, 0.08), Vector3(0.06, 0.06, 0.06), UrbanMaterials.metal_brass())
	
	# Stoop occupation prop (flower pot or bicycle)
	if prop_kind.is_empty(): prop_kind="flower_pot" if unit_index%2==0 else "bicycle"
	if prop_kind == "flower_pot":
		# Potted plant on landing
		add_mesh_box(stoop, "FlowerPot", Vector3(-stoop_w * 0.36, landing_h + 0.18, 0.35), Vector3(0.28, 0.36, 0.28), UrbanMaterials.terracotta_flue())
		add_mesh_box(stoop, "Foliage", Vector3(-stoop_w * 0.36, landing_h + 0.48, 0.35), Vector3(0.38, 0.32, 0.38), UrbanMaterials.get_mat("plant_green", Color("3d6840"), 0.8))
	elif prop_kind == "bicycle":
		# Commuter bicycle parked along railing
		_build_bicycle(stoop, Vector3(stoop_w * 0.5 + 0.2, landing_h * 0.35, total_d * 0.6))
	elif prop_kind == "stone_rail":
		for side in [-.48,.48]: add_mesh_box(stoop,"StoneRailPost",Vector3(side,landing_h+.58,.48),Vector3(.20,1.16,.20),trim_mat)
		add_mesh_box(stoop,"StoneRailCap",Vector3(0,landing_h+1.14,.48),Vector3(1.18,.14,.26),trim_mat)
	elif prop_kind == "milk_crate":
		add_mesh_box(stoop,"MilkCrate",Vector3(stoop_w*.62,landing_h+.22,.38),Vector3(.52,.44,.48),UrbanMaterials.get_mat("milk_crate",Color("baa788"),.88))
		for slot in [-.15,0.0,.15]: add_mesh_box(stoop,"MilkCrateSlot",Vector3(stoop_w*.62+slot,landing_h+.22,.625),Vector3(.05,.26,.02),UrbanMaterials.trim_dark())
	
	visuals_root.add_child(stoop)

func _build_bicycle(parent: Node3D, at: Vector3) -> void:
	var bike := Node3D.new()
	bike.name = "Bicycle"
	bike.position = at
	var mat := UrbanMaterials.metal_dark()
	var frame_mat := UrbanMaterials.get_mat("bike_blue", Color("3e5771"), 0.5, 0.4)
	
	# Wheels (front and rear)
	add_mesh_box(bike, "RearWheel", Vector3(0, 0.32, -0.45), Vector3(0.06, 0.64, 0.64), mat)
	add_mesh_box(bike, "FrontWheel", Vector3(0, 0.32, 0.45), Vector3(0.06, 0.64, 0.64), mat)
	# Frame tubes
	add_mesh_box(bike, "FrameTop", Vector3(0, 0.58, 0), Vector3(0.04, 0.04, 0.65), frame_mat)
	add_mesh_box(bike, "SeatPost", Vector3(0, 0.62, -0.15), Vector3(0.18, 0.08, 0.22), mat)
	add_mesh_box(bike, "Handlebars", Vector3(0, 0.78, 0.40), Vector3(0.42, 0.04, 0.06), mat)
	
	parent.add_child(bike)

## Bay window saliente de dois andares, apoiada em mão-francesa. Quebra a
## silhueta de caixa lisa do brownstone sem alterar o volume principal
## (a caixa continua servindo de base de colisão).
func _build_bay_window(at: Vector3, wall_mat: StandardMaterial3D) -> void:
	var bay := Node3D.new()
	bay.name = "BayWindow"
	bay.position = at

	var bay_w := 1.35
	var bay_h := 4.4
	var bay_depth := 0.55
	var glass_mat := UrbanMaterials.glass_window()
	var trim_mat := UrbanMaterials.trim_stone()

	add_mesh_box(bay, "BayBody", Vector3(0, bay_h * 0.5 + 0.9, bay_depth * 0.5), Vector3(bay_w, bay_h, bay_depth), wall_mat)
	add_mesh_box(bay, "BayGlassFront", Vector3(0, bay_h * 0.5 + 0.9, bay_depth + 0.02), Vector3(bay_w - 0.18, bay_h - 0.5, 0.03), glass_mat)
	add_mesh_box(bay, "BaySillBracket", Vector3(0, 0.85, bay_depth * 0.5), Vector3(bay_w + 0.1, 0.10, bay_depth + 0.05), trim_mat)
	add_mesh_box(bay, "BayCap", Vector3(0, bay_h + 0.92, bay_depth * 0.5), Vector3(bay_w + 0.14, 0.10, bay_depth + 0.1), trim_mat)

	visuals_root.add_child(bay)

func _build_unit_windows(unit_center_x: float, unit_w: float, front_z: float, unit_height := -1.0, pane_count := 4, key_prefix := "") -> void:
	var trim_mat := UrbanMaterials.trim_stone()
	var dark_mat := UrbanMaterials.window_interior_dark()

	var win_w := 1.15
	var win_h := 1.65
	var win_x_offset := unit_w * 0.26

	# Upper floors window grid
	var effective_height := height if unit_height<0.0 else unit_height
	var floors := 2 if effective_height >= 6.0 else 1
	for f in floors:
		var floor_y := 2.2 + float(f) * 2.5

		# Pair of windows per floor
		for side_index in 2:
			var side: float = win_x_offset if side_index == 1 else -win_x_offset
			var wx: float = unit_center_x + side
			var wy: float = floor_y + win_h * 0.5
			var glass_mat := window_glass_material("%s_f%d_s%d" % [key_prefix, f, side_index])

			# Projecting stone sill
			add_mesh_box(visuals_root, "WindowSill", Vector3(wx, floor_y - 0.08, front_z + 0.12), Vector3(win_w + 0.24, 0.14, 0.26), trim_mat)
			# Heavy stone lintel
			add_mesh_box(visuals_root, "WindowLintel", Vector3(wx, floor_y + win_h + 0.10, front_z + 0.08), Vector3(win_w + 0.28, 0.20, 0.16), trim_mat)

			# Recessed window frame
			add_mesh_box(visuals_root, "WindowFrame", Vector3(wx, wy, front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
			# Glass pane
			var glass := add_mesh_box(visuals_root, "WindowGlass", Vector3(wx, wy, front_z + 0.04), Vector3(win_w - 0.14, win_h - 0.14, 0.02), glass_mat)
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
			# Preserve the source unit's distinct sash division.
			if pane_count in [2,4,6]: add_mesh_box(visuals_root,"MullionH",Vector3(wx,wy,front_z+.05),Vector3(win_w-.14,.05,.03),dark_mat)
			if pane_count in [4,6]: add_mesh_box(visuals_root,"MullionV",Vector3(wx,wy,front_z+.05),Vector3(.05,win_h-.14,.03),dark_mat)
			if pane_count==6:
				for offset in [-win_w*.22,win_w*.22]: add_mesh_box(visuals_root,"MullionV",Vector3(wx+offset,wy,front_z+.055),Vector3(.04,win_h-.14,.03),dark_mat)
