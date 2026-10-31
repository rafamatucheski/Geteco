extends "res://assets/CivilianModel.gd"
## Pose local de torcida; o rig civil compartilhado e o caminho quente da multidão não mudam.
## A admissão de 45m existente e o LOD de pose do rig limitam todo o trabalho de animação.
var _cheer_weight := 0.0

func _pose(dt: float) -> void:
	super._pose(dt)
	if activity != "cheer" or _speed > .18 or sit_amount > 0.0:
		_cheer_weight = 0.0
		return
	_cheer_weight = move_toward(_cheer_weight, 1.0, minf(dt, .25) * 4.0)
	if _cheer_weight <= 0.0: return
	# Um ou os dois braços sobem acima do ombro, com socos no ar/acenos defasados.
	# Identidade e relógio evitam uma multidão sincronizada, sem timers nem tweens.
	var beat := clock * 2.8 + _seed
	for index in 2:
		var side := -1.0 if index == 0 else 1.0
		var wave := sin(beat + float(index) * 1.8)
		var lift := 2.15 + .28 * wave
		if index == 0 and appearance_variant % 2 == 0: lift = .65 + .15 * wave
		var raised := Basis.from_euler(Vector3(-lift, side * .12, side * (.3 + .1 * sin(beat * .7))))
		var bent := Basis(Vector3.RIGHT, -(.7 + .25 * sin(beat + .8)))
		upper_arms[index].basis = upper_arms[index].basis.slerp(raised, _cheer_weight)
		forearms[index].basis = forearms[index].basis.slerp(bent, _cheer_weight)
