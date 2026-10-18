extends Node
## Keep the wearer's body out of its own lamps' shadow maps, not the world's.
## Layer 16 is reserved for the player; 17/18 belong to coastal reflections.
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
	# Reflection-only proxies and explicitly hidden geometry must stay invisible
	# to the main camera. Only migrate ordinary, publicly rendered geometry.
	if node.layers & (1 | PLAYER_LAYER) == 0: return
	if not (is_instance_valid(gameplay.player) and gameplay.player.is_ancestor_of(node)) \
		and not (is_instance_valid(gameplay.gun) and gameplay.gun.is_ancestor_of(node)): return
	# Keep reflection/cutaway bits. Ordinary cameras and lights include layer 16;
	# personal shadow masks omit it, without disabling the mesh's cast_shadow.
	node.layers = (node.layers & ~1) | PLAYER_LAYER
