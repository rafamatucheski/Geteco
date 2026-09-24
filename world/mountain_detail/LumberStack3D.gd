extends Node3D
class_name LumberStack3D

## High-detail 3D model of stacked, sawn lumber boards bound with galvanized steel packing bands.
## Reconstructs the 2D outlines authored in SawmillYardDetails.gd into native 3D metric geometry.
## Layer 1 native StaticBody3D collision.

@export var stack_length: float = 3.375 # 54 px / 16
@export var stack_width: float = 0.375   # 6 px / 16
@export var stack_height: float = 0.65
@export var board_rows: int = 5

func _ready() -> void:
	build()

func build() -> void:
	for child in get_children():
		child.queue_free()
	
	var board_mat := MountainMaterials.wood_board()
	var aged_mat := MountainMaterials.wood_board_aged()
	var end_mat := MountainMaterials.wood_cut_end()
	var strap_mat := MountainMaterials.metal_strap()
	
	var row_h := stack_height / float(board_rows)
	var spacer_h := 0.025
	
	# Solid StaticBody3D
	var body := StaticBody3D.new()
	body.name = "LumberStackCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(stack_length, stack_height, stack_width)
	col.shape = box_shape
	col.position = Vector3(stack_length * 0.5, stack_height * 0.5, stack_width * 0.5)
	body.add_child(col)
	add_child(body)
	
	# Base skids (dunnage lifting wood off moist snow/dirt)
	for sx in [0.25, stack_length * 0.5, stack_length - 0.25]:
		_add_box("Skid", Vector3(sx, 0.04, stack_width * 0.5), Vector3(0.10, 0.08, stack_width + 0.04), aged_mat)
	
	# Stacked layers of boards
	for r in board_rows:
		var by := 0.08 + float(r) * row_h + row_h * 0.5
		var mat := board_mat if r % 2 == 0 else aged_mat
		_add_box("BoardCourse_%d" % r, Vector3(stack_length * 0.5, by, stack_width * 0.5), Vector3(stack_length - 0.02, row_h - spacer_h, stack_width), mat)
		
		# Sawn cut end caps
		for side in [-1.0, 1.0]:
			var ex: float = stack_length * 0.5 + side * (stack_length * 0.5 - 0.005)
			_add_box("EndCap", Vector3(ex, by, stack_width * 0.5), Vector3(0.01, row_h - spacer_h, stack_width * 0.96), end_mat)
		
		# Wooden stickers/spacers between courses for airflow
		if r < board_rows - 1:
			var sy := by + row_h * 0.5 + spacer_h * 0.5
			for sx in [0.35, stack_length * 0.5, stack_length - 0.35]:
				_add_box("Sticker", Vector3(sx, sy, stack_width * 0.5), Vector3(0.05, spacer_h, stack_width + 0.02), aged_mat)
	
	# Steel packing straps wrapping tightly around the stack (offsets matching 10px and 44px in V1)
	for strap_x in [stack_length * 0.185, stack_length * 0.815]:
		# Top strap
		_add_box("StrapTop", Vector3(strap_x, stack_height + 0.08, stack_width * 0.5), Vector3(0.03, 0.015, stack_width + 0.01), strap_mat)
		# Front/back vertical bands
		_add_box("StrapFront", Vector3(strap_x, stack_height * 0.5 + 0.04, stack_width + 0.005), Vector3(0.03, stack_height, 0.01), strap_mat)
		_add_box("StrapBack", Vector3(strap_x, stack_height * 0.5 + 0.04, -0.005), Vector3(0.03, stack_height, 0.01), strap_mat)
	
	# Thin snow accumulation on top
	_add_box("SnowCap", Vector3(stack_length * 0.5, stack_height + 0.09, stack_width * 0.5), Vector3(stack_length * 0.95, 0.02, stack_width * 0.90), MountainMaterials.snow_fresh())

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
