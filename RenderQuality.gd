extends Node
## O MSAA da janela não alcança os modelos desenhados em SubViewports.
## Configura também os viewports criados depois, inclusive pelo streaming.

func _ready() -> void:
	get_tree().root.msaa_2d = Viewport.MSAA_2X
	get_tree().node_added.connect(_configure_viewport)

func _configure_viewport(node: Node) -> void:
	if not node is SubViewport:
		return
	var viewport := node as SubViewport
	# Preserva níveis maiores definidos por retratos e prévias de personagens.
	if viewport.disable_3d:
		if viewport.msaa_2d == Viewport.MSAA_DISABLED:
			viewport.msaa_2d = Viewport.MSAA_2X
	elif viewport.msaa_3d == Viewport.MSAA_DISABLED:
		viewport.msaa_3d = Viewport.MSAA_2X
