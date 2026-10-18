extends RefCounted
## Acabamento do chão da serra (18/10/2026): seixos, ondulação de vento na neve, acostamento de
## cascalho com leira de neve e asfalto com sal, trincas e pó de neve na nevasca. É tudo conta nos
## shaders que já existiam (terreno, piloto do terminal e asfalto unificado): nenhum material,
## textura ou variante de shader novo, então nada a pré-aquecer além do que já é.
## GETECO_MOUNTAIN_GROUND=0 desliga (uniform em 0) para A/B no mesmo export.

static var _enabled := -1
static var _snowfall := -1.0

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_MOUNTAIN_GROUND") == "0" else 1
	return _enabled == 1

static func value() -> float:
	return 1.0 if enabled() else 0.0

## Terreno e piloto: o uniform vem do include mountain_ground.gdshaderinc.
static func apply_ground(material: ShaderMaterial) -> void:
	material.set_shader_parameter("ground_finish", value())

## Asfalto unificado (porto, ponte e serra no mesmo material): a geada usa a rampa de entrada da serra.
## `load` em vez de preload: WorldConnection3D já pré-carrega o kit da ponte que cria este material.
static func apply_asphalt(material: ShaderMaterial) -> void:
	material.set_shader_parameter("mountain_finish", value())
	var connection: GDScript = load("res://world/regions/WorldConnection3D.gd")
	var unified: bool = connection.UNIFIED_BRIDGE.enabled()
	material.set_shader_parameter("frost_entry_x", Vector2(connection.TUNNEL_END_X+12.0,connection.TUNNEL_END_X+60.0) if unified else Vector2(connection.BRIDGE_END_X,connection.MOUNTAIN_BLEND_END_X))
	material.set_shader_parameter("frost_north_fade", connection.MOUNTAIN_NORTH_FADE)

## Frente de neve da serra (0..1). Só escreve quando muda de verdade: o clima chama a cada passo.
static func set_snowfall(front: float, material: ShaderMaterial) -> void:
	var value := snappedf(clampf(front, 0.0, 1.0), 0.01)
	if not enabled() or is_equal_approx(value, _snowfall): return
	_snowfall = value
	material.set_shader_parameter("snowfall", value)
