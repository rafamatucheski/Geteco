extends Node3D
## Architecture in the facade's actual metre footprint. Furnishings are batched
## separately; every inhabited storey shares the main world and native depth.
const MATERIALS = preload("res://world/places/ShopInteriorMaterials.gd")
const DRESSING = preload("res://world/places/harbor_buildings/HarborBuildingDressing.gd")
const CONTENT = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
# Keep shell outer faces behind the resident facade, without moving inner faces.
const EXTERIOR_CLEARANCE := .02
var definition: Dictionary = {}
var variant := 0
var floor_index := 0
var width := 14.0
var depth := 11.0
var serial := 0
var content: Dictionary = {}

func create_reward_art(item: Dictionary) -> Node3D:
	return preload("res://world/places/harbor_buildings/HarborBuildingRewardArt.gd").build(item)

func _ready() -> void:
	if get_parent() != null and "definition" in get_parent():
		definition = get_parent().definition
	width = definition.get("size", Vector2(width, depth)).x
	depth = definition.get("size", Vector2(width, depth)).y
	floor_index = int(definition.get("building_floor_index", 0))
	var stage_started := STALL_WORK.begin()
	_shell()
	if stage_started != 0:
		STALL_WORK.finish("building.interior.shell", stage_started, {"place":definition.id})
	stage_started = STALL_WORK.begin()
	_stairs()
	if stage_started != 0:
		STALL_WORK.finish("building.interior.stairs", stage_started, {"place":definition.id})
	stage_started = STALL_WORK.begin()
	content = DRESSING.populate(self, definition, floor_index)
	if stage_started != 0:
		STALL_WORK.finish("building.interior.dressing", stage_started, {"place":definition.id})
	set_process(false)
	set_physics_process(false)

func box(at: Vector3, size: Vector3, color: String, solid: String = "", kind: String = "wood") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	serial += 1
	node.name = (solid if not solid.is_empty() else "Detail") + str(serial)
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = MATERIALS.material(kind, Color(color))
	if not solid.is_empty(): node.set_meta("interior_solid_id", solid)
	add_child(node)
	return node

func _shell() -> void:
	var entry_x: float = definition.get("entrance_local",Vector3.ZERO).x
	var residential: bool = str(definition.get("archetype", "")) in ["residential", "apartments", "residence", "brownstone"]
	# Parede e piso seguem a paleta do prédio/andar (HarborBuildingContent), em
	# vez de cinco rebocos fixos e um único piso por família.
	var palette: Dictionary = CONTENT.palette_for(definition, floor_index, CONTENT.family(definition)) if definition.has("floor_count") else {}
	var plaster: String = str(palette.get("wall", "b7b4a6"))
	var floor_color: String = str(palette.get("floor", "8b6646" if residential else "7e817b"))
	var floor_kind := "wood" if residential or str(definition.get("archetype", "")) == "hospitality" else "stone"
	box(Vector3(0,-.045,0),Vector3(width-EXTERIOR_CLEARANCE*2,.05,depth-EXTERIOR_CLEARANCE*2),floor_color,"",floor_kind)
	box(Vector3(0,1.35,-depth*.5+.12+EXTERIOR_CLEARANCE*.5),Vector3(width-EXTERIOR_CLEARANCE*2,2.7,.24-EXTERIOR_CLEARANCE),plaster,"BackWall","stone")
	for side in [-1,1]:
		# Low camera-facing edges preserve true depth and unbroken collision.
		box(Vector3(side*(width*.5-.12-EXTERIOR_CLEARANCE*.5),.55,0),Vector3(.24-EXTERIOR_CLEARANCE,1.1,depth-EXTERIOR_CLEARANCE*2),plaster,"SideWall%d"%side,"stone")
		box(Vector3(side*(width*.5-.26),.09,0),Vector3(.06,.18,depth-.4),"534c40")
		var span: float = width*.5
		var center_x: float = float(side)*width*.25
		if floor_index == 0:
			span = width*.5+float(side)*(-entry_x)-1.2
			center_x = (float(side)*width*.5+entry_x+float(side)*1.2)*.5
		box(Vector3(center_x-float(side)*EXTERIOR_CLEARANCE*.5,.52,depth*.5-.12-EXTERIOR_CLEARANCE*.5),Vector3(span-EXTERIOR_CLEARANCE,1.04,.24-EXTERIOR_CLEARANCE),plaster,"FrontWall%d"%side,"stone")
		var window_x: float = float(side)*width*.27
		var window_width := minf(1.8,width*.24)
		box(Vector3(window_x,1.85,-depth*.5+.25),Vector3(window_width,1.1,.06),"364b50","","metal")
		for edge in [-1,1]:
			box(Vector3(window_x+edge*(window_width*.5+.04),1.85,-depth*.5+.30),Vector3(.08,1.26,.11),"554d40")
		box(Vector3(window_x,1.85,-depth*.5+.33),Vector3(.055,1.12,.09),"88755c")
		box(Vector3(window_x,1.24,-depth*.5+.35),Vector3(window_width+.2,.1,.28),"88755c")
	# Thin rugs remain walkable. Floor trim communicates circulation without
	# descriptive labels or the orange ground entry marker.
	box(Vector3(entry_x,.005,depth*.5-1.2),Vector3(1.75,.016,.8),"494e45","","cloth")
	for side in [-1,1]:
		box(Vector3(side*.97,-.012,0),Vector3(.035,.025,depth-.5),"b5a384","","stone")

func _stairs() -> void:
	var x := -width*.5+1.45
	var stair_width := minf(1.75,width*.5-1.05)
	for step in 7:
		var h := .16*(step+1)
		box(Vector3(x,h*.5,.2-step*.25),Vector3(stair_width,h,.26),"726e64","StairFlight","stone")
		box(Vector3(x,h+.01,.31-step*.25),Vector3(stair_width+.015,.02,.045),"ada89b")
	for side in [-1,1]:
		box(Vector3(x+side*(stair_width*.5+.045),.67,-.55),Vector3(.065,1.34,1.85),"474b47","StairRail%d"%side,"metal")
	box(Vector3(x,1.28,-1.6),Vector3(stair_width+.12,2.56,.12),"373e3b","StairBack","stone")
	# The destination is operated at the landing. The visible continuation is
	# solid so walking cannot clip through a flight during floor preparation.
	var plate := Label3D.new()
	plate.name = "FunctionalFloorNumber"
	plate.text = "T" if floor_index == 0 else str(floor_index)
	plate.position = Vector3(x,1.85,-1.515)
	plate.font_size = 36
	plate.pixel_size = .009
	plate.modulate = Color("ddd5bb")
	add_child(plate)
