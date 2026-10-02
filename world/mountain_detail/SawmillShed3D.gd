extends Node3D
class_name SawmillShed3D

## Open-sided timber cutting shed for the Mountain Pass sawmill.
## Features heavy round log posts, king-post timber roof trusses, circular saw table with steel blade,
## log roller conveyor track, carpentry workbenches, and authentic logging tool racks.
## Maintains clear, unblocked pedestrian/material passageways through the central work corridor.
## Native StaticBody3D collision on layer 1, mask 0.

@export var shed_width: float = 7.2
@export var shed_depth: float = 5.4
@export var shed_height: float = 4.0

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var beam_mat := MountainMaterials.wood_beam()
	var log_mat := MountainMaterials.wood_log()
	var board_mat := MountainMaterials.wood_board()
	var roof_mat := MountainMaterials.wood_shingle()
	var snow_mat := MountainMaterials.snow_fresh()
	var iron_mat := MountainMaterials.metal_iron()
	var steel_mat := MountainMaterials.metal_blade()
	var stone_mat := MountainMaterials.stone_river()
	
	var half_w := shed_width * 0.5
	var half_d := shed_depth * 0.5
	var post_h := 3.2
	
	# Solid StaticBody3D for structural posts and equipment
	var body := StaticBody3D.new()
	body.name = "SawmillShedCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	
	# 1. Six Heavy Timber Log Posts with Stone Plinths (±half_w, center 0, ±half_d)
	for x in [-half_w + 0.35, 0.0, half_w - 0.35]:
		for z in [-half_d + 0.35, half_d - 0.35]:
			# Stone foundation pad
			_add_box("Plinth", Vector3(x, 0.10, z), Vector3(0.46, 0.20, 0.46), stone_mat)
			# Vertical log column
			_add_cylinder("Post", Vector3(x, post_h * 0.5 + 0.20, z), 0.16, post_h, log_mat)
			# Collision shape for each post
			var col := CollisionShape3D.new()
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = 0.22
			cyl_shape.height = post_h + 0.2
			col.shape = cyl_shape
			col.position = Vector3(x, (post_h + 0.2) * 0.5, z)
			body.add_child(col)
	
	# 2. Longitudinal & Transverse Header Beams
	var header_y := post_h + 0.20
	# Front and rear long beams
	_add_box("HeaderFront", Vector3(0, header_y, half_d - 0.35), Vector3(shed_width, 0.22, 0.22), beam_mat)
	_add_box("HeaderRear", Vector3(0, header_y, -half_d + 0.35), Vector3(shed_width, 0.22, 0.22), beam_mat)
	# Transverse cross beams
	for x in [-half_w + 0.35, 0.0, half_w - 0.35]:
		_add_box("CrossTie", Vector3(x, header_y, 0), Vector3(0.20, 0.22, shed_depth - 0.70), beam_mat)
		# King-post roof truss
		_build_roof_truss(x, header_y, shed_depth - 0.70, beam_mat)
	
	# 3. Pitched Gable Roof with Wood Shakes and Thick Snow Layer
	var ridge_h := 1.25
	var ridge_y := header_y + ridge_h
	var roof_overhang_w := shed_width + 0.8
	var roof_overhang_d := shed_depth + 0.8
	var pitch := 0.42 # ~24 degrees
	
	for side in [-1.0, 1.0]:
		var panel_w := (roof_overhang_d * 0.55)
		var offset_z: float = side * (roof_overhang_d * 0.26)
		var roof_y := header_y + ridge_h * 0.5 + 0.10
		
		# Timber roof deck
		var deck := _add_box("RoofDeck", Vector3(0, roof_y, offset_z), Vector3(roof_overhang_w, 0.10, panel_w), roof_mat)
		deck.rotation.x = -side * pitch
		
		# Snow accumulation on roof
		var snow := _add_box("RoofSnow", Vector3(0, roof_y + 0.07, offset_z), Vector3(roof_overhang_w + 0.08, 0.12, panel_w + 0.06), snow_mat)
		snow.rotation.x = -side * pitch
	
	# Ridge cap
	_add_box("RidgeCap", Vector3(0, ridge_y + 0.12, 0), Vector3(roof_overhang_w + 0.10, 0.14, 0.32), snow_mat)
	
	# 4. Circular Saw Table & Equipment (Left Bay: x around -2.0)
	var saw_x := -half_w * 0.52
	var saw_h := 0.90
	var saw_len := 3.2
	
	# Solid collision for saw table
	var saw_col := CollisionShape3D.new()
	var saw_shape := BoxShape3D.new()
	saw_shape.size = Vector3(1.10, saw_h, saw_len)
	saw_col.shape = saw_shape
	saw_col.position = Vector3(saw_x, saw_h * 0.5, 0)
	body.add_child(saw_col)
	
	# Heavy timber table base
	_add_box("SawBenchTop", Vector3(saw_x, saw_h - 0.06, 0), Vector3(1.05, 0.12, saw_len), beam_mat)
	for sz in [-saw_len * 0.4, 0.0, saw_len * 0.4]:
		_add_box("SawBenchLeg", Vector3(saw_x, (saw_h - 0.12) * 0.5, sz), Vector3(0.95, saw_h - 0.12, 0.14), beam_mat)
	
	# Steel roller guides along conveyor
	for r in 6:
		var rz: float = -saw_len * 0.42 + float(r) * (saw_len * 0.84 / 5.0)
		_add_cylinder("ConveyorRoller", Vector3(saw_x, saw_h + 0.04, rz), 0.045, 0.82, steel_mat, Vector3(0, 0, 90))
	
	# Circular saw blade (vertical steel disc) protruding through center of table
	var saw_blade_pos := Vector3(saw_x + 0.15, saw_h + 0.32, 0.2)
	_add_cylinder("CircularSawBlade", saw_blade_pos, 0.48, 0.02, steel_mat, Vector3(0, 0, 90))
	# Blade arbor and drive belt shroud
	_add_box("SawShroud", saw_blade_pos + Vector3(0, 0.12, 0), Vector3(0.14, 0.36, 0.70), iron_mat)
	_add_box("DriveMotor", Vector3(saw_x - 0.30, 0.35, 0.2), Vector3(0.38, 0.45, 0.52), iron_mat)
	
	# 5. Carpentry Workbench & Tool Rack (Right Bay: x around +2.3)
	var bench_x := half_w * 0.58
	var bench_h := 0.88
	var bench_len := 2.6
	
	# Solid collision for workbench
	var bench_col := CollisionShape3D.new()
	var bench_shape := BoxShape3D.new()
	bench_shape.size = Vector3(0.85, bench_h, bench_len)
	bench_col.shape = bench_shape
	bench_col.position = Vector3(bench_x, bench_h * 0.5, -half_d * 0.45)
	body.add_child(bench_col)
	
	# Workbench top and sturdy legs
	_add_box("WorkBenchTop", Vector3(bench_x, bench_h - 0.05, -half_d * 0.45), Vector3(0.80, 0.10, bench_len), board_mat)
	for bz in [-half_d * 0.45 - bench_len * 0.4, -half_d * 0.45 + bench_len * 0.4]:
		_add_box("WorkBenchLeg", Vector3(bench_x, (bench_h - 0.10) * 0.5, bz), Vector3(0.72, bench_h - 0.10, 0.12), beam_mat)
	
	# Cast iron bench vise on edge of workbench
	_add_box("BenchVise", Vector3(bench_x - 0.38, bench_h + 0.10, -half_d * 0.45 - 0.6), Vector3(0.18, 0.22, 0.25), iron_mat)
	
	# Two-man crosscut saw (traçadeira) hanging on rear cross beam
	var saw_pos := Vector3(0.8, header_y - 0.30, -half_d + 0.38)
	_add_box("CrosscutBlade", saw_pos, Vector3(1.75, 0.14, 0.015), steel_mat)
	# Wooden handles on both ends
	for h_end in [-0.85, 0.85]:
		_add_box("SawHandle", saw_pos + Vector3(h_end, 0, 0.02), Vector3(0.04, 0.28, 0.04), MountainMaterials.wood_pole())
	
	# Felling axes hanging on post
	var post_tool_x := half_w - 0.35
	_add_box("AxeHanging", Vector3(post_tool_x - 0.18, 1.6, -half_d + 0.35), Vector3(0.03, 0.85, 0.03), MountainMaterials.wood_pole())
	_add_box("AxeHeadHanging", Vector3(post_tool_x - 0.18, 1.95, -half_d + 0.35), Vector3(0.04, 0.16, 0.22), iron_mat)

func _build_roof_truss(x: float, y: float, depth: float, mat: Material) -> void:
	var half_d := depth * 0.5

	# King post in center
	_add_box("KingPost", Vector3(x, y + 0.60, 0), Vector3(0.14, 1.20, 0.14), mat)
	# Rafters from center apex to eaves
	for side in [-1.0, 1.0]:
		var rafter_z: float = side * half_d * 0.5
		var rafter := _add_box("Rafter", Vector3(x, y + 0.60, rafter_z), Vector3(0.12, 0.14, half_d * 1.15), mat)
		rafter.rotation.x = -side * 0.42

func _add_box(node_name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi

func _add_cylinder(node_name: String, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi
