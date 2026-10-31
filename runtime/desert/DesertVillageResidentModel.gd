extends "res://assets/CivilianModel.gd"
## Um rig humano compartilhado, com mãos e respiração contínuas na sala ativa.
var home_activity := "read"

func _pose(delta: float) -> void:
	super._pose(delta)
	if home_activity=="read":
		head_node.rotation=Vector3(.30+sin(clock*.6)*.018,sin(clock*.45)*.035,0)
		return
	if home_activity!="sleep": return
	# O rig nativo inteiro deita de costas; a cabeça descansa no travesseiro
	# escrito enquanto o tronco e as pernas esticadas ficam apoiados no colchão.
	pelvis.position=Vector3(0,PELVIS_Y,0)
	pelvis.rotation=Vector3.ZERO
	spine.rotation=Vector3(sin(clock*1.35)*.006,0,0)
	head_node.position=NECK+Vector3(0,0,.12)
	head_node.rotation=Vector3(-.06,.06,0)
	for i in 2:
		var side := -1.0 if i==0 else 1.0
		thighs[i].rotation=Vector3(0,0,side*.025)
		shins[i].rotation=Vector3.ZERO
		feet[i].rotation=Vector3(-.05,0,0)
		upper_arms[i].rotation=Vector3(-.18,0,side*.10)
		forearms[i].rotation=Vector3(-.28,0,0)
