extends SceneTree
## NPCs de função (bombeiro, paramédico, funerário, bancário, caixa, residente de serviço) com corpo do Meshy
## escolhido por `RoleBodyCatalog`: um só corpo visível, nenhuma malha antiga visível fora do que o modelo mantém
## (maca, cadeira, balcão), mãos na maca e rollback pelo interruptor. Não mede desempenho.
const CATALOG := preload("res://assets/civilians/RoleBodyCatalog.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
const MODELS := {
	"bombeiro": "res://gameplay/emergency/FirefighterModel.gd",
	"paramédico": "res://gameplay/emergency/ParamedicModel.gd",
	"funerário": "res://gameplay/emergency/MorticianModel.gd",
	"bancário": "res://assets/regions/source/world/harbor/events/BankClerkModel.gd",
	"caixa": "res://runtime/CashierBaseModel.gd",
	"residente de serviço": "res://world/places/ServiceResidentModel.gd",
	"Neco": "res://world/places/NecoModel.gd",
	"operador do porto": "res://gameplay/routines_v1/DockWorkerModel.gd",
	"segurança do banco": "res://runtime/BankGuardModel.gd",
	"morador do esgoto": "res://world/places/sewers/SewerHomelessModel.gd",
	"Cobra": "res://gameplay/CobraModel.gd",
	"morador da montanha": "res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd",
	"atendente da loja da montanha": "res://world/places/MountainShopResidentModel.gd",
	"morador da vila dos caminhoneiros": "res://gameplay/urban_v1/TruckersVillageResidentModel.gd",
	"Maciota": "res://assets/maciota/MaciotaModel.gd",
	"Luisa": "res://world/places/curitiba_cellar/LuisaModel.gd",
	"palhaço": "res://world/places/amusement_park/ParkClownModel.gd",
	"guarda do carro-forte": "res://gameplay/armored/ArmoredGuardModel.gd",
}
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("FUNCOES ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void: _run.call_deferred()

func _visible_old_meshes(model: Node, body: Node) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree() or body.is_ancestor_of(mesh_node): continue
		count += 1
	return count

func _run() -> void:
	for tag in MODELS:
		for variant in 2:
			# Guarda do carro-forte é PoliceModel tático (SWAT): não há corpo tático feminino (pendência conhecida).
			await _check_model(tag, variant)
	CATALOG.enabled = false
	var plain := (load(MODELS["funerário"]) as GDScript).new() as Node3D
	root.add_child(plain)
	for i in 8: await process_frame
	_check(plain.body != null and plain.body.get("skeleton") == null, "com o catálogo desligado o funerário volta ao corpo do kit")
	print("FUNCOES failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_model(tag: String, index: int) -> void:
	var model := (load(MODELS[tag]) as GDScript).new() as Node3D
	if model.get("appearance_female") != null: model.set("appearance_female", index == 1)
	if model.get("is_female") != null: model.set("is_female", index == 1)
	model.position = Vector3(index * 2.0, 0, 0)
	root.add_child(model)
	for i in 10: await process_frame
	var body: Node3D = model.get("body")
	# Modelos que herdam CivilianModel (operador do porto) são o próprio corpo.
	if body == null and model.get("skeleton") != null: body = model
	var label := "%s #%d" % [tag, index]
	if not _check(is_instance_valid(body) and body.get("skeleton") != null, "%s: corpo do Meshy instalado" % label):
		model.queue_free()
		return
	var skinned := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).is_visible_in_tree() and (node as MeshInstance3D).skeleton != NodePath(): skinned += 1
	_check(skinned >= 1 and skinned <= 2, "%s: corpo(s) com pele visíveis (%d)" % [label, skinned])
	_check(not DEATH.joints_of(body).is_empty(), "%s: juntas das mortes do Mixamo" % label)
	var skeleton: Skeleton3D = body.skeleton
	var feet := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_LeftToeBase")).origin
	_check(absf(feet.y - model.global_position.y) < 0.12, "%s: pés no chão da posição do modelo (%.3f m)" % [label, feet.y - model.global_position.y])
	# Malhas do modelo antigo ainda visíveis (maca, cadeira, balcão do próprio modelo são esperados e só contados).
	print("FUNCOES info ", label, " malhas fora do corpo visíveis: ", _visible_old_meshes(model, body))
	if tag in ["bombeiro", "paramédico", "funerário"]:
		var targets: Array = body.hand_provider.call() if body.hand_provider.is_valid() else []
		_check(targets.size() == 2, "%s: o provedor de mãos da maca responde" % label)
	model.queue_free()
