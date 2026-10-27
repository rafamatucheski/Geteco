extends "res://runtime/desert/drag_meet/DragSpectatorModel.gd"
## Balanço do encontro de lowriders: cabeça e tronco marcam o tempo (~92 BPM) e um braço sobe
## dobrado no ritmo. Só o tronco, a cabeça e os braços: a pelve e o IK das pernas do CivilianModel
## ficam intactos. Herda a torcida ("cheer") do público do racha para comemorar os pulos.
const BPM := 92.0
var _groove_weight := 0.0

func _pose(dt: float) -> void:
	super._pose(dt)
	var grooving := activity == "groove" and _speed <= .18 and sit_amount <= 0.0
	_groove_weight = move_toward(_groove_weight, 1.0 if grooving else 0.0, minf(dt, .25) * 3.0)
	if _groove_weight <= 0.0: return
	var beat := clock * TAU * BPM / 60.0 + _seed
	# Pulso curto em cada batida (sobe rápido, solta devagar) e meio balanço lateral a cada compasso.
	var pulse := pow(maxf(0.0, sin(beat)), 2.0)
	var sway := sin(beat * .5)
	var w := _groove_weight
	spine.transform.basis = spine.transform.basis * Basis.from_euler(Vector3(.10 * pulse * w, .08 * sway * w, .05 * sway * w))
	head_node.transform.basis = Basis(Vector3.RIGHT, .20 * pulse * w) * head_node.transform.basis
	# Braço da frente sobe dobrado e acompanha a batida; o outro fica solto, balançando pouco.
	var lead := 1 if appearance_variant % 2 == 0 else 0
	var side := -1.0 if lead == 0 else 1.0
	var raised := Basis.from_euler(Vector3(-(1.05 + .22 * pulse), side * .10, side * .32))
	upper_arms[lead].transform.basis = upper_arms[lead].transform.basis.slerp(raised, w)
	forearms[lead].transform.basis = forearms[lead].transform.basis.slerp(Basis(Vector3.RIGHT, -(1.35 + .15 * pulse)), w)
	var loose := 1 - lead
	upper_arms[loose].transform.basis = upper_arms[loose].transform.basis * Basis(Vector3.RIGHT, -.10 * sway * w)
