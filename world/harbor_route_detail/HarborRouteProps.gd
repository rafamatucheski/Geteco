extends RefCounted
class_name HarborRouteProps

## Factory library for modular, native 3D urban street furniture, sidewalks, and curbs.
## Strictly adheres to Geteco V2 physics and performance contracts:
## - All solids have exact StaticBody3D volumes on collision_layer 1 (mask 0).
## - Shared materials from HarborRouteMaterials.
## - Zero descriptive/decorative signage.
## - Safe for pedestrian and vehicular navigation without accidental traps.

# ==============================================================================
# Sidewalks & Curbs
# ==============================================================================

## Creates an elevated sidewalk pavement slab.
static func create_sidewalk_slab(size: Vector2, height: float = 0.14, mat: StandardMaterial3D = null, with_collision: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "SidewalkSlab"
	
	if mat == null:
		mat = HarborRouteMaterials.sidewalk_concrete()
	
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "SlabMesh"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, height, size.y)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(mesh_inst)
	
	if with_collision:
		var body := StaticBody3D.new()
		body.name = "SlabCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		col.position = mesh_inst.position
		body.add_child(col)
		root.add_child(body)
	
	return root

## Creates a linear curb stone section along the edge of a sidewalk.
static func create_curb_segment(length: float, width: float = 0.30, height: float = 0.16, mat: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "CurbSegment"
	
	if mat == null:
		mat = HarborRouteMaterials.curb_granite()
	
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "CurbMesh"
	var box := BoxMesh.new()
	box.size = Vector3(width, height, length)
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(mesh_inst)
	
	var body := StaticBody3D.new()
	body.name = "CurbCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = mesh_inst.position
	body.add_child(col)
	root.add_child(body)
	
	return root

## Creates a beveled curb cut / pedestrian & vehicle ramp for smooth level transitions.
## Slopes smoothly from road level (Y = 0.0) at the front edge (+Z) to curb height (Y = max_height) at the rear edge (-Z).
## Angle of inclination: atan2(max_height, depth_z) ≈ 8° to 12°, well within CharacterBody3D floor_max_angle.
static func create_curb_ramp(span_x: float, depth_z: float = 0.70, max_height: float = 0.14, mat: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "CurbRamp"
	
	if mat == null:
		mat = HarborRouteMaterials.curb_granite()
	
	var hx := span_x * 0.5
	var hz := depth_z * 0.5
	
	# Six vertices of the right-triangular wedge:
	# - Rear face at -hz has height = max_height
	# - Front face at +hz has height = 0.0
	var v_rear_top_l := Vector3(-hx, max_height, -hz)
	var v_rear_top_r := Vector3(hx, max_height, -hz)
	var v_rear_bot_l := Vector3(-hx, 0.0, -hz)
	var v_rear_bot_r := Vector3(hx, 0.0, -hz)
	var v_front_l := Vector3(-hx, 0.0, hz)
	var v_front_r := Vector3(hx, 0.0, hz)
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Top sloped surface (walkable/drivable face)
	var slope_norm := Vector3(0.0, depth_z, max_height).normalized()
	st.set_normal(slope_norm)
	st.add_vertex(v_front_l)
	st.add_vertex(v_rear_top_l)
	st.add_vertex(v_rear_top_r)
	
	st.add_vertex(v_front_l)
	st.add_vertex(v_rear_top_r)
	st.add_vertex(v_front_r)
	
	# Rear vertical face
	st.set_normal(Vector3(0.0, 0.0, -1.0))
	st.add_vertex(v_rear_bot_l)
	st.add_vertex(v_rear_top_l)
	st.add_vertex(v_rear_top_r)
	
	st.add_vertex(v_rear_bot_l)
	st.add_vertex(v_rear_top_r)
	st.add_vertex(v_rear_bot_r)
	
	# Bottom face
	st.set_normal(Vector3(0.0, -1.0, 0.0))
	st.add_vertex(v_rear_bot_l)
	st.add_vertex(v_rear_bot_r)
	st.add_vertex(v_front_r)
	
	st.add_vertex(v_rear_bot_l)
	st.add_vertex(v_front_r)
	st.add_vertex(v_front_l)
	
	# Left triangular side
	st.set_normal(Vector3(-1.0, 0.0, 0.0))
	st.add_vertex(v_front_l)
	st.add_vertex(v_rear_bot_l)
	st.add_vertex(v_rear_top_l)
	
	# Right triangular side
	st.set_normal(Vector3(1.0, 0.0, 0.0))
	st.add_vertex(v_front_r)
	st.add_vertex(v_rear_top_r)
	st.add_vertex(v_rear_bot_r)
	
	var array_mesh := st.commit()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "RampMesh"
	mesh_inst.mesh = array_mesh
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	
	# Physical collision using identical convex hull
	var body := StaticBody3D.new()
	body.name = "RampCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		v_rear_top_l, v_rear_top_r,
		v_rear_bot_l, v_rear_bot_r,
		v_front_l, v_front_r
	])
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	
	return root

