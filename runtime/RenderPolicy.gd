extends RefCounted
## Política de render que não depende das opções gráficas do menu: MSAA de SubViewport e
## qualidade de sombra lida do autoload (auditoria do Godot 4.7, 19/10).

## MSAA de SubViewport 3D. Pipeline de cor é compilado por número de amostras: um SubViewport com
## 4x fixo enquanto o jogo roda em 2x (ou sem MSAA) compila de novo cada material que ele desenha,
## no primeiro desenho — nenhum pré-aquecimento sob a cortina serve para ele (auditoria Godot 4.7,
## 19/10, §4). Seguir o viewport principal reaproveita o que já foi compilado, como
## CoastalPlanarReflections já fazia. GETECO_SUBVIEWPORT_MSAA_MATCH=0 devolve o valor fixo antigo (A/B).
static var subviewport_msaa_match := OS.get_environment("GETECO_SUBVIEWPORT_MSAA_MATCH") != "0"

static func subviewport_msaa(legacy: Viewport.MSAA) -> Viewport.MSAA:
	if not subviewport_msaa_match: return legacy
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return legacy
	return tree.root.msaa_3d

## Qualidade de sombra escolhida pelo jogador (0 baixa, 1 média, 2 alta); 1 sem o autoload (testes).
static func shadow_quality() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("V2Settings") if tree != null and tree.root != null else null
	return clampi(int(settings.get("shadow_quality")), 0, 2) if settings != null else 1
