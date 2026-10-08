extends "res://world/places/NativePlace.gd"
## Fagulha uses normal room admission, rewards, residents and save restoration.
const ID := "harbor_arcade"
const EXTERIOR := Vector3(80, .12, 8.75)
const STATIONS := {
	"arcade_pinball": Vector3(-4.25, 0, -1.85),
	"arcade_blocks": Vector3(-1.45, 0, -2.1),
	"arcade_racer": Vector3(1.4, 0, -1.28),
	"arcade_fighter": Vector3(4.05, 0, -2.1),
}

static func definition_data() -> Dictionary:
	var reward := {"id":"fagulha_first_aid","kind":"item","item":"first_aid","amount":1,"local_position":Vector3(-4.1,0,3.5)}
	return {
		"id":ID,"original_name":"Fagulha","region":"harbor","source_id":"fagulha",
		"model":"res://world/places/arcade/ArcadeInterior.gd",
		"exterior_position":EXTERIOR,"entry_position":EXTERIOR+Vector3(0,0,6.3),
		"return_position":EXTERIOR+Vector3(0,0,7.05),
		"spawn":Vector3(0,0,3.5),"exit":Vector3(0,0,4.5),"size":Vector2(12,10),
		"camera_target":Vector3(0,.65,-.15),"camera_size":14.5,"variant":0,
		"service":"arcade","reward":reward,"rewards":[reward],
		"npc_model":"","npc_point":Vector3.ZERO,"integration_status":"native",
		"npcs":[
			{"id":"fagulha_lia","name":"Lia","model":"res://world/places/arcade/ArcadePlayerModel.gd",
				"appearance":{"player_variant":0},"local_position":Vector3(3.95,0,.35)},
			{"id":"fagulha_ivo","name":"Ivo","model":"res://world/places/arcade/ArcadePlayerModel.gd",
				"appearance":{"player_variant":1},"local_position":Vector3(3.95,0,2.9)},
		],
	}

func _ready() -> void:
	super._ready()
	for station in STATIONS: interaction_points[station] = to_global(STATIONS[station])
	interaction_points.service = interaction_points.arcade_pinball
	# The front wall remains physically full height even where its visual is cut.
	for mesh in model.get_children():
		if mesh is MeshInstance3D and str(mesh.get_meta("interior_solid_id", "")).begins_with("SouthWall"):
			mesh.mesh = mesh.mesh.duplicate()
			mesh.mesh.size.y = .28
			mesh.position.y = .14

func on_session_entered(owner_session) -> void:
	for actor in owner_session.room_npcs:
		if not is_instance_valid(actor): continue
		if str(actor.get_meta("interior_npc_id", "")).begins_with("fagulha_"):
			# Actor's native forward is -Z; the resident rig turns PI internally.
			actor.visual.rotation.y = -PI * .5
