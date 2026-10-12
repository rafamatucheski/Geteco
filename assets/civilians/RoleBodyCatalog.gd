extends RefCounted
## Corpos do Meshy para os NPCs de função (bombeiro, paramédico, funerário, bancário, caixa, residente de serviço).
##
## Reaproveita os GLBs que já existem (terno, tático e pedestres) mudando só a cor das roupas com `tone`, sem gastar
## créditos do Meshy: `RigBodySwap.install` consulta este catálogo quando o `look` traz `role`. A escolha é estável
## pela `variant` do look. `enabled = false` ou `GETECO_NO_MESHY_BODIES=1` devolve o corpo procedural do kit.
## `tone` pode passar de 1 (cor HDR) para clarear roupa cinza, por exemplo o amarelo do bombeiro.
const POLICE := "res://assets/civilians/meshy/police/"
const PEDESTRIANS := "res://assets/civilians/meshy/pedestrians/"
const ROLES := {
	"mortician": [
		{"file": POLICE + "suit_m.glb", "female": false, "tint": {"tone": Color(0.30, 0.30, 0.34)}},
		{"file": POLICE + "suit_f.glb", "female": true, "tint": {"tone": Color(0.30, 0.30, 0.34)}},
	],
	"bank_clerk": [
		{"file": POLICE + "suit_m.glb", "female": false, "tint": {"tone": Color(0.85, 0.95, 1.2)}},
		{"file": POLICE + "suit_f.glb", "female": true, "tint": {"tone": Color(0.85, 0.95, 1.2)}},
	],
	"paramedic": [
		{"file": POLICE + "suit_m.glb", "female": false, "tint": {"tone": Color(0.55, 1.0, 1.1)}},
		{"file": POLICE + "suit_f.glb", "female": true, "tint": {"tone": Color(0.55, 1.0, 1.1)}},
	],
	"firefighter": [
		{"file": POLICE + "tactical_gray.glb", "female": false, "tint": {"tone": Color(1.9, 1.5, 0.3)}, "baked_equipment": true},
		{"file": POLICE + "tactical_black.glb", "female": false, "tint": {"tone": Color(1.8, 1.45, 0.3)}, "baked_equipment": true},
	],
	"pedestrian": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false},
		{"file": PEDESTRIANS + "f_medium_a.glb", "female": true},
		{"file": PEDESTRIANS + "f_medium_b.glb", "female": true},
		{"file": PEDESTRIANS + "f_slim_a.glb", "female": true},
	],
}
static var enabled := OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()

## {"path", "tint", "baked_equipment"} para `role`/`variant`, ou {} quando não há corpo (papel desconhecido, arquivo ausente
## ou catálogo desligado). `female` do look filtra pelo sexo quando há opção.
static func pick(role: String, variant: int, female := false, use_sex := false) -> Dictionary:
	if not enabled or not ROLES.has(role): return {}
	var options: Array = []
	for entry in ROLES[role]:
		if ResourceLoader.exists(entry.file) and (not use_sex or bool(entry.female) == female): options.append(entry)
	if options.is_empty(): return {}
	var entry: Dictionary = options[posmod(variant * 2654435761 + 40503, options.size())]
	return {"path": entry.file, "tint": entry.get("tint", {}), "baked_equipment": bool(entry.get("baked_equipment", false))}
