extends UrbanBuildingBase
class_name UrbanServiceBuilding

var police_door_visuals: Array[Node3D] = []
var police_door_bodies: Array[StaticBody3D] = []
var fire_door_visual: Node3D
var fire_door_body: StaticBody3D
var fire_door_shape: BoxShape3D
var fire_door_height := 3.8
var open_amount := 0.0

func set_open_amount(amount: float) -> void:
	if building_kind == "fire_station" or building_id == "NorthFireStation":
		open_amount = clampf(amount, 0.0, 1.0)
		if not is_instance_valid(fire_door_visual): return
		# Sectional shutter stacks under its header; visual and solid rise together.
		fire_door_visual.position.y = fire_door_height * open_amount
		fire_door_visual.scale.y = maxf(.001, 1.0 - open_amount)
		fire_door_shape.size.y = maxf(.004, fire_door_height * (1.0 - open_amount))
		fire_door_body.position.y = fire_door_height * open_amount
		fire_door_body.get_child(0).position.y = fire_door_shape.size.y * .5
		return
	if building_kind != "police_precinct" and building_id != "Police": return
	open_amount = clampf(amount, 0.0, 1.0)
	for i in police_door_visuals.size():
		var side := -1.0 if i == 0 else 1.0
		police_door_visuals[i].rotation.y = -side * 1.2 * open_amount
		police_door_bodies[i].rotation.y = police_door_visuals[i].rotation.y

## Reconstructs emergency service buildings and municipal infrastructure:
## - Fire Station: 3 appliance engine bays, hose-drying tower, siren, crossed-tool emblem.
## - Police Precinct: Motor pool bay, secure entry, police shield, blue/white marker band.
## - Motor Workshop: Open drive-in service bay with solid side and rear walls, overhead truss.

func build() -> void:
	if building_kind == "fire_station" or building_id == "NorthFireStation":
		_build_fire_station()
	elif building_kind == "police_precinct" or building_id == "Police":
		_build_police_precinct()
	elif building_kind == "garage" or building_id == "MotorWorkshop":
		_build_motor_workshop()
	else:
		_build_default_box()

