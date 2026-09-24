# Source: economy/CollectibleCatalog.gd; original data, legacy coordinates are NOT V2 world positions.
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
	"mountain_expedition_pack": {
		"name": "Mochila de Álvaro",
		"region": "Cachoeira da Mountain Pass",
	},
	"mountain_expedition_journal": {
		"name": "Diário de Álvaro",
		"region": "Caverna da Queda",
	},
	"mountain_expedition_camera": {
		"name": "Câmera quebrada",
		"region": "Câmara profunda da montanha",
	},
}

const FIND_CASH := 50
const MILESTONE_CASH := {3: 100, 5: 200, 10: 500}

