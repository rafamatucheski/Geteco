extends "res://assets/CivilianModel.gd"
## Adaptacao nativa do EPI visual de HarborDockWorker._build_3d_viewport.
## A geometria humana continua sendo o modelo civil compartilhado do V2.

var worker_index := 0

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 180 + worker_index * 4
	coat_color = Color("344958")
	pants_color = Color("283848")
	# Manga longa, calça e bota de trabalho; nada de boné/mochila sob o EPI.
	wardrobe_overrides = {"top": 1, "bottom": 0, "shoe": 1, "hat": 0, "backpack": false, "bag": 0, "glasses": false}
	super._ready()
	_build_original_ppe()

func _build_original_ppe() -> void:
	# Coordenadas do modelo em repouso; `anchor` prende cada peça à articulação
	# (capacete na cabeça, colete no tronco), então elas acompanham a passada.
	var helmet := anchor(head_node)
	helmet.name = "SafetyHelmet"
	var yellow := Color("f4cc40") if worker_index % 3 != 2 else Color("f1e9ca")
	part(helmet,Vector3(0,1.745,-.01),Vector3(.30,.05,.31),yellow)
	part(helmet,Vector3(0,1.79,-.012),Vector3(.25,.17,.27),yellow)
	part(helmet,Vector3(0,1.87,.0),Vector3(.035,.03,.25),yellow.lightened(.15))
	var vest := anchor(spine)
	vest.name = "ReflectiveVest"
	var vest_color := Color("d7d84d") if worker_index % 3 == 1 else Color("ec792b")
	part(vest,Vector3(0,1.2,0),Vector3(.39,.46,.27),vest_color)
	for z in [-.137,.137]:
		for x in [-.1,.1]: part(vest,Vector3(x,1.22,z),Vector3(.04,.38,.014),Color("e6eac9"))
		part(vest,Vector3(0,1.08,z*.97),Vector3(.36,.045,.016),Color("e6eac9"))