func _build_fire_station() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var wall_mat := UrbanMaterials.material_for_color(Color("75413a"), 0.86)
	var trim_mat := UrbanMaterials.trim_stone()
	var red_mat := UrbanMaterials.emergency_red()
	var dark_mat := UrbanMaterials.metal_dark()
	
	# Main engine house volume
	var main_w := building_size.x * 0.76
	var main_center_x := half_w - main_w * 0.5
	var center_bay_w := (main_w - 2.2) / 3.0
	var wing_w := (main_w - center_bay_w) * .5
	# Central bay is a physical vestibule; the other two remain solid engine bays.
	for side in [-1.0, 1.0]:
		add_solid_box(visuals_root, "FireHouseWing", Vector3(main_center_x + side * (center_bay_w + wing_w) * .5, height * .5, 0), Vector3(wing_w, height, building_size.y), wall_mat)
	add_solid_box(visuals_root, "FireHouseRear", Vector3(main_center_x, height * .5, -.9), Vector3(center_bay_w, height, building_size.y - 1.8), wall_mat)
	add_solid_box(visuals_root, "FireBayHeader", Vector3(main_center_x, (height + 3.8) * .5, front_z - .9), Vector3(center_bay_w, height - 3.8, 1.8), wall_mat)
	add_roof_parapet(visuals_root, height, 0.45, 0.25, trim_mat)
	add_roof_gravel(visuals_root, height)
	
	# Left: Hose-drying tower (taller asymmetric silhouette as authored in ProceduralBuilding:430-441)
	var tower_w := building_size.x * 0.24
	var tower_d := building_size.y * 0.45
	var tower_h := height + 4.2
	var tower_center_x := -half_w + tower_w * 0.5
	var tower_center_z := -half_d + tower_d * 0.5 + 1.0
	
	add_solid_box(visuals_root, "HoseTower", Vector3(tower_center_x, tower_h * 0.5, tower_center_z), Vector3(tower_w, tower_h, tower_d), UrbanMaterials.brick_red())
	add_mesh_box(visuals_root, "TowerCornice", Vector3(tower_center_x, tower_h + 0.08, tower_center_z), Vector3(tower_w + 0.25, 0.16, tower_d + 0.25), trim_mat)
	
	# Tower louvered drying vents
	for vy in [height + 1.2, height + 2.6]:
		add_mesh_box(visuals_root, "TowerLouver", Vector3(tower_center_x, vy, tower_center_z + tower_d * 0.5 + 0.02), Vector3(tower_w * 0.6, 0.8, 0.06), dark_mat)
	
	# Rooftop emergency siren on main building
	var siren_pos := Vector3(main_center_x + main_w * 0.35, height + 0.5, front_z - 1.2)
	add_mesh_box(visuals_root, "SirenMast", siren_pos, Vector3(0.12, 1.0, 0.12), dark_mat)
	add_mesh_box(visuals_root, "SirenHorn", siren_pos + Vector3(0, 0.45, 0), Vector3(0.55, 0.35, 0.55), red_mat)
	
	# Three equal engine appliance bays
	var bay_count := 3
	var bay_margin := 0.6
	var bay_gap := 0.5
	var usable_w := main_w - bay_margin * 2.0
	var bay_w := (usable_w - bay_gap * float(bay_count - 1)) / float(bay_count)
	var bay_h := 3.8
	
	for b in bay_count:
		var bx: float = main_center_x - main_w * 0.5 + bay_margin + bay_w * 0.5 + float(b) * (bay_w + bay_gap)
		var by: float = bay_h * 0.5
		
		# Stone portal surround
		if b == 1:
			add_mesh_box(visuals_root, "ApplianceLintel", Vector3(bx, bay_h + .125, front_z + .04), Vector3(bay_w + .35, .25, .12), trim_mat)
			for side in [-1.0, 1.0]:
				add_mesh_box(visuals_root, "ApplianceJamb", Vector3(bx + side * (bay_w + .175) * .5, by, front_z + .04), Vector3(.175, bay_h, .12), trim_mat)
		else:
			add_mesh_box(visuals_root, "ApplianceSurround", Vector3(bx, by, front_z + 0.04), Vector3(bay_w + 0.35, bay_h + 0.25, 0.12), trim_mat)
		var panel_root: Node3D = visuals_root
		var panel_x := bx
		var panel_z := front_z + .06
		if b == 1:
			fire_door_visual = Node3D.new()
			fire_door_visual.name = "FireWalkupShutter"
			fire_door_visual.position = Vector3(bx, 0, panel_z)
			visuals_root.add_child(fire_door_visual)
			panel_root = fire_door_visual
			panel_x = 0.0
			panel_z = 0.0
			fire_door_body = StaticBody3D.new()
			fire_door_body.name = "FireWalkupShutterSolid"
			fire_door_body.collision_layer = 1
			fire_door_body.collision_mask = 0
			fire_door_body.position = fire_door_visual.position
			var shape := CollisionShape3D.new()
			fire_door_shape = BoxShape3D.new()
			fire_door_shape.size = Vector3(bay_w, bay_h, .08)
			shape.shape = fire_door_shape
			shape.position.y = by
			fire_door_body.add_child(shape)
			collision_root.add_child(fire_door_body)
		
		# Red glazed sectional appliance door
		add_mesh_box(panel_root, "ApplianceDoor", Vector3(panel_x, by, panel_z), Vector3(bay_w, bay_h, 0.06), red_mat)
		
		# Horizontal door panel segments
		for seg in 4:
			var sy := float(seg) * (bay_h / 4.0) + (bay_h / 8.0)
			add_mesh_box(panel_root, "DoorSegment", Vector3(panel_x, sy, panel_z + .02), Vector3(bay_w - 0.1, 0.04, 0.02), dark_mat)
			# Glass window inserts on middle segment
			if seg == 2:
				var glass := add_mesh_box(panel_root, "ApplianceGlass", Vector3(panel_x, sy, panel_z + .025), Vector3(bay_w * 0.75, (bay_h / 4.0) * 0.6, 0.02), UrbanMaterials.glass_window())
				glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Crossed ladder/tool emblem above center bay
	var emblem_pos := Vector3(main_center_x, bay_h + 0.75, front_z + 0.08)
	var emblem_mat := UrbanMaterials.metal_brass()
	var ladder1 := add_mesh_box(visuals_root, "EmblemLadder1", emblem_pos, Vector3(0.08, 1.3, 0.04), emblem_mat)
	ladder1.rotation.z = 0.785
	var ladder2 := add_mesh_box(visuals_root, "EmblemLadder2", emblem_pos, Vector3(0.08, 1.3, 0.04), emblem_mat)
	ladder2.rotation.z = -0.785
	
	# Facade proper name signage
	if not proper_name.is_empty():
		var sign := UrbanSignage.create_sign_3d(proper_name, Vector2(minf(main_w * 0.65, 5.2), 0.70), 0.08, trim_mat)
		if sign != null:
			sign.position = Vector3(main_center_x, height - 0.65, front_z + 0.12)
			visuals_root.add_child(sign)

