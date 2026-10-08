extends "res://assets/CivilianModel.gd"
## Local cheering pose; the shared civilian rig and crowd hot path are unchanged.
## The existing 45m admission and rig pose LOD bound all animation work.
var _cheer_weight := 0.0

func _pose(dt: float) -> void:
	super._pose(dt)
	if activity != "cheer" or _speed > .18 or sit_amount > 0.0:
		_cheer_weight = 0.0
		return
	_cheer_weight = move_toward(_cheer_weight, 1.0, minf(dt, .25) * 4.0)
	if _cheer_weight <= 0.0: return
	# One or both arms rise above shoulder level, with staggered pumps/waves.
	# Identity and clock avoid a synchronized crowd, without timers or tweens.
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
