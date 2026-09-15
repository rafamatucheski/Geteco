extends "res://legacy/city_demo/scenes/pickups/BodyArmorPickup.gd"
var room: Node2D
var visual: Node3D

func _ready() -> void:
	super._ready()
	collision_mask=2|4

func _ensure_art() -> void:
	_art_root=Node2D.new()
	add_child(_art_root)
	visual=Node3D.new()
	visual.name="DroppedBallisticVest"
	var part=preload("res://world/shared/pedestrians/CitizenDetails.gd")
	var fabric:=Color("3e4845")
	part.piece(visual,Vector3(.40,.065,.43),Vector3.ZERO,fabric)
	part.piece(visual,Vector3(.31,.025,.29),Vector3(0,.043,-.025),Color("525d56"))
	for side in [-1,1]:
		part.piece(visual,Vector3(.095,.045,.15),Vector3(side*.15,0,-.27),fabric)
		part.piece(visual,Vector3(.065,.016,.033),Vector3(side*.15,.032,-.26),Color("a19f89"))
		part.piece(visual,Vector3(.125,.055,.11),Vector3(side*.082,.05,.115),fabric.darkened(.12))
		part.piece(visual,Vector3(.12,.008,.025),Vector3(side*.082,.082,.09),Color("616a60"))
	var materials:Dictionary={}
	for mesh in visual.get_children():
		var color:Color=mesh.material_override.albedo_color
		if materials.has(color): mesh.material_override=materials[color]
		else: materials[color]=mesh.material_override
	visual.rotation.y=-.35
	preload("res://world/harbor/events/BankFloorItem.gd").place(room,visual,global_position)
	add_to_group("bank_guard_armor")

func _process(_delta: float) -> void: pass
func _draw() -> void: pass

func _take(player: Node) -> void:
	if _consumed or not player.has_method("add_armor"): return
	visual.hide()
	super._take(player)

func _exit_tree() -> void:
	if is_instance_valid(visual): visual.queue_free()
