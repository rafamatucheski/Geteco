extends UrbanBuildingBase
class_name UrbanShopfrontBuilding

## Reconstructs commercial retail storefronts, corner diners, groceries, and laundromats in native 3D.
## Features glazed storefront display windows, striped awnings, wraparound corner canopies,
## and visual identity communicated by appearance (e.g. washing machine drums for laundromat).

func build() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var wall_mat := UrbanMaterials.material_for_color(base_color, 0.84)
	var trim_mat := UrbanMaterials.trim_stone()
	
	# Recessed entrance alcove dimensions
	var is_corner: bool = building_kind in ["corner_shop", "corner_diner"] or building_id.begins_with("Corner")
	var door_center_x: float = 0.0 if not is_corner else -building_size.x * 0.15
	var door_w: float = 1.15
	var door_h: float = 2.35
	var recess_w: float = door_w + 0.45
	var recess_depth: float = 0.85
	
	# Main structural body with carved entrance volume:
	# 1. Rear Body (spanning full width behind the recess)
	var rear_d: float = building_size.y - recess_depth
	var rear_center_z: float = -half_d + rear_d * 0.5
	add_solid_box(visuals_root, "ShopRearBody", Vector3(0, height * 0.5, rear_center_z), Vector3(building_size.x, height, rear_d), wall_mat)
	
	# 2. Flanking Left Block
	var left_flank_w: float = (door_center_x - recess_w * 0.5) - (-half_w)
	if left_flank_w > 0.1:
		var left_center_x: float = -half_w + left_flank_w * 0.5
		var flank_center_z: float = half_d - recess_depth * 0.5
		add_solid_box(visuals_root, "ShopFlankLeft", Vector3(left_center_x, height * 0.5, flank_center_z), Vector3(left_flank_w, height, recess_depth), wall_mat)
	
	# 3. Flanking Right Block
	var right_flank_w: float = half_w - (door_center_x + recess_w * 0.5)
	if right_flank_w > 0.1:
		var right_center_x: float = (door_center_x + recess_w * 0.5) + right_flank_w * 0.5
		var flank_center_z: float = half_d - recess_depth * 0.5
		add_solid_box(visuals_root, "ShopFlankRight", Vector3(right_center_x, height * 0.5, flank_center_z), Vector3(right_flank_w, height, recess_depth), wall_mat)
	
	# 4. Overhead Lintel Block (above the entrance door opening)
	var lintel_h: float = height - door_h
	if lintel_h > 0.1:
		var lintel_y: float = door_h + lintel_h * 0.5
		var flank_center_z: float = half_d - recess_depth * 0.5
		add_solid_box(visuals_root, "ShopLintelOverhead", Vector3(door_center_x, lintel_y, flank_center_z), Vector3(recess_w, lintel_h, recess_depth), wall_mat)
	
	# Roof features
	add_roof_parapet(visuals_root, height, 0.40, 0.22, trim_mat)
	add_mesh_box(visuals_root,"V1RoofSurface",Vector3(0,height+.03,0),Vector3(building_size.x-.5,.06,building_size.y-.5),UrbanMaterials.material_for_color(v1_palette.roof,.92))
	add_cornice(visuals_root, height - 0.05, 0.36, 0.40, true, trim_mat)
	
	# Rooftop skylights and ventilation
	_build_roof_skylight(Vector3(half_w * 0.3, height + 0.05, -half_d * 0.2))
	add_hvac_chiller(visuals_root, Vector3(-half_w * 0.35, height + 0.05, -half_d * 0.2), Vector3(1.6, 0.8, 1.2))
	
	# Retail ground-floor storefront with open doorway alcove
	_build_storefront(front_z, is_corner, door_center_x, door_w, door_h, recess_w, recess_depth)
	
	# Upper floor residential/office windows
	if height >= 5.0:
		_build_upper_windows(front_z)
	
	# Facade proper name signage
	if not proper_name.is_empty():
		var sign_w: float = minf(building_size.x * 0.6, 4.2)
		var sign_node := UrbanSignage.create_sign_3d(proper_name, Vector2(sign_w, 0.60), 0.08, UrbanMaterials.trim_dark())
		if sign_node != null:
			# Placed neatly on the sign fascia board above the awning
			sign_node.position = Vector3(0, minf(3.45,height-.35), front_z + 0.16)
			visuals_root.add_child(sign_node)

