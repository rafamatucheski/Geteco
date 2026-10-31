extends Node
## Mantém o corpo de quem usa fora dos shadow maps das próprias lâmpadas, não dos do mundo.
## A camada 16 é reservada ao jogador; 17/18 pertencem aos reflexos costeiros.
const PLAYER_LAYER := 1 << 15
const CAPTURE_LAYERS := (1 << 16) | (1 << 17)
const SHADOW_MASK := 0xFFFFF & ~(PLAYER_LAYER | CAPTURE_LAYERS)
var gameplay

func _ready() -> void:
	_visit(gameplay.player)
	_visit(gameplay.gun)
	get_tree().node_added.connect(_node_added)

func _exit_tree() -> void:
	get_tree().node_added.disconnect(_node_added)

func _visit(node: Node) -> void:
	if not is_instance_valid(node): return
	_node_added(node)
	for child in node.get_children(): _visit(child)

func _node_added(node: Node) -> void:
	if not node is GeometryInstance3D: return
	# Proxies só de reflexo e geometria escondida explicitamente precisam continuar invisíveis
	# para a câmera principal. Só migra geometria comum, renderizada publicamente.
	if node.layers & (1 | PLAYER_LAYER) == 0: return
	if not (is_instance_valid(gameplay.player) and gameplay.player.is_ancestor_of(node)) \
		and not (is_instance_valid(gameplay.gun) and gameplay.gun.is_ancestor_of(node)): return
	# Mantém os bits de reflexo/corte. Câmeras e luzes comuns incluem a camada 16;
	# máscaras de sombra pessoais a omitem, sem desligar o cast_shadow da malha.
	node.layers = (node.layers & ~1) | PLAYER_LAYER