# ==============================================================================
# Street Lighting
# ==============================================================================

## Creates a municipal street light.
## Styles:
## - "standard": Tall steel pole with arched mast arm and cobra-head luminaire.
## - "police": Civic cast-iron dual globe lamp post with navy blue base.
## - "industrial": Robust goose-neck lamp mounted on heavy square base for workshop aprons.
static func create_streetlight(pole_height: float = 5.4, arm_length: float = 1.35, style: String = "standard", rotate_y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLight_%s" % style
	root.rotation.y = rotate_y
	
	var base_mat := HarborRouteMaterials.cast_iron_dark() if style in ["police", "industrial"] else HarborRouteMaterials.steel_galvanized()
	
	# 1. Base pedestal
	var pedestal := MeshInstance3D.new()
	pedestal.name = "Pedestal"
	var ped_mesh := CylinderMesh.new()
	ped_mesh.top_radius = 0.16
	ped_mesh.bottom_radius = 0.22
	ped_mesh.height = 0.55
	pedestal.mesh = ped_mesh
	pedestal.material_override = HarborRouteMaterials.police_navy() if style == "police" else base_mat
	pedestal.position = Vector3(0.0, 0.275, 0.0)
	root.add_child(pedestal)
	
	# 2. Main shaft
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.13
	pole_mesh.height = pole_height - 0.55
	pole.mesh = pole_mesh
	pole.material_override = base_mat
	pole.position = Vector3(0.0, 0.55 + pole_mesh.height * 0.5, 0.0)
	root.add_child(pole)
	
	# 3. Mast arm and luminaire head depending on style
	match style:
		"police":
			# Civic cross-arm with 2 frosted globes
			var cross_arm := MeshInstance3D.new()
			cross_arm.name = "CrossArm"
			var ca_mesh := BoxMesh.new()
			ca_mesh.size = Vector3(1.40, 0.09, 0.09)
			cross_arm.mesh = ca_mesh
			cross_arm.material_override = base_mat
			cross_arm.position = Vector3(0.0, pole_height - 0.15, 0.0)
			root.add_child(cross_arm)
			
			for side in [-0.60, 0.60]:
				var globe := MeshInstance3D.new()
				globe.name = "Globe_%s" % ("Left" if side < 0 else "Right")
				var sp := SphereMesh.new()
				sp.radius = 0.18
				sp.height = 0.36
				globe.mesh = sp
				globe.material_override = HarborRouteMaterials.lamp_emissive()
				globe.position = Vector3(side, pole_height - 0.10, 0.0)
				root.add_child(globe)
		
		"industrial":
			# Angled 45-degree bracket and cone shade
			var bracket := MeshInstance3D.new()
			bracket.name = "Bracket"
			var b_mesh := CylinderMesh.new()
			b_mesh.top_radius = 0.05
			b_mesh.bottom_radius = 0.05
			b_mesh.height = 0.95
			bracket.mesh = b_mesh
			bracket.material_override = base_mat
			bracket.position = Vector3(0.35, pole_height - 0.20, 0.0)
			bracket.rotation_degrees = Vector3(0, 0, -45)
			root.add_child(bracket)
			
			var shade := MeshInstance3D.new()
			shade.name = "ConeShade"
			var c_mesh := CylinderMesh.new()
			c_mesh.top_radius = 0.08
			c_mesh.bottom_radius = 0.28
			c_mesh.height = 0.22
			shade.mesh = c_mesh
			shade.material_override = HarborRouteMaterials.cast_iron_dark()
			shade.position = Vector3(0.70, pole_height - 0.50, 0.0)
			root.add_child(shade)
			
			var bulb := MeshInstance3D.new()
			bulb.name = "Bulb"
			var b_sp := SphereMesh.new()
			b_sp.radius = 0.10
			b_sp.height = 0.20
			bulb.mesh = b_sp
			bulb.material_override = HarborRouteMaterials.lamp_emissive()
			bulb.position = Vector3(0.70, pole_height - 0.58, 0.0)
			root.add_child(bulb)
			
		_: # "standard"
			var arm := MeshInstance3D.new()
			arm.name = "MastArm"
			var arm_mesh := BoxMesh.new()
			arm_mesh.size = Vector3(arm_length, 0.08, 0.08)
			arm.mesh = arm_mesh
			arm.material_override = base_mat
			arm.position = Vector3(arm_length * 0.5, pole_height, 0.0)
			root.add_child(arm)
			
			var head := MeshInstance3D.new()
			head.name = "LuminaireHead"
			var h_mesh := BoxMesh.new()
			h_mesh.size = Vector3(0.55, 0.12, 0.24)
			head.mesh = h_mesh
			head.material_override = base_mat
			head.position = Vector3(arm_length, pole_height - 0.06, 0.0)
			root.add_child(head)
			
			var lens := MeshInstance3D.new()
			lens.name = "Lens"
			var l_mesh := BoxMesh.new()
			l_mesh.size = Vector3(0.42, 0.02, 0.18)
			lens.mesh = l_mesh
			lens.material_override = HarborRouteMaterials.lamp_emissive()
			lens.position = Vector3(arm_length, pole_height - 0.12, 0.0)
			root.add_child(lens)
	
	# Solid base collision (pedestrians and vehicles cannot pass through pole)
	var body := StaticBody3D.new()
	body.name = "PoleCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 2.4
	col.shape = shape
	col.position = Vector3(0.0, 1.2, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

# ==============================================================================
# Security & Protection Bollards
# ==============================================================================

## Creates a sidewalk protection / anti-ram security bollard.
## Styles:
## - "civic": Fluted dark cast-iron with rounded dome cap.
## - "police": Institutional security post in navy blue with white reflective band.
## - "hazard": High-visibility industrial warning post in safety yellow for corners.
static func create_bollard(style: String = "civic", height: float = 0.88, radius: float = 0.11) -> Node3D:
	var root := Node3D.new()
	root.name = "Bollard_%s" % style
	
	var main_mat: StandardMaterial3D
	match style:
		"police": main_mat = HarborRouteMaterials.police_navy()
		"hazard": main_mat = HarborRouteMaterials.hazard_yellow()
		_: main_mat = HarborRouteMaterials.cast_iron_dark()
	
	# Post shaft
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.08
	cyl.height = height
	shaft.mesh = cyl
	shaft.material_override = main_mat
	shaft.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(shaft)
	
	# Dome cap
	var dome := MeshInstance3D.new()
	dome.name = "Cap"
	var sp := SphereMesh.new()
	sp.radius = radius * 1.02
	sp.height = radius * 1.02
	dome.mesh = sp
	dome.material_override = HarborRouteMaterials.cast_iron_dark() if style == "hazard" else main_mat
	dome.position = Vector3(0.0, height, 0.0)
	root.add_child(dome)
	
	# Reflective accent band
	if style in ["police", "hazard"]:
		var band := MeshInstance3D.new()
		band.name = "ReflectiveBand"
		var band_cyl := CylinderMesh.new()
		band_cyl.top_radius = radius * 1.03
		band_cyl.bottom_radius = radius * 1.03
		band_cyl.height = 0.10
		band.mesh = band_cyl
		band.material_override = HarborRouteMaterials.pavement_white() if style == "police" else HarborRouteMaterials.cast_iron_dark()
		band.position = Vector3(0.0, height * 0.80, 0.0)
		root.add_child(band)
	
	# Base flange ring
	var flange := MeshInstance3D.new()
	flange.name = "BaseFlange"
	var fl_cyl := CylinderMesh.new()
	fl_cyl.top_radius = radius * 1.35
	fl_cyl.bottom_radius = radius * 1.45
	fl_cyl.height = 0.06
	flange.mesh = fl_cyl
	flange.material_override = HarborRouteMaterials.cast_iron_dark()
	flange.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(flange)
	
	# Solid collision
	var body := StaticBody3D.new()
	body.name = "BollardCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.15
	shape.height = height + 0.10
	col.shape = shape
	col.position = Vector3(0.0, shape.height * 0.5, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

# ==============================================================================
# Pedestrian Amenities (Benches, Trash Bins, Bike Racks)
# ==============================================================================

## Creates a wooden slat public bench with cast iron legs and backrest.
static func create_bench(length: float = 2.0) -> Node3D:
	var root := Node3D.new()
	root.name = "PublicBench"
	
	var iron_mat := HarborRouteMaterials.cast_iron_dark()
	var wood_mat := HarborRouteMaterials.bench_wood()
	
	# Cast-iron side legs
	for side in [-1.0, 1.0]:
		var leg_root := Node3D.new()
		leg_root.name = "LegFrame_%s" % ("Left" if side < 0 else "Right")
		leg_root.position = Vector3(side * (length * 0.5 - 0.12), 0.0, 0.0)
		root.add_child(leg_root)
		
		# Vertical leg
		var v_leg := MeshInstance3D.new()
		var vl_box := BoxMesh.new()
		vl_box.size = Vector3(0.06, 0.44, 0.50)
		v_leg.mesh = vl_box
		v_leg.material_override = iron_mat
		v_leg.position = Vector3(0.0, 0.22, 0.0)
		leg_root.add_child(v_leg)
		
		# Backrest upright
		var b_upright := MeshInstance3D.new()
		var bu_box := BoxMesh.new()
		bu_box.size = Vector3(0.06, 0.45, 0.06)
		b_upright.mesh = bu_box
		b_upright.material_override = iron_mat
		b_upright.position = Vector3(0.0, 0.58, -0.22)
		b_upright.rotation_degrees = Vector3(-10, 0, 0)
		leg_root.add_child(b_upright)
	
	# Seat Slats (3 wooden boards)
	var slat_mesh := BoxMesh.new()
	slat_mesh.size = Vector3(length, 0.035, 0.12)
	for z_idx in range(3):
		var slat := MeshInstance3D.new()
		slat.name = "SeatSlat_%d" % z_idx
		slat.mesh = slat_mesh
		slat.material_override = wood_mat
		slat.position = Vector3(0.0, 0.44, -0.14 + (z_idx * 0.14))
		root.add_child(slat)
	
	# Backrest Slats (2 wooden boards)
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(length, 0.11, 0.03)
	for y_idx in range(2):
		var back_slat := MeshInstance3D.new()
		back_slat.name = "BackSlat_%d" % y_idx
		back_slat.mesh = back_mesh
		back_slat.material_override = wood_mat
		back_slat.position = Vector3(0.0, 0.58 + (y_idx * 0.15), -0.23 - (y_idx * 0.03))
		back_slat.rotation_degrees = Vector3(-10, 0, 0)
		root.add_child(back_slat)
	
	# Solid Collision
	var body := StaticBody3D.new()
	body.name = "BenchCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 0.82, 0.65)
	col.shape = shape
	col.position = Vector3(0.0, 0.41, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

## Creates a sidewalk cylindrical waste receptacle.
static func create_trash_bin() -> Node3D:
	var root := Node3D.new()
	root.name = "TrashBin"
	
	# Support post
	var post := MeshInstance3D.new()
	post.name = "SupportPost"
	var p_mesh := CylinderMesh.new()
	p_mesh.top_radius = 0.04
	p_mesh.bottom_radius = 0.05
	p_mesh.height = 0.85
	post.mesh = p_mesh
	post.material_override = HarborRouteMaterials.cast_iron_dark()
	post.position = Vector3(0.0, 0.425, 0.0)
	root.add_child(post)
	
	# Bin body
	var bin := MeshInstance3D.new()
	bin.name = "BinBody"
	var b_mesh := CylinderMesh.new()
	b_mesh.top_radius = 0.22
	b_mesh.bottom_radius = 0.19
	b_mesh.height = 0.60
	bin.mesh = b_mesh
	bin.material_override = HarborRouteMaterials.trash_bin_metal()
	bin.position = Vector3(0.0, 0.55, 0.0)
	root.add_child(bin)
	
	# Rain lid hood
	var hood := MeshInstance3D.new()
	hood.name = "RainHood"
	var h_mesh := SphereMesh.new()
	h_mesh.radius = 0.23
	h_mesh.height = 0.16
	hood.mesh = h_mesh
	hood.material_override = HarborRouteMaterials.cast_iron_dark()
	hood.position = Vector3(0.0, 0.88, 0.0)
	root.add_child(hood)
	
	# Solid Collision
	var body := StaticBody3D.new()
	body.name = "BinCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = 0.95
	col.shape = shape
	col.position = Vector3(0.0, 0.475, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

## Creates a tubular U-loop bicycle parking rack.
static func create_bike_rack(loops: int = 3, loop_spacing: float = 0.90) -> Node3D:
	var root := Node3D.new()
	root.name = "BikeRack"
	
	var steel_mat := HarborRouteMaterials.steel_galvanized()
	var total_span := (loops - 1) * loop_spacing
	var start_x := -total_span * 0.5
	
	for i in range(loops):
		var loop_root := Node3D.new()
		loop_root.name = "Loop_%d" % i
		loop_root.position = Vector3(start_x + (i * loop_spacing), 0.0, 0.0)
		root.add_child(loop_root)
		
		# Inverted U-shape (2 vertical legs + 1 crossbar)
		for leg_x in [-0.28, 0.28]:
			var leg := MeshInstance3D.new()
			var l_mesh := CylinderMesh.new()
			l_mesh.top_radius = 0.035
			l_mesh.bottom_radius = 0.035
			l_mesh.height = 0.80
			leg.mesh = l_mesh
			leg.material_override = steel_mat
			leg.position = Vector3(leg_x, 0.40, 0.0)
			loop_root.add_child(leg)
		
		var top_bar := MeshInstance3D.new()
		var tb_mesh := BoxMesh.new()
		tb_mesh.size = Vector3(0.60, 0.07, 0.07)
		top_bar.mesh = tb_mesh
		top_bar.material_override = steel_mat
		top_bar.position = Vector3(0.0, 0.80, 0.0)
		loop_root.add_child(top_bar)
	
	# Solid Collision
	var body := StaticBody3D.new()
	body.name = "RackCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(total_span + 0.70, 0.85, 0.35)
	col.shape = shape
	col.position = Vector3(0.0, 0.425, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

# ==============================================================================
# Municipal Infrastructure (Hydrants, Drains, Planters)
# ==============================================================================

## Creates an authentic fire hydrant with brass caps and pentagonal top nut.
static func create_fire_hydrant() -> Node3D:
	var root := Node3D.new()
	root.name = "FireHydrant"
	
	var red_mat := HarborRouteMaterials.hydrant_red()
	var brass_mat := HarborRouteMaterials.hydrant_brass()
	
	# Lower body
	var lower := MeshInstance3D.new()
	lower.name = "LowerBarrel"
	var l_cyl := CylinderMesh.new()
	l_cyl.top_radius = 0.13
	l_cyl.bottom_radius = 0.15
	l_cyl.height = 0.45
	lower.mesh = l_cyl
	lower.material_override = red_mat
	lower.position = Vector3(0.0, 0.225, 0.0)
	root.add_child(lower)
	
	# Upper bonnet
	var bonnet := MeshInstance3D.new()
	bonnet.name = "UpperBonnet"
	var b_sph := SphereMesh.new()
	b_sph.radius = 0.14
	b_sph.height = 0.20
	bonnet.mesh = b_sph
	bonnet.material_override = red_mat
	bonnet.position = Vector3(0.0, 0.50, 0.0)
	root.add_child(bonnet)
	
	# Top brass operating nut
	var nut := MeshInstance3D.new()
	nut.name = "OperatingNut"
	var n_cyl := CylinderMesh.new()
	n_cyl.top_radius = 0.04
	n_cyl.bottom_radius = 0.04
	n_cyl.height = 0.08
	nut.mesh = n_cyl
	nut.material_override = brass_mat
	nut.position = Vector3(0.0, 0.62, 0.0)
	root.add_child(nut)
	
	# Dual side hose outlets
	for side in [-1.0, 1.0]:
		var nozzle := MeshInstance3D.new()
		nozzle.name = "HoseOutlet_%s" % ("Left" if side < 0 else "Right")
		var noz_cyl := CylinderMesh.new()
		noz_cyl.top_radius = 0.055
		noz_cyl.bottom_radius = 0.055
		noz_cyl.height = 0.14
		nozzle.mesh = noz_cyl
		nozzle.material_override = brass_mat
		nozzle.position = Vector3(side * 0.16, 0.35, 0.0)
		nozzle.rotation_degrees = Vector3(0, 0, 90)
		root.add_child(nozzle)
	
	# Solid Collision
	var body := StaticBody3D.new()
	body.name = "HydrantCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 0.70
	col.shape = shape
	col.position = Vector3(0.0, 0.35, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

## Creates a cast-iron street storm drain grate set flush with asphalt along the curb line.
static func create_drain_grate(size: Vector2 = Vector2(0.85, 0.45)) -> Node3D:
	var root := Node3D.new()
	root.name = "DrainGrate"
	
	var grate_mat := HarborRouteMaterials.drain_grate()
	
	# Recessed water basin
	var basin := MeshInstance3D.new()
	basin.name = "CatchBasin"
	var b_box := BoxMesh.new()
	b_box.size = Vector3(size.x, 0.02, size.y)
	basin.mesh = b_box
	basin.material_override = grate_mat
	basin.position = Vector3(0.0, 0.01, 0.0)
	root.add_child(basin)
	
	# Parallel iron bars
	var bar_count := 6
	var bar_step := size.x / float(bar_count + 1)
	var bar_start := -size.x * 0.5 + bar_step
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.035, 0.03, size.y * 0.92)
	
	for i in range(bar_count):
		var bar := MeshInstance3D.new()
		bar.name = "IronBar_%d" % i
		bar.mesh = bar_mesh
		bar.material_override = grate_mat
		bar.position = Vector3(bar_start + (i * bar_step), 0.015, 0.0)
		root.add_child(bar)
	
	return root

## Creates a stone-walled rectangular planter box with low coastal shrubs.
static func create_planter_box(size: Vector3 = Vector3(1.8, 0.45, 0.90)) -> Node3D:
	var root := Node3D.new()
	root.name = "PlanterBox"
	
	var stone_mat := HarborRouteMaterials.planter_stone()
	var foliage_mat := HarborRouteMaterials.shrub_foliage()
	
	# Stone outer wall
	var wall := MeshInstance3D.new()
	wall.name = "StoneWall"
	var w_box := BoxMesh.new()
	w_box.size = size
	wall.mesh = w_box
	wall.material_override = stone_mat
	wall.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(wall)
	
	# Soil infill
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	var s_box := BoxMesh.new()
	s_box.size = Vector3(size.x - 0.20, 0.08, size.z - 0.20)
	soil.mesh = s_box
	soil.material_override = HarborRouteMaterials.workshop_apron()
	soil.position = Vector3(0.0, size.y - 0.04, 0.0)
	root.add_child(soil)
	
	# Low trimmed shrubs (2 spheres)
	for side in [-1.0, 1.0]:
		var shrub := MeshInstance3D.new()
		shrub.name = "Shrub_%s" % ("Left" if side < 0 else "Right")
		var sh_mesh := SphereMesh.new()
		sh_mesh.radius = (size.z * 0.42)
		sh_mesh.height = (size.z * 0.65)
		shrub.mesh = sh_mesh
		shrub.material_override = foliage_mat
		shrub.position = Vector3(side * (size.x * 0.24), size.y + 0.15, 0.0)
		root.add_child(shrub)
	
	# Solid Collision
	var body := StaticBody3D.new()
	body.name = "PlanterCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(col)
	root.add_child(body)
	
	return root

## Creates a painted pedestrian crosswalk zebra pattern flush to asphalt.
static func create_crosswalk_stripes(width: float = 3.6, length: float = 7.5, stripe_count: int = 6) -> Node3D:
	var root := Node3D.new()
	root.name = "CrosswalkStripes"
	
	var white_mat := HarborRouteMaterials.pavement_white()
	var stripe_len := length / float(stripe_count)
	var bar_len := stripe_len * 0.55
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(width, 0.01, bar_len)
	
	var start_z := -length * 0.5 + (stripe_len * 0.5)
	for i in range(stripe_count):
		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe_%d" % i
		stripe.mesh = bar_mesh
		stripe.material_override = white_mat
		stripe.position = Vector3(0.0, 0.005, start_z + (i * stripe_len))
		root.add_child(stripe)
	
	return root