func _build_storefront(front_z: float, is_corner: bool, door_center_x: float, door_w: float, door_h: float, recess_w: float, recess_depth: float) -> void:
	var dark_trim := UrbanMaterials.trim_dark()
	var glass_mat := UrbanMaterials.glass_display()
	var stone_trim := UrbanMaterials.trim_stone()
	
	var store_h: float = 2.9
	var half_w: float = building_size.x * 0.5
	
	# Stone framing pilasters at ends of storefront
	for side: float in [-half_w + 0.25, half_w - 0.25]:
		add_mesh_box(visuals_root, "StorePilaster", Vector3(side, store_h * 0.5, front_z + 0.06), Vector3(0.50, store_h + 0.2, 0.16), stone_trim)
	
	# Horizontal sign fascia board band above display windows
	add_mesh_box(visuals_root, "SignFascia", Vector3(0, store_h + 0.25, front_z + 0.08), Vector3(building_size.x - 0.2, 0.70, 0.18), dark_trim)
	
	# Recessed customer entry door - sitting at the back of the open alcove
	var alcove_back_z: float = front_z - recess_depth
	var door_y: float = door_h * 0.5
	
	# Alcove side return walls and trim
	add_mesh_box(visuals_root, "AlcoveWallLeft", Vector3(door_center_x - recess_w * 0.5, door_y, front_z - recess_depth * 0.5), Vector3(0.06, door_h, recess_depth), dark_trim)
	add_mesh_box(visuals_root, "AlcoveWallRight", Vector3(door_center_x + recess_w * 0.5, door_y, front_z - recess_depth * 0.5), Vector3(0.06, door_h, recess_depth), dark_trim)
	
	# Customer door with glass panel and brass handle inside the alcove
	add_mesh_box(visuals_root, "ShopDoor", Vector3(door_center_x, door_y, alcove_back_z + 0.04), Vector3(door_w, door_h, 0.06), UrbanMaterials.wood_door_navy())
	var door_glass := add_mesh_box(visuals_root, "DoorGlass", Vector3(door_center_x, door_y + 0.2, alcove_back_z + 0.06), Vector3(door_w * 0.65, door_h * 0.6, 0.02), glass_mat)
	door_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_mesh_box(visuals_root, "DoorHandle", Vector3(door_center_x + door_w * 0.35, 1.05, alcove_back_z + 0.10), Vector3(0.04, 0.32, 0.06), UrbanMaterials.metal_brass())
	
	# Flanking display windows
	var left_w: float = (door_center_x - recess_w * 0.5) - (-half_w + 0.5)
	var right_w: float = (half_w - 0.5) - (door_center_x + recess_w * 0.5)
	
	if left_w > 1.2:
		var lx: float = -half_w + 0.5 + left_w * 0.5
		_build_display_bay(Vector3(lx, store_h * 0.5, front_z + 0.04), Vector2(left_w - 0.15, store_h - 0.3), "BayLeft")
	
	if right_w > 1.2:
		var rx: float = door_center_x + recess_w * 0.5 + right_w * 0.5
		_build_display_bay(Vector3(rx, store_h * 0.5, front_z + 0.04), Vector2(right_w - 0.15, store_h - 0.3), "BayRight")
	
	# Awning
	_build_awning(front_z, store_h, is_corner)

