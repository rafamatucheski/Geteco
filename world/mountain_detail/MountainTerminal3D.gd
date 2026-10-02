extends Node3D
class_name MountainTerminal3D

## High-detail 3D model of the Mountain Transit Terminal ("Terminal da Serra") and Coach Berth 01.
## Reconstructs the station office, passenger shelter canopy, waiting benches, and platform markings
## from MountainTransitArchitecture3D.gd into native 3D metric geometry.
## Strictly adheres to AGENTS.md: proper name signage, zero SubViewports, layer 1 StaticBody3D.

@export var terminal_size: Vector2 = Vector2(7.8, 3.5) # ~125 x 55 px
@export var terminal_height: float = 3.6

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var wall_mat := MountainMaterials.wood_board_aged()
	var trim_mat := MountainMaterials.wood_beam()
	var stone_mat := MountainMaterials.stone_river()
	var roof_mat := MountainMaterials.wood_shingle()
	var snow_mat := MountainMaterials.snow_fresh()
	var glass_mat := MountainMaterials.glass_warm()
	MountainMaterials.wood_bench()
	
	var half_w := terminal_size.x * 0.5
	var half_d := terminal_size.y * 0.5
	var body_h := 2.7
	
	# Solid StaticBody3D for terminal office body
	var body := StaticBody3D.new()
	body.name = "TerminalCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(terminal_size.x, body_h, terminal_size.y)
	col.shape = box_shape
	col.position = Vector3(0, body_h * 0.5 + 0.15, 0)
	body.add_child(col)
	add_child(body)
	
	# 1. Foundation Stone Plinth
	_add_box("FoundationPlinth", Vector3(0, 0.10, 0), Vector3(terminal_size.x + 0.35, 0.20, terminal_size.y + 0.35), stone_mat)
	
	# 2. Main Timber Office Body
	_add_box("OfficeWalls", Vector3(0, body_h * 0.5 + 0.20, 0), Vector3(terminal_size.x, body_h, terminal_size.y), wall_mat)
	
	# Corner pillars
	for cx in [-half_w, half_w]:
		_add_box("Pillar", Vector3(cx, body_h * 0.5 + 0.20, half_d), Vector3(0.18, body_h, 0.18), trim_mat)
		_add_box("PillarRear", Vector3(cx, body_h * 0.5 + 0.20, -half_d), Vector3(0.18, body_h, 0.18), trim_mat)
	
	# 3. Office Door and Ticket Window (+Z)
	var door_w := 1.10
	var door_h := 2.20
	_add_box("DoorFrame", Vector3(-half_w * 0.35, door_h * 0.5 + 0.20, half_d + 0.02), Vector3(door_w + 0.16, door_h + 0.10, 0.08), trim_mat)
	_add_box("DoorWood", Vector3(-half_w * 0.35, door_h * 0.5 + 0.20, half_d + 0.04), Vector3(door_w, door_h, 0.06), trim_mat)
	
	# Ticket/waiting window
	var win_x := half_w * 0.45
	var win_y := 1.5 + 0.20
	_add_box("TicketFrame", Vector3(win_x, win_y, half_d + 0.02), Vector3(1.8, 1.25, 0.08), trim_mat)
	var win_glass := _add_box("TicketGlass", Vector3(win_x, win_y, half_d + 0.04), Vector3(1.6, 1.05, 0.02), glass_mat)
	win_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 4. Extended Passenger Waiting Canopy (Overhang toward +Z by ~2.2m)
	var canopy_d := 2.3
	var canopy_w := terminal_size.x + 0.6
	var canopy_y := body_h + 0.10
	var canopy := _add_box("WaitingCanopy", Vector3(0, canopy_y, half_d + canopy_d * 0.48), Vector3(canopy_w, 0.12, canopy_d), roof_mat)
	canopy.rotation.x = 0.08
	var canopy_snow := _add_box("CanopySnow", Vector3(0, canopy_y + 0.06, half_d + canopy_d * 0.48), Vector3(canopy_w + 0.04, 0.08, canopy_d + 0.04), snow_mat)
	canopy_snow.rotation.x = 0.08
	
	# Front porch support posts with collision
	for px in [-half_w * 0.85, half_w * 0.85]:
		var post_pos := Vector3(px, canopy_y * 0.5, half_d + canopy_d * 0.90)
		_add_box("CanopyPost", post_pos, Vector3(0.16, canopy_y, 0.16), trim_mat)
		var pcol := CollisionShape3D.new()
		var pbox := BoxShape3D.new()
		pbox.size = Vector3(0.20, canopy_y, 0.20)
		pcol.shape = pbox
		pcol.position = post_pos
		body.add_child(pcol)
	
	# 5. Waiting Benches under the canopy
	for bx in [-half_w * 0.5, half_w * 0.5]:
		var b_pos := Vector3(bx, 0.45, half_d + canopy_d * 0.45)
		_build_bench(b_pos, 1.7)
	
	# 6. Facade Signage: "Terminal da Serra"
	var sign_y := body_h + 0.45
	_add_box("TerminalSignBoard", Vector3(0, sign_y, half_d + 0.12), Vector3(minf(terminal_size.x * 0.6, 4.8), 0.60, 0.08), MountainMaterials.sign_timber())
	var label := Label3D.new()
	label.name = "TerminalSignLabel"
	label.text = "Terminal da Serra"
	label.font_size = 44
	label.pixel_size = 0.007
	label.outline_size = 0
	label.modulate = Color("#f4ede0")
	label.position = Vector3(0, sign_y, half_d + 0.18)
	add_child(label)
	
	# 7. Main Pitched Roof with Snow
	var pitch := 0.40
	var roof_overhang_w := terminal_size.x + 0.8
	var roof_overhang_d := terminal_size.y + 0.8
	var ridge_y := body_h + 0.20 + 1.15
	
	for side in [-1.0, 1.0]:
		var panel_w := roof_overhang_d * 0.56
		var offset_z: float = side * (roof_overhang_d * 0.26)
		var roof_y := body_h + 0.20 + 0.55
		
		var deck := _add_box("RoofDeck", Vector3(0, roof_y, offset_z), Vector3(roof_overhang_w, 0.12, panel_w), roof_mat)
		deck.rotation.x = -side * pitch
		
		var snow := _add_box("RoofSnow", Vector3(0, roof_y + 0.08, offset_z), Vector3(roof_overhang_w + 0.06, 0.14, panel_w + 0.04), snow_mat)
		snow.rotation.x = -side * pitch
	
	_add_box("RidgeCap", Vector3(0, ridge_y + 0.10, 0), Vector3(roof_overhang_w + 0.08, 0.14, 0.35), snow_mat)
	
	# 8. Coach Berth 01 Markings (Positioned in front of the terminal at Z offset -5.5m)
	_build_berth_markings()

