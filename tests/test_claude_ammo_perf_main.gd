extends "res://tests/measure/video_phase4_ammunation.gd"
## Mesma medição renderizada da fase 4, com o aquecimento da Ammu-Nation feito
## antes da Main — simula o ponto de carregamento proposto para
## ProductionWorld._prewarm_regions(). O custo do aquecimento é impresso à parte.
## Mesmos argumentos do script base. (Uma variante que também desenhava a sala
## num SubViewport antes da Main foi medida em 25/09 e piorou a entrada: removida.)
const ART := preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")

func _initialize() -> void:
	var cost: float = ART.prewarm()
	var again: float = ART.prewarm()
	print("CLAUDE_AMMO_PREWARM ", JSON.stringify({"prewarm_ms": cost, "second_call_ms": again, "static_memory_mb": OS.get_static_memory_usage() / 1048576.0}))
	super._initialize()