func _build_display_bay(at: Vector3, size: Vector2, bay_name: String) -> void:
	var dark_trim := UrbanMaterials.trim_dark()
	var glass_mat := UrbanMaterials.glass_display()
	
	var kickplate_h := 0.45
	var win_h := size.y - kickplate_h
	var win_y := at.y - size.y * 0.5 + kickplate_h + win_h * 0.5
	
	# Dark kickplate panel below glass
	add_mesh_box(visuals_root, bay_name + "_Kickplate", Vector3(at.x, at.y - size.y * 0.5 + kickplate_h * 0.5, at.z), Vector3(size.x, kickplate_h, 0.08), dark_trim)
	
	# Display glass pane
	var glass := add_mesh_box(visuals_root, bay_name + "_Glass", Vector3(at.x, win_y, at.z + 0.02), Vector3(size.x - 0.08, win_h, 0.04), glass_mat)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Vertical divider mullions
	if size.x > 2.2:
		var parts := 2 if size.x < 3.8 else 3
		var step := size.x / float(parts)
		for p in range(1, parts):
			var px := at.x - size.x * 0.5 + float(p) * step
			add_mesh_box(visuals_root, bay_name + "_Mullion_%d" % p, Vector3(px, win_y, at.z + 0.04), Vector3(0.06, win_h, 0.06), dark_trim)

	# Productive corner shops show a counter and hanging lights through the
	# glazing; these are volumes behind the glass, not facade decals.
	if building_kind in ["corner_shop","corner_diner"] or building_id.begins_with("Corner"):
		add_mesh_box(visuals_root,bay_name+"_Counter",Vector3(at.x,.72,at.z-.38),Vector3(maxf(.8,size.x-.35),.18,.42),UrbanMaterials.get_mat("shop_counter",Color("765139"),.82))
		for pendant_index in maxi(1,int(size.x/2.2)):
			var pendant_x:=at.x-size.x*.28+float(pendant_index)*minf(1.8,size.x*.42)
			_build_pendant(Vector3(pendant_x,2.28,at.z-.42),bay_name+"_Pendant_%d"%pendant_index)
	
	# Specialized visual interior: Laundromat washing machines
	if building_kind == "commercial_laundromat" or building_id == "Laundry":
		var drum_count := maxi(1, int(size.x / 1.1))
		var drum_step := size.x / float(drum_count)
		var machine_mat := UrbanMaterials.wall_cream()
		var drum_mat := UrbanMaterials.metal_dark()
		
		for m in drum_count:
			var mx := at.x - size.x * 0.5 + drum_step * 0.5 + float(m) * drum_step
			var my := win_y - 0.2
			var mz := at.z - 0.35
			# Machine cabinet body
			add_mesh_box(visuals_root, "WasherCabinet", Vector3(mx, my, mz), Vector3(0.65, 0.85, 0.65), machine_mat)
			# Circular front glass porthole drum, preserving the productive V1 cue.
			_add_washer_porthole(Vector3(mx,my+.05,mz+.34),drum_mat)

func _build_pendant(at: Vector3, label: String) -> void:
	add_mesh_box(visuals_root,label+"_Stem",at+Vector3(0,.22,0),Vector3(.035,.44,.035),UrbanMaterials.metal_dark())
	var shade:=MeshInstance3D.new()
	shade.name=label+"_Shade"
	var shade_mesh:=CylinderMesh.new()
	shade_mesh.top_radius=.06
	shade_mesh.bottom_radius=.18
	shade_mesh.height=.16
	shade_mesh.radial_segments=12
	shade.mesh=shade_mesh
	shade.position=at
	shade.material_override=UrbanMaterials.get_mat("pendant_brass",Color("efcc83"),.45,.55)
	visuals_root.add_child(shade)

func _add_washer_porthole(at: Vector3, drum_mat: Material) -> void:
	for part in [["WasherPortholeRing",.25,.055,drum_mat],["WasherPortholeGlass",.18,.06,UrbanMaterials.glass_display()]]:
		var disc:=MeshInstance3D.new()
		disc.name=String(part[0])
		var mesh:=CylinderMesh.new()
		mesh.top_radius=float(part[1])
		mesh.bottom_radius=float(part[1])
		mesh.height=float(part[2])
		mesh.radial_segments=20
		disc.mesh=mesh
		disc.rotation_degrees.x=90
		disc.position=at+Vector3(0,0,.015 if String(part[0]).ends_with("Glass") else 0.0)
		disc.material_override=part[3]
		visuals_root.add_child(disc)