func _build_bench(pos: Vector3, width: float) -> void:
	var bench_mat := MountainMaterials.wood_bench()
	var trim_mat := MountainMaterials.wood_beam()
	var half_bw := width * 0.5
	# Seat slab
	_add_box("BenchSeat", pos, Vector3(width, 0.08, 0.45), bench_mat)
	# Backrest
	_add_box("BenchBack", pos + Vector3(0, 0.30, -0.20), Vector3(width, 0.35, 0.06), bench_mat)
	# Legs
	for side in [-1.0, 1.0]:
		_add_box("BenchLeg", pos + Vector3(side * (half_bw - 0.15), -0.22, 0), Vector3(0.08, 0.44, 0.40), trim_mat)

func _build_berth_markings() -> void:
	# Coach berth located in front of terminal: width ~10.5m x 2.8m
	var berth_center := Vector3(0.5, 0.02, -7.5)
	var gold_mat := MountainMaterials.metal_brass()
	
	# Yellow/Gold boundary box lines on pavement
	var berth_w := 10.5
	var berth_d := 2.8
	# Side lines
	for side in [-1.0, 1.0]:
		_add_box("BerthLineX", berth_center + Vector3(0, 0, side * berth_d * 0.5), Vector3(berth_w, 0.005, 0.12), gold_mat)
	# End lines
	for side in [-1.0, 1.0]:
		_add_box("BerthLineZ", berth_center + Vector3(side * berth_w * 0.5, 0, 0), Vector3(0.12, 0.005, berth_d), gold_mat)
	
	# "01" Berth Designation Label on Ground
	var berth_label := Label3D.new()
	berth_label.name = "Berth01Text"
	berth_label.text = "01"
	berth_label.font_size = 56
	berth_label.pixel_size = 0.010
	berth_label.outline_size = 0
	berth_label.modulate = Color("#e5ba55")
	berth_label.position = berth_center + Vector3(berth_w * 0.35, 0.015, 0)
	berth_label.rotation.x = -PI * 0.5
	add_child(berth_label)

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
