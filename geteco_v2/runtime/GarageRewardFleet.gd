extends RefCounted
const ID := "cobra_boss_ironback"
# ironback.scn is the same untouched BossMuscleModel snapshot exported by
# tools/bake_vehicles.gd; this reward has its own ID and HarborBossMuscle rules.
const SPEC := {"id":ID,"label":"Ironback V8","scene":"res://assets/garage_rewards/ironback.scn",
	"model_class":"res://prototypes/living_cast/BossMuscleModel.gd","source_controller":"prototypes/living_cast/HarborBossMuscle.gd",
	"bounds_size":[2.23600006103516,1.34099853038788,5.06999969482422],"bounds_center":[0.0,.675499320030212,.00499987602233887],
	"durability":100,"max_speed":560.0,"acceleration":1200.0,"braking":1500.0,"turn_speed":3.5,"drift_factor":.9,"mass":1.0,
	"engine_pitch":.85,"drivetrain":"rwd","colors":["49252dff"],"mesh_count":10}
static func spec(id: String) -> Dictionary:
	return SPEC.duplicate(true) if id==ID else {}
static func create(id: String) -> Node3D:
	if id!=ID: return null
	var model := load(SPEC.scene) as PackedScene
	return model.instantiate() if model else null