func _build_awning(front_z: float, store_h: float, is_corner: bool) -> void:
	var awning_color: Color = accent_color
	if building_kind in ["corner_shop", "corner_diner"] or building_id.begins_with("Corner"):
		if proper_name == "TIDELINE":
			awning_color = Color("477f7d")
		elif proper_name == "EARLY SHIFT":
			awning_color = Color("68784a")
		else:
			awning_color = Color("a65338")
	elif building_kind == "commercial_laundromat" or building_id == "Laundry":
		awning_color = Color("366f70")
	var awning_mat: StandardMaterial3D = UrbanMaterials.material_for_color(awning_color, 0.72)
	
	var awning_y := store_h + 0.05
	var awning_depth := 1.3
	var awning_drop := 0.65
	var awning_w := building_size.x - 0.4
	
	# Main sloped awning canopy
	var canopy := add_mesh_box(visuals_root, "AwningCanopy", Vector3(0, awning_y, front_z + awning_depth * 0.5), Vector3(awning_w, 0.08, awning_depth), awning_mat)
	canopy.rotation.x = 0.28
	
	# Front decorative valance / skirt
	add_mesh_box(visuals_root, "AwningValance", Vector3(0, awning_y - awning_drop * 0.5, front_z + awning_depth), Vector3(awning_w, 0.28, 0.04), awning_mat)
	# Twelve alternating fabric strips match HarborBuilding._draw_shop_awning.
	var stripe_mat:=UrbanMaterials.material_for_color(Color("e9dfc7"),.76)
	var stripe_w:=awning_w/12.0
	for stripe_index in range(1,12,2):
		var stripe_x:=-awning_w*.5+stripe_w*(float(stripe_index)+.5)
		var canopy_stripe:=add_mesh_box(visuals_root,"AwningStripe_%02d"%stripe_index,Vector3(stripe_x,awning_y+.012,front_z+awning_depth*.5),Vector3(stripe_w*.92,.025,awning_depth*.98),stripe_mat)
		canopy_stripe.rotation.x=.28
		add_mesh_box(visuals_root,"ValanceStripe_%02d"%stripe_index,Vector3(stripe_x,awning_y-awning_drop*.5,front_z+awning_depth+.025),Vector3(stripe_w*.92,.26,.018),stripe_mat)
	
	# Wraparound side canopy for corner buildings
	if is_corner:
		var side_depth := minf(building_size.y * 0.45, 3.8)
		var side_x := building_size.x * 0.5
		var side_canopy := add_mesh_box(visuals_root, "CornerAwning", Vector3(side_x + awning_depth * 0.5, awning_y, front_z - side_depth * 0.5), Vector3(awning_depth, 0.08, side_depth), awning_mat)
		side_canopy.rotation.z = -0.28

func _build_upper_windows(front_z: float) -> void:
	var trim_mat := UrbanMaterials.trim_stone()
	var glass_mat := UrbanMaterials.glass_window()
	var dark_mat := UrbanMaterials.window_interior_dark()
	
	var win_w := 1.10
	var win_h := 1.45
	var win_y := 4.6
	
	var count := maxi(2, int(building_size.x / 2.6))
	var step := (building_size.x - 1.2) / float(count)
	
	for c in count:
		var wx: float = -building_size.x * 0.5 + 0.6 + step * 0.5 + float(c) * step
		add_mesh_box(visuals_root, "UpperSill", Vector3(wx, win_y - win_h * 0.5 - 0.06, front_z + 0.08), Vector3(win_w + 0.2, 0.12, 0.20), trim_mat)
		add_mesh_box(visuals_root, "UpperLintel", Vector3(wx, win_y + win_h * 0.5 + 0.08, front_z + 0.06), Vector3(win_w + 0.24, 0.16, 0.14), trim_mat)
		add_mesh_box(visuals_root, "UpperFrame", Vector3(wx, win_y, front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
		var glass := add_mesh_box(visuals_root, "UpperGlass", Vector3(wx, win_y, front_z + 0.04), Vector3(win_w - 0.12, win_h - 0.12, 0.02), glass_mat)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_roof_skylight(at: Vector3) -> void:
	var sky := Node3D.new()
	sky.name = "RoofSkylight"
	sky.position = at
	
	var curb_mat := UrbanMaterials.trim_stone()
	var glass_mat := UrbanMaterials.glass_window()
	var size := Vector3(2.2, 0.45, 1.4)
	
	add_mesh_box(sky, "Curb", Vector3(0, size.y * 0.5, 0), size, curb_mat)
	var glass := add_mesh_box(sky, "GlassPane", Vector3(0, size.y + 0.04, 0), Vector3(size.x - 0.2, 0.08, size.z - 0.2), glass_mat)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	visuals_root.add_child(sky)
