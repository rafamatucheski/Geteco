extends "res://assets/CivilianModel.gd"
## A static display built from the same tailored body as living pedestrians.
## No physics, idle animation or per-frame work is needed for shop furniture.

static func create(id: String, coat: Color, style: int = 0) -> Node3D:
	var display = load("res://world/places/ShopMannequin.gd").new()
	display.name = id
	display.appearance_locked = true
	display.appearance_variant = 8100 + style
	display.coat_color = coat
	display.pants_color = Color("323d43")
	display.wardrobe_overrides = {"female": style == 2, "build": 0, "height": 1.0,
		"top": 9 if style == 2 else 2, "bottom": 0, "shoe": 1, "hat": 0, "hair": 0,
		"beard": 0, "glasses": false, "backpack": false, "bag": 0,
		"skin": Color("bdb9ad"), "hair_color": Color("bdb9ad"),
		"inner": Color("e1d3b6"), "accent": Color("8d7450"), "shoe_color": Color("35322f")}
	return display

func _ready() -> void:
	super._ready()
	# _ready builds and poses the rig synchronously, before the room collects
	# its solid volumes. Preserve that pose even while the store is occupied.
	set_process(false)
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("interior_solid_id", StringName(name))
