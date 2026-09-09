class_name StreamableActorPresentation
extends Node3D

## Controlador-base para apresentacao visual 3D sob demanda (Presentation Streaming).
##
## Compativel com o PresentationBudget do projeto:
## 1. Suporta modo diferido (defer_presentation = true) exibindo proxy leve de silhueta
##    enquanto aguarda orcamento de frame para construcao.
## 2. Permite que fisica, colisao, navegacao, estados de vida/morte e regras de jogo
##    funcionem imediatamente SEM depender da presenca do rig 3D.
## 3. Armazena chamadas visuais em buffer (poses, acessorios, tintas, danos) se forem
##    solicitadas antes de presentation_ready, aplicando-as automaticamente na montagem.
## 4. Reciclagem integral (recycle_presentation): zera poses, limpa danos, restaura
##    materiais imutaveis compartilhados e desanexa acessorios, garantindo ZERO vazamento.

signal presentation_build_requested
signal presentation_ready
signal presentation_recycled
signal presentation_damaged(damage_type: String, intensity: float)

@export var defer_presentation: bool = false

var is_presentation_ready: bool = false
var build_duration_ms: float = 0.0

# Proxy de silhueta para quando estiver em defer_presentation
var _presentation_fallback: Node3D = null

# Buffers de estado enquanto o rig nao foi construido
var _buffered_pose: int = -1
var _buffered_custom_tint: Color = Color.TRANSPARENT
var _buffered_damage: Array[Dictionary] = []
var _buffered_accessories: Array[Dictionary] = []
var _buffered_walking: bool = false

# Dicionario de rotacoes de repouso originais para restauracao perfeita
var _rest_rotations: Dictionary = {}

func _ready() -> void:
	if not defer_presentation:
		ensure_presentation()
	else:
		_setup_fallback_silhouette()

## Cria uma silhueta visual basica e ultra-leve para o ator enquanto aguarda o rig 3D
func _setup_fallback_silhouette() -> void:
	if _presentation_fallback != null or is_presentation_ready:
		return
	_presentation_fallback = Node3D.new()
	_presentation_fallback.name = "FallbackSilhouette"
	add_child(_presentation_fallback)

	# Proxy de silhueta vertical
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box()
	mi.scale = Vector3(0.32, 1.65, 0.22)
	mi.position = Vector3(0.0, 0.825, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat

	_presentation_fallback.add_child(mi)

## Requisita montagem ao PresentationBudget ou dispara construcao
func request_presentation() -> void:
	if is_presentation_ready:
		return
	if has_node("/root/PresentationBudget"):
		get_node("/root/PresentationBudget").call("request", self)
	presentation_build_requested.emit()

## Constroi o rig 3D de forma sincrona se ainda nao construido
func ensure_presentation() -> void:
	if is_presentation_ready:
		return

	var start_usec := Time.get_ticks_usec()
	_build_presentation_rig()
	build_duration_ms = (Time.get_ticks_usec() - start_usec) / 1000.0

	# Remove o proxy de silhueta
	if is_instance_valid(_presentation_fallback):
		_presentation_fallback.queue_free()
		_presentation_fallback = null

	# Registra as rotacoes de repouso de todos os membros do rig recem-construido
	_cache_rest_rotations()

	is_presentation_ready = true

	# Aplica estados em buffer acumulados antes da montagem
	_apply_buffered_states()

	presentation_ready.emit()

## Metodo virtual para ser sobrescrito pelos modelos concretos (Elias, Coveiro, Mourner)
func _build_presentation_rig() -> void:
	pass

## Metodo virtual para registrar rotacoes de repouso dos membros
func _cache_rest_rotations() -> void:
	_rest_rotations.clear()
	_cache_node_rotations_recursive(self)

func _cache_node_rotations_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D:
			_rest_rotations[child] = child.rotation
			_cache_node_rotations_recursive(child)

## Aplica tudo que foi bufferizado antes de o rig existir
func _apply_buffered_states() -> void:
	if _buffered_pose >= 0:
		_apply_pose_to_rig(_buffered_pose)
	if _buffered_custom_tint != Color.TRANSPARENT:
		_apply_tint_to_rig(_buffered_custom_tint)
	for dmg in _buffered_damage:
		_apply_damage_to_rig(dmg.get("type", "bullet"), dmg.get("intensity", 1.0), dmg.get("part", ""))
	_buffered_damage.clear()
	for acc in _buffered_accessories:
		_apply_accessory_to_rig(acc)
	_buffered_accessories.clear()

## Reciclagem completa: limpa deformacoes, restaura poses de repouso e materiais imutaveis
func recycle_presentation() -> void:
	if not is_presentation_ready:
		_buffered_pose = -1
		_buffered_custom_tint = Color.TRANSPARENT
		_buffered_damage.clear()
		_buffered_accessories.clear()
		_buffered_walking = false
		return

	# 1. Restaura rotacoes de repouso
	for node in _rest_rotations.keys():
		if is_instance_valid(node):
			node.rotation = _rest_rotations[node]

	# 2. Restaura materiais imutaveis compartilhados
	_restore_shared_materials()

	# 3. Limpa buffers
	_buffered_pose = -1
	_buffered_custom_tint = Color.TRANSPARENT
	_buffered_damage.clear()
	_buffered_accessories.clear()
	_buffered_walking = false

	# 4. Reseta flags de animacao
	_on_recycled_custom()

	presentation_recycled.emit()

## Metodo virtual para restaurar materiais imutaveis
func _restore_shared_materials() -> void:
	pass

## Hook adicional de reciclagem para filhas
func _on_recycled_custom() -> void:
	pass

## Aplicacao de dano com isolamento de material garantido
func apply_damage(damage_type: String, intensity: float = 1.0, affected_part: String = "") -> void:
	if not is_presentation_ready:
		_buffered_damage.append({"type": damage_type, "intensity": intensity, "part": affected_part})
		return
	_apply_damage_to_rig(damage_type, intensity, affected_part)
	presentation_damaged.emit(damage_type, intensity)

## Metodo virtual para aplicar dano no rig
func _apply_damage_to_rig(_damage_type: String, _intensity: float, _affected_part: String) -> void:
	pass

## Aplicacao de tint personalizada com isolamento de material
func set_custom_tint(tint: Color) -> void:
	if not is_presentation_ready:
		_buffered_custom_tint = tint
		return
	_apply_tint_to_rig(tint)

## Metodo virtual para tintar o rig
func _apply_tint_to_rig(_tint: Color) -> void:
	pass

## Poses virtuais
func set_pose(pose_idx: int) -> void:
	if not is_presentation_ready:
		_buffered_pose = pose_idx
		return
	_apply_pose_to_rig(pose_idx)

func _apply_pose_to_rig(_pose_idx: int) -> void:
	pass

func _apply_accessory_to_rig(_acc: Dictionary) -> void:
	pass