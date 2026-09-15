extends Node3D
## Dante Meshy para cópias do rig antigo fora do Player: cabine de veículo, moto
## e prévia da loja. Essas cópias duplicam as âncoras do Player, cujas malhas
## ficam ocultas quando o Meshy está ativo; sem este nó o Dante sumia no carro.
const MODEL_PATH := "res://assets/characters/meshy_dante/dante_grip.glb"
const SCALE := 0.82
const RETARGET := preload("res://scripts/player/MeshyAnchorRetarget.gd")
const APPEARANCE := preload("res://scripts/player/MeshyDanteAppearance.gd")

var anchors_root: Node3D
var skeleton: Skeleton3D
var material: ShaderMaterial
var _anchors := {}
var _bones := {}
var _rests: Array[Transform3D] = []

func configure(root: Node3D, outfit_id: String, hide_legacy := false) -> bool:
	name = "MeshyDantePuppet"
	anchors_root = root
	_anchors = RETARGET.find_anchors(root)
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null or _anchors.is_empty(): return false
	var model := packed.instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * SCALE
	model.rotation.y = PI
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh := model.find_child("Mesh0", true, false) as MeshInstance3D
	if skeleton == null or mesh == null: return false
	var animations := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animations: animations.active = false
	for i in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(i)] = i
		_rests.append(skeleton.get_bone_rest(i))
	material = APPEARANCE.apply(mesh, skeleton, outfit_id)
	if hide_legacy:
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			# A sombra de contato é filha direta da raiz e continua.
			if node.get_parent() != root and not is_ancestor_of(node): node.hide()
	# Depois de quem posa as âncoras no mesmo quadro (embarque, cabine, moto).
	process_priority = 200
	_update()
	return true

func _update() -> void:
	if is_instance_valid(skeleton) and is_instance_valid(anchors_root):
		RETARGET.apply(skeleton, _bones, _rests, anchors_root, _anchors)

func _process(_delta: float) -> void:
	if is_visible_in_tree(): _update()
