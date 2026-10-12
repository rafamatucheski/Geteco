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
		{"file": POLICE + "tactical_f.glb", "female": true, "tint": {"tone": Color(1.9, 1.5, 0.3)}, "baked_equipment": true},
	],
	# Neco: senhor robusto de boné verde-petróleo; o avental e a chave inglesa do modelo antigo não foram portados.
	"neco": [
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false, "accessories": [{"kind": "cap", "color": Color("384e49"), "band": Color("1d2a27")}]},
	],
	# Operadores do porto: o capacete e o colete refletivo continuam sendo as peças do `DockWorkerModel` presas às juntas.
	"dock_worker": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false},
		{"file": PEDESTRIANS + "m_heavy_b.glb", "female": false},
	],
	# Moradores de rua e do esgoto: só corpos de pedestre comum (nunca terno), com roupa suja e desbotada (tone escuro,
	# brilho baixo) e gorro ou boné escuro na maioria.
	"homeless": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "cap", "color": Color("4a4136"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "cap", "color": Color("4a4136"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "cap", "color": Color("4a4136"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_heavy_b.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "m_heavy_b.glb", "female": false, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "cap", "color": Color("4a4136"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "f_medium_a.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "f_medium_a.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}},
		{"file": PEDESTRIANS + "f_medium_b.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "f_medium_b.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}},
		{"file": PEDESTRIANS + "f_slim_a.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "f_slim_a.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}},
		{"file": PEDESTRIANS + "f_slim_b.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}, "accessories": [{"kind": "beanie", "color": Color("3a3c3e"), "band": Color("1c1d1e")}]},
		{"file": PEDESTRIANS + "f_slim_b.glb", "female": true, "tint": {"tone": Color(0.62, 0.55, 0.45), "brightness": 0.82}},
	],
	# Cobras: gangue de farda verde-escura; o biotipo segue o escalão (`role_index` = 0 magro, 1 médio, 2 robusto).
	"cobra": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false, "tint": {"tone": Color(0.36, 0.44, 0.38), "brightness": 0.9}},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false, "tint": {"tone": Color(0.36, 0.44, 0.38), "brightness": 0.9}},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false, "tint": {"tone": Color(0.36, 0.44, 0.38), "brightness": 0.9}},
	],
	# Moradores da montanha: pedestres comuns; a cor do casaco vem do look (`body_tone`) e o gorro de `body_accessories`.
	"winter": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false},
		{"file": PEDESTRIANS + "m_heavy_a.glb", "female": false},
		{"file": PEDESTRIANS + "m_heavy_b.glb", "female": false},
		{"file": PEDESTRIANS + "f_medium_a.glb", "female": true},
		{"file": PEDESTRIANS + "f_medium_b.glb", "female": true},
		{"file": PEDESTRIANS + "f_slim_a.glb", "female": true},
		{"file": PEDESTRIANS + "f_slim_b.glb", "female": true},
	],
	# Maciota: o terno cinza vira roxo (tone), com fedora escuro de fita dourada e óculos escuros; a bengala segue na mão.
	"maciota": [
		{"file": POLICE + "suit_m.glb", "female": false, "tint": {"tone": Color(1.3, 0.55, 1.5)}, "accessories": [
			{"kind": "fedora", "color": Color("4a235a"), "band": Color("f5cd79")}, {"kind": "sunglasses"}]},
	],
	# Luisa (contas da adega): mulher de blusa verde-sálvia, sentada.
	"luisa": [
		{"file": PEDESTRIANS + "f_medium_b.glb", "female": true, "tint": {"tone": Color(0.78, 1.0, 0.74)}},
	],
	# Palhaços do parque: pedestres de roupa tingida por `hue`/`tone` do look e peruca + nariz (acessório `clown`).
	"clown": [
		{"file": PEDESTRIANS + "m_medium_a.glb", "female": false},
		{"file": PEDESTRIANS + "f_medium_a.glb", "female": true},
		{"file": PEDESTRIANS + "m_medium_b.glb", "female": false},
		{"file": PEDESTRIANS + "f_slim_a.glb", "female": true},
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
static func pick(role: String, variant: int, female := false, use_sex := false, index := -1) -> Dictionary:
	if not enabled or not ROLES.has(role): return {}
	var options: Array = []
	for entry in ROLES[role]:
		if ResourceLoader.exists(entry.file) and (not use_sex or bool(entry.female) == female): options.append(entry)
	if options.is_empty(): return {}
	var entry: Dictionary = options[posmod(variant * 2654435761 + 40503, options.size()) if index < 0 else posmod(index, options.size())]
	return {"path": entry.file, "tint": entry.get("tint", {}), "baked_equipment": bool(entry.get("baked_equipment", false)), "accessories": entry.get("accessories", [])}

## Para modelos que herdam `CivilianModel` e se montam sozinhos (ex.: operador do porto): grava corpo e acessórios do papel
## antes de `super._ready()`. Devolve false (corpo do kit) sem catálogo ou arquivo.
static func apply(model: Node3D, role: String, variant: int, female := false, use_sex := false) -> bool:
	var picked := pick(role, variant, female, use_sex)
	if picked.is_empty(): return false
	model.body_source = String(picked.path)
	model.body_tint = picked.tint
	model.body_accessories = picked.accessories
	return true