func _build_police_precinct() -> void:
	var half_w := building_size.x * 0.5
	var half_d := building_size.y * 0.5
	var front_z := half_d
	
	var wall_mat := UrbanMaterials.material_for_color(Color("4f6878"), 0.84)
	var trim_mat := UrbanMaterials.trim_stone()
	var dark_mat := UrbanMaterials.metal_dark()
	var blue_mat := UrbanMaterials.police_blue()
	var accent_mat := UrbanMaterials.police_accent()
	
	# Leave a short, physical vestibule behind the pedestrian doorway. The
	# walk-in transition happens inside it, before the rear wall.
	add_solid_box(visuals_root, "PrecinctBody", Vector3(0, height * 0.5, -0.75), Vector3(building_size.x, height, building_size.y - 1.5), wall_mat)
	var front_wing_width := half_w - 1.3
	for side in [-1.0, 1.0]:
		add_solid_box(visuals_root, "PrecinctFrontWing", Vector3(side * (half_w + 1.3) * 0.5, height * 0.5, front_z - 0.12), Vector3(front_wing_width, height, 0.24), wall_mat)
		add_solid_box(visuals_root, "PrecinctVestibuleSide", Vector3(side * 1.3, 1.5, front_z - 0.8), Vector3(0.2, 3.0, 1.6), wall_mat)
	add_solid_box(visuals_root, "PrecinctVestibuleRoof", Vector3(0, height - 0.15, front_z - 0.75), Vector3(2.6, 0.3, 1.5), wall_mat)
	add_roof_parapet(visuals_root, height, 0.50, 0.28, trim_mat)
	add_roof_gravel(visuals_root, height)
	
	# Left: Motor-pool shutter bay (for patrol cars)
	var bay_w := building_size.x * 0.48
	var bay_h := 3.4
	var bay_center_x := -half_w + 0.6 + bay_w * 0.5
	var bay_y := bay_h * 0.5
	
	add_mesh_box(visuals_root, "MotorPoolSurround", Vector3(bay_center_x, bay_y, front_z + 0.04), Vector3(bay_w + 0.3, bay_h + 0.25, 0.12), dark_mat)
	add_mesh_box(visuals_root, "MotorPoolShutter", Vector3(bay_center_x, bay_y, front_z + 0.06), Vector3(bay_w, bay_h, 0.06), UrbanMaterials.metal_corrugated())
	
	# Right: Fortified pedestrian entrance
	var entry_w := 2.4
	var entry_h := 2.6
	var entry_center_x: float = 0.0 if data.has("entry_position") else half_w - 0.8 - entry_w * 0.5
	var entry_y := entry_h * 0.5
	
	add_mesh_box(visuals_root, "EntryPortalTop", Vector3(entry_center_x, entry_h + 0.1, front_z + 0.06), Vector3(entry_w + 0.35, 0.35, 0.15), trim_mat)
	for side in [-1.0, 1.0]:
		add_mesh_box(visuals_root, "EntryPortalSide", Vector3(entry_center_x + side * (entry_w + 0.25) * 0.5, entry_y, front_z + 0.06), Vector3(0.15, entry_h, 0.15), trim_mat)
		var hinge := Node3D.new()
		hinge.position = Vector3(entry_center_x + side * entry_w * 0.5, 0, front_z + 0.16)
		visuals_root.add_child(hinge)
		add_mesh_box(hinge, "EntryDoor", Vector3(-side * entry_w * 0.25, entry_y, 0), Vector3(entry_w * 0.5, entry_h, 0.06), dark_mat)
		var glass := add_mesh_box(hinge, "EntryGlass", Vector3(-side * entry_w * 0.25, entry_y + 0.3, 0.04), Vector3(entry_w * 0.34, entry_h * 0.5, 0.02), UrbanMaterials.glass_window())
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		police_door_visuals.append(hinge)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = hinge.position
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(entry_w * 0.5, entry_h, 0.08)
		shape.shape = box
		shape.position = Vector3(-side * entry_w * 0.25, entry_y, 0)
		body.add_child(shape)
		collision_root.add_child(body)
		police_door_bodies.append(body)
	
	# Police Shield Emblem above entrance
	var shield_pos := Vector3(entry_center_x, entry_h + 0.70, front_z + 0.10)
	add_mesh_box(visuals_root, "PoliceShield", shield_pos, Vector3(0.65, 0.75, 0.08), blue_mat)
	add_mesh_box(visuals_root, "ShieldStar", shield_pos + Vector3(0, 0, 0.05), Vector3(0.25, 0.25, 0.04), accent_mat)
	
	# Horizontal Blue & White identity stripe along facade
	add_mesh_box(visuals_root, "BlueBand", Vector3(0, bay_h + 0.15, front_z + 0.05), Vector3(building_size.x, 0.22, 0.10), blue_mat)
	add_mesh_box(visuals_root, "WhiteBand", Vector3(0, bay_h + 0.35, front_z + 0.05), Vector3(building_size.x, 0.12, 0.10), accent_mat)
	
	# Upper security windows with steel protective bars
	var win_y := 5.2
	var win_w := 1.2
	var win_h := 1.3
	for offset_x in [-half_w * 0.45, 0.0, half_w * 0.45]:
		add_mesh_box(visuals_root, "SecFrame", Vector3(offset_x, win_y, front_z + 0.02), Vector3(win_w, win_h, 0.08), dark_mat)
		var glass := add_mesh_box(visuals_root, "SecGlass", Vector3(offset_x, win_y, front_z + 0.04), Vector3(win_w - 0.1, win_h - 0.1, 0.02), UrbanMaterials.glass_window())
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Security bars
		for b in 3:
			var bx: float = offset_x - win_w * 0.3 + float(b) * (win_w * 0.3)
			add_mesh_box(visuals_root, "Bar", Vector3(bx, win_y, front_z + 0.06), Vector3(0.03, win_h, 0.03), dark_mat)
	
	# Communications antenna on roof
	var ant := Node3D.new()
	ant.name = "RadioTower"
	ant.position = Vector3(half_w * 0.35, height + 0.05, -half_d * 0.3)
	add_mesh_box(ant, "Mast", Vector3(0, 1.8, 0), Vector3(0.08, 3.6, 0.08), UrbanMaterials.metal_steel())
	add_mesh_box(ant, "Crossbar", Vector3(0, 3.2, 0), Vector3(1.2, 0.04, 0.04), blue_mat)
	visuals_root.add_child(ant)
	
	# Facade proper name signage
	if not proper_name.is_empty():
		var sign := UrbanSignage.create_sign_3d(proper_name, Vector2(minf(building_size.x * 0.55, 4.4), 0.65), 0.08, blue_mat)
		if sign != null:
			sign.position = Vector3(0, height - 0.65, front_z + 0.12)
			visuals_root.add_child(sign)

