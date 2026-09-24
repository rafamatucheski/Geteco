extends RefCounted
## Troca o corpo de um modelo de NPC antigo (polícia, socorristas, residentes,
## caixas, mecânico) pelo pedestre articulado do `CivilianModel`, sem mexer na
## API que os atores usam.
##
## O modelo antigo continua existindo: os atores seguem escrevendo em
## `left_upper_leg.rotation`, a polícia segue calculando a arma pelos próprios
## braços. Só a geometria antiga fica invisível; o corpo novo anda sozinho
## (mede o próprio deslocamento) e as mãos vão até arma/maca via `hand_targets`.
##
## Chamar no fim do `_ready` do modelo, depois de ele ter fixado a própria escala.
## `keep` = nós cuja geometria deve continuar visível (arma, maca, clarão).
const BODY := preload("res://assets/CivilianModel.gd")

static func install(model: Node3D, look: Dictionary, keep: Array = [], faces_positive_z := false) -> Node3D:
	_hide_old(model, keep)
	var holder := Node3D.new()
	holder.name = "RigBody"
	# A maioria dos modelos antigos olha para -Z e o pedestre para +Z (o Actor
	# gira em PI); residentes de serviço já giram o próprio model_root.
	holder.rotation.y = 0.0 if faces_positive_z else PI
	var s := model.scale
	holder.scale = Vector3(1.0 / maxf(s.x, 0.01), 1.0 / maxf(s.y, 0.01), 1.0 / maxf(s.z, 0.01))
	var body: Node3D = BODY.new()
	body.name = "Body"
	body.appearance_locked = true
	body.appearance_variant = int(look.get("variant", randi_range(0, 9999)))
	body.coat_color = look.get("top_color", Color("3f6872"))
	body.pants_color = look.get("bottom_color", Color("293849"))
	var overrides: Dictionary = look.duplicate()
	for key in ["variant", "top_color", "bottom_color"]: overrides.erase(key)
	body.wardrobe_overrides = overrides
	body.lod_enabled = bool(look.get("lod", true))
	holder.add_child(body)
	model.add_child(holder)
	model.set_meta("rig_body", body)
	return body

static func _hide_old(root: Node, keep: Array) -> void:
	for child in root.get_children():
		if child in keep: continue
		if child is GeometryInstance3D: (child as GeometryInstance3D).visible = false
		_hide_old(child, keep)

## Mãos nas alças da maca dos socorristas (`stretcher_mesh` do modelo antigo,
## caixa de 0,42 × 0,85 m à frente), só enquanto ela está à vista.
static func stretcher_hands(model: Node3D) -> Callable:
	return func() -> Array:
		var stretcher = model.get("stretcher_mesh")
		if not is_instance_valid(stretcher) or not stretcher.is_visible_in_tree(): return [null, null]
		# Índice 0 do corpo = lado +X do modelo antigo (corpo girado em PI).
		return [stretcher.to_global(Vector3(0.19, 0.02, 0.43)), stretcher.to_global(Vector3(-0.19, 0.02, 0.43))]
