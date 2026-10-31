extends RefCounted
## Entrada fria do catálogo: o carro pessoal salvo mantém a carroceria e a dirigibilidade.
const ID := "jessica_jetta_gli"
static func spec() -> Dictionary:
	return {"id":ID,"label":"Jetta GLI · Jessica","scene":"res://gameplay/jessica/JessicaJettaModel.tscn",
		"colors":["f1f0eaff"],"bounds_size":[2.21,1.46,4.84],"bounds_center":[0,.73,0],
		"durability":260,"mass":1.42,"max_speed":640.0,"acceleration":1320.0,
		"braking":1410.0,"turn_speed":2.85,"drift_factor":.84,"drivetrain":"fwd",
		"engine_family":"sport","engine_pitch":1.06,"turbo_audio":true,"roof_prop":"none",
		"owner":"jessica","turbo":true,"rim_inches":18,"body_doors":4}
