extends "res://world/places/NativePlace.gd"
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")

static func definition_data() -> Dictionary:
	return {"id":LAYOUT.HAUNTED_ID,"original_name":"Umbra","region":"harbor",
		"source_id":"amusement_park_umbra","model":"res://world/places/amusement_park/HauntedHouseInterior.gd",
		"exterior_position":LAYOUT.HAUNTED_CENTER,"entry_position":LAYOUT.HAUNTED_ENTRY,
		"return_position":LAYOUT.HAUNTED_ENTRY+Vector3(0,0,1.3),
		"spawn":LAYOUT.HOUSE_SPAWN,"exit":LAYOUT.HOUSE_EXIT,"size":LAYOUT.HOUSE_SIZE,
		"camera_target":Vector3(0,.7,0),"camera_size":17.0,"variant":0,"service":"amusement",
		"reward":{},"rewards":[],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,
		"integration_status":"native","amusement_park":true}

func _ready() -> void:
	super._ready()
	# Esta atração usa perspectiva em primeira pessoa. Restaura a arte da parede da frente
	# depois do corte ortográfico do NativePlace, mantendo os sólidos inteiros originais.
	for side in [-1,1]:
		var wall := model.get_node_or_null("FrontWall%d"%side) as MeshInstance3D
		if wall != null:
			wall.mesh.size.y = 3.3
			wall.position.y = 1.65
	var door := model.get_node_or_null("ExitDoorPanel") as MeshInstance3D
	if door != null:
		door.mesh.size.y = 2.7
		door.position.y = 1.35

func _box_solid(id: String, bounds: AABB, obstacle := true) -> void:
	# A extensão cresce para o norte; as coordenadas originais de entrada/save não mudam.
	if id == "Floor": bounds = AABB(Vector3(-9,-.22,-27.5),Vector3(18,.2,35))
	super._box_solid(id,bounds,obstacle)
