extends "res://assets/CivilianModel.gd"
## Motorista do trânsito sentado ao volante (playtest 29/10: os carros andavam vazios e o motorista
## só nascia quando o jogador entrava). Só apresentação: corpo do pedestre com a mesma receita de
## aparência do `Actor` civil (mesma identidade = mesma pessoa quando o roubo materializa o Actor).
## Vive num pool (TrafficDriverPool) e é estacionado/reaproveitado, nunca criado por carro.
##
## Custo: o corpo não anda (a medida de passada fica zerada, então nada de balanço de braço com o
## carro em movimento) e a pose só é refeita a cada POSE_STRIDE quadros quando visível; fora de
## vista não posa. Mãos no aro pelo volante medido do interior (VehicleInterior._limb_targets).
const POSE_STRIDE := 8
## Mãos no aro, no espaço deste corpo. Vazio = braços pendentes (carro sem interior medido).
var wheel_hands: Array = []
## 0 = dirigindo; 1 = caído sobre o volante (morto).
var slump := 0.0
var _posed_once := false

## Mesma receita do Actor civil (scripts/Actor.gd, ramo `else` do corpo). `winter`: roupa da serra, como o
## Actor que nasce lá, para o roubo tirar do banco a mesma pessoa.
static func create(identity: int, winter := false) -> Node3D:
	var model = load("res://gameplay/traffic/TrafficDriverModel.gd").new()
	model.name = "TrafficDriver"
	model.appearance_locked = true
	model.appearance_variant = identity
	model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][identity % 6]
	model.pants_color = [Color("293849"), Color("484644"), Color("615342")][identity % 3]
	model.sit_amount = 1.0
	model.set_meta("traffic_driver", true)
	model.set_meta("traffic_driver_winter", winter)
	if winter: model.wardrobe_overrides = WINTER_WARDROBE.duplicate()
	preload("res://assets/civilians/CivilianBodyCatalog.gd").apply(model, identity)
	return model

func _measure(_delta: float) -> void:
	# Sentado no carro: andar com o carro não é passada.
	_speed = 0.0

func _pose_update_interval() -> int:
	if not is_inside_tree() or not is_visible_in_tree(): return 0
	if not _posed_once or _hit != Vector2.ZERO or _hit_target != Vector2.ZERO or _hit_velocity != Vector2.ZERO: return 1
	var view := get_viewport().get_camera_3d()
	if view == null: return POSE_STRIDE
	return POSE_STRIDE if _pose_in_view(view) else 0

func _pose(dt: float) -> void:
	super._pose(dt)
	_posed_once = true
	if pelvis == null: return
	if slump > 0.0:
		# Caído: tronco sobre o volante, cabeça tombada, braços soltos.
		spine.transform = Transform3D(Basis(Vector3.RIGHT, .75 * slump) * Basis(Vector3.FORWARD, .18 * slump), SPINE_OFFSET)
		head_node.transform = Transform3D(Basis(Vector3.RIGHT, .55 * slump) * Basis(Vector3.FORWARD, -.35 * slump) * Basis.from_scale(_head_scale), NECK)
		return
	if wheel_hands.size() != 2: return
	var chest := pelvis.transform * spine.transform
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var target: Vector3 = wheel_hands[i]
		var arm := _reach_arm(i, chest, target, Vector3(side * .9, -.8, -.3))
		upper_arms[i].transform = Transform3D(arm[0], _shoulders[i])
		forearms[i].transform = Transform3D(arm[1], Vector3(0, -_arm_measure(i).x, 0))

## Refaz a pose já no próximo quadro (troca de carro, ferimento, morte).
func repose() -> void:
	_posed_once = false
	_pose_lod_frame = -1