func _build_motor_workshop() -> void:
	# MotorWorkshop in Northgate is a Drive-In Service Bay!
	# Reconciles strictly with HarborBuilding.gd:29-31:
	# Left solid:  Rect2(-134, -104, 79, 208) -> width 4.9375m, depth 13.0m, center_x = -5.90625m
	# Right solid: Rect2( 55,  -104, 79, 208) -> width 4.9375m, depth 13.0m, center_x =  5.90625m
	# Rear solid:  Rect2(-55,  -104, 110, 40) -> width 6.875m (110px), depth 2.5m (40px), center_z = -5.25m
	# Open drive-in bay: width 6.875m (110px), clear driveway from Z = -4.0m to Z = +6.5m.
	
	var wall_mat := UrbanMaterials.material_for_color(Color("6bd2b2").darkened(0.2), 0.86)
	var roof_mat := UrbanMaterials.roof_tin()
	
	var side_w: float = 79.0 / 16.0       # 4.9375 m
	var side_d: float = 208.0 / 16.0      # 13.0 m
	var left_cx: float = -94.5 / 16.0     # -5.90625 m
	var right_cx: float = 94.5 / 16.0     #  5.90625 m
	
	var rear_w: float = 110.0 / 16.0      # 6.875 m
	var rear_d: float = 40.0 / 16.0       # 2.5 m
	var rear_cz: float = -84.0 / 16.0     # -5.25 m
	
	# Left Solid Wall
	add_solid_box(visuals_root, "WorkshopLeft", Vector3(left_cx, height * 0.5, 0), Vector3(side_w, height, side_d), wall_mat)
	
	# Right Solid Wall
	add_solid_box(visuals_root, "WorkshopRight", Vector3(right_cx, height * 0.5, 0), Vector3(side_w, height, side_d), wall_mat)
	
	# Rear Solid Wall (110px wide x 40px deep)
	add_solid_box(visuals_root, "WorkshopRear", Vector3(0, height * 0.5, rear_cz), Vector3(rear_w, height, rear_d), wall_mat)
	
	# Overhead Roof & Steel Trusses (covering the structure above drive-in height)
	add_solid_box(visuals_root, "WorkshopRoof", Vector3(0, height + 0.15, 0), Vector3(building_size.x + 0.3, 0.30, building_size.y + 0.3), roof_mat)
	
	# Yellow & Black Hazard Warning Stripes along the entrance canopy beam
	var beam_pos := Vector3(0, height - 0.25, side_d * 0.5 + 0.05)
	add_mesh_box(visuals_root, "HazardBeam", beam_pos, Vector3(rear_w + 0.4, 0.50, 0.15), UrbanMaterials.hazard_stripe_yellow())
	
	# Diagonal hazard stripes
	var stripe_count: int = int(rear_w / 0.65)
	for s in stripe_count:
		var sx: float = -rear_w * 0.5 + 0.3 + float(s) * 0.65
		add_mesh_box(visuals_root, "Stripe_%d" % s, Vector3(sx, beam_pos.y, beam_pos.z + 0.08), Vector3(0.22, 0.48, 0.02), UrbanMaterials.hazard_stripe_black())
	
	# Service tools / workbench on side apron
	add_mesh_box(visuals_root, "WorkbenchLeft", Vector3(left_cx + side_w * 0.5 - 0.45, 0.45, 0), Vector3(0.70, 0.90, 2.4), UrbanMaterials.metal_steel())
