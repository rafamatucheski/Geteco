class_name CollectibleCatalog
extends RefCounted

## Metadado de apresentação (nome + região) para a tela "Colecionáveis" do
## menu de pausa. A fonte de verdade de progresso continua sendo
## Player.collectibles_found — isto é só rótulo, nunca gravado em save.
##
## IDs tirados do manifesto real de HarborGame.gd (_spawn_world_extras),
## que instancia Collectible.gd com esses `collectible_id` — ver os dois
## arquivos antes de adicionar uma entrada nova aqui.
##
## Um ID presente em Player.collectibles_found mas ausente deste catálogo
## (por exemplo, um save de uma versão antiga do mapa) não é um erro: a tela
## de colecionáveis trata isso como achado preservado, sem nome/região
## conhecidos, em vez de descartar o registro.

const ENTRIES := {
	"harbor_memorial_letter": {"name": "Carta esquecida", "region": "Cemitério de Westgate"},
	"harbor_col_navio_01": {
		"name": "Pista do Cargueiro",
		"region": "Convés do cargueiro, doca leste",
	},
	"harbor_col_cobras_01": {
		"name": "Pista do Covil",
		"region": "Covil dos Cobras",
	},
	"harbor_col_oeste_01": {
		"name": "Achado do Limite Oeste",
		"region": "Extremidade oeste do distrito",
	},
	"harbor_col_leste_01": {
		"name": "Achado do Limite Leste",
		"region": "Extremidade leste, além do bairro dos Cobras",
	},
	"harbor_col_norte_01": {
		"name": "Achado do Limite Norte",
		"region": "Extremidade norte do distrito",
	},
	"harbor_col_sul_01": {
		"name": "Achado do Limite Sul",
		"region": "Extremidade sul do distrito",
	},
}

static func get_all_ids() -> Array:
	return ENTRIES.keys()

static func get_entry(collectible_id: String) -> Dictionary:
	return ENTRIES.get(collectible_id, {})

static func has_entry(collectible_id: String) -> bool:
	return ENTRIES.has(collectible_id)
