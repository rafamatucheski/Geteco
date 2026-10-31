extends RefCounted
## Dez fitas do piloto desaparecido (31/10/2026, card "Dez fitas e esconderijo secreto do piloto";
## plano em docs/plano-coletaveis-20260928.md, lugares em docs/fitas-piloto-20261031.md).
## Mesmo caminho das cartas de Vicente: cada fita é um colecionável (CollectibleCatalog, recibo
## "collectible:<id>" na carteira), então save, "não conta duas vezes" e a tela de colecionáveis já
## valem. Qualquer ordem. A décima libera o galpão do Pátio dos Armazéns (recibo HIDEOUT_RECEIPT,
## sem dinheiro: o prêmio é o lugar). Carro exclusivo e pista de saltos ficam como pendência no doc.
const IDS := ["pilot_tape_01", "pilot_tape_02", "pilot_tape_03", "pilot_tape_04", "pilot_tape_05",
	"pilot_tape_06", "pilot_tape_07", "pilot_tape_08", "pilot_tape_09", "pilot_tape_10"]
const HIDEOUT_RECEIPT := "pilot_tapes_hideout"
const HIDEOUT_NAME := "Galpão do piloto"
## Pátio dos Armazéns (ActivityDefinitions.delivery_yards "harbor_cold_storage", 1984,952 px / 16).
const HIDEOUT_POINT := Vector3(124, 0, 59.5)
## Rótulo curto (tela de colecionáveis).
const PLACES := {
	"pilot_tape_01": "Garagem do Chefe, porto sul", "pilot_tape_02": "Quartel Northgate",
	"pilot_tape_03": "Jardim de Westgate", "pilot_tape_04": "Boca do esgoto",
	"pilot_tape_05": "Cume Branco", "pilot_tape_06": "Cabana do Cavaleiro", "pilot_tape_07": "Abrigo dos Lenhadores",
	"pilot_tape_08": "Torre de rádio", "pilot_tape_09": "Ferro-velho do Nonato", "pilot_tape_10": "Salinas Estrada do Sal"}

static func is_tape(id: String) -> bool:
	return id in IDS

static func found(collectibles: Array) -> int:
	var count := 0
	for id in IDS:
		if collectibles.has(id): count += 1
	return count

static func complete(collectibles: Array) -> bool:
	return found(collectibles) == IDS.size()

static func hideout_open(economy) -> bool:
	return economy != null and economy.has_reward_receipt(HIDEOUT_RECEIPT)

## Grava o recibo do galpão uma única vez, só com as dez. true quando abriu agora.
static func try_unlock(economy) -> bool:
	if economy == null or hideout_open(economy) or not complete(economy._data.get("collectibles", [])): return false
	return economy.grant_reward(HIDEOUT_RECEIPT, 0, HIDEOUT_NAME)

## Pontos das fitas (ActivityDefinitions.collectibles). Harbor e serra: ponto de retorno de um lugar
## existente (PlaceCatalog: área que o jogo já garante livre ao sair) deslocado 1,5 m de lado, preso
## ao chão pelo raio do pickup. Deserto: ao lado do lugar da beira de estrada, fora do raio dele e
## longe do eixo da pista (RoadsideLayout: o centro fica a ~22 m da estrada).
static func points() -> Array:
	var roadside := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
	var result := [
		# Garagem do Chefe (5515,5870 px): retorno = exterior; a aproximação vai para -x, a fita segue nela.
		{"id":"pilot_tape_01","region":"harbor","place":"","point":Vector3(338.7,0,366.9)},
		# Quartel Northgate: aproximação (369.8, -77.2) + 2 m para fora do portão.
		{"id":"pilot_tape_02","region":"harbor","place":"","point":Vector3(369.8,0,-75.2)},
		# Westgate Garden (residência em 250,150 px): retorno (15.6, 15.16) + 1,5 m de lado. Quayside
		# ficava a 22 m da carta nº 2 de Vicente.
		{"id":"pilot_tape_03","region":"harbor","place":"","point":Vector3(17.1,0,15.2)},
		# Esgoto (bueiro em 1182,2114 px): ao lado da tampa, não em cima dela.
		{"id":"pilot_tape_04","region":"harbor","place":"","point":Vector3(75.6,0,132.1)},
		# Summit/Cume Branco: retorno (715, -476.02).
		{"id":"pilot_tape_05","region":"mountain","place":"","point":Vector3(716.5,0,-476.0)},
		# Cabana do Cavaleiro (mundo 655,-905): retorno (655, -900.62).
		{"id":"pilot_tape_06","region":"mountain","place":"","point":Vector3(656.5,0,-900.6)},
		# Abrigo dos Lenhadores, perto da serraria: retorno (765, -252.5).
		{"id":"pilot_tape_07","region":"mountain","place":"","point":Vector3(766.5,0,-252.5)},
	]
	for entry in [["pilot_tape_08", "radio_tower"], ["pilot_tape_09", "scrapyard"], ["pilot_tape_10", "salt_works"]]:
		var site: Dictionary = roadside.site(entry[1])
		if site.is_empty(): continue
		var side := float(site.get("radius", roadside.SITE_RADIUS)) + 3.0
		result.append({"id":entry[0],"region":"desert","place":"","point":roadside.at(site, Vector3(side, 0, 0))})
	return result
