extends RefCounted
## As 10 cartas de Vicente (20/10/2026). Escritas da prisão nos oito anos que Dante não respondeu,
## voltaram com "destinatário desconhecido"; solto, Vicente as deixou pelo caminho que ele mesmo fez
## (Harbor, a serra, o deserto) para o irmão seguir. A décima aponta a caverna escondida onde está
## o Coyote 440 dos dois. Achar as dez também libera a mala do Maciota (o mesmo prêmio da Prova de
## rua: um ou outro basta). Progresso = Economy.collectibles (CollectibleCatalog, mesmos ids).
## O texto fica fiel ao que o roteiro guarda para o ato 2: Vicente lê a prisão como abandono e não
## sabe da armação; as cartas não contam quem armou.
const IDS := ["vicente_letter_01", "vicente_letter_02", "vicente_letter_03", "vicente_letter_04", "vicente_letter_05",
	"vicente_letter_06", "vicente_letter_07", "vicente_letter_08", "vicente_letter_09", "vicente_letter_10"]
const SPEAKER := "Carta de Vicente"
const TEXTS := {
	"vicente_letter_01": "Dante. Primeira carta. O advogado disse que escrever ajuda. Não ajuda. Você me olhou nos olhos quando fechou a algema. Eu só queria entender por quê.",
	"vicente_letter_02": "O Maciota veio me ver. Trouxe cigarro e notícia sua: disse que você largou a farda. Não sei se fiquei com raiva ou aliviado.",
	"vicente_letter_03": "Lembra do canal? A gente pulava da mureta e a mãe gritava da janela. Aqui dentro eu fecho o olho e ainda ouço a água.",
	"vicente_letter_04": "Dois anos e nenhuma resposta. Talvez você nem receba. Vou continuar escrevendo do mesmo jeito: teimosia é coisa de família.",
	"vicente_letter_05": "Aprendi a mexer em motor com um velho daqui. Ele diz que todo carro guarda a história de quem dirigiu. O nosso Coyote deve estar guardando a minha.",
	"vicente_letter_06": "Um guarda me contou que você pediu meu processo de volta. Não acreditei. Se for verdade, por que nunca veio me dizer?",
	"vicente_letter_07": "Contei os dias na parede da cela. Aqui na pedra também. Quando sair, vou para o deserto: lá ninguém pergunta de onde você veio, só quanto acelera.",
	"vicente_letter_08": "Saí. Dormi a primeira noite livre num quarto de beira de estrada, de luz acesa. Não consegui fechar a porta. Oito anos ensinam coisas estranhas.",
	"vicente_letter_09": "Acendi uma vela aqui. Não sei mais rezar, então só fiquei sentado. Pedi que, se você tiver um motivo, um dia eu consiga escutar.",
	"vicente_letter_10": "Se você leu até aqui, seguiu cada passo meu. Então siga mais um: a mesa de pedra ao sul do leito seco, longe da estrada do sal. O Coyote ainda está lá. Sempre foi nosso.",
}
## Onde cada uma está (nome curto para a tela de colecionáveis).
const PLACES := {
	"vicente_letter_01": "Cais do porto", "vicente_letter_02": "Oficina do Maciota", "vicente_letter_03": "Sobrados do canal",
	"vicente_letter_04": "Ponte para a serra", "vicente_letter_05": "Estrada da serra", "vicente_letter_06": "Curva alta da serra",
	"vicente_letter_07": "Caverna do Sussurro", "vicente_letter_08": "Motel Oásis", "vicente_letter_09": "Capela da Estrada",
	"vicente_letter_10": "Arquibancada da reta"}
## O prêmio da décima: caverna escondida e o carro (DesertWilds "cave_brother").
const CAR_ID := "vicente_coyote"
const CAR_ARCHETYPE := "desert_coyote"
const CAR_PAINT := "1d2b26"
const CAR_RECEIPT := "desert_wilds_cave_brother"
## Peças do Coyote do Vicente (preparação de arrancada que ele deixou montada).
const CAR_PARTS := {"ecu": "ecu_2", "engine": "street_cam", "gearbox": "gear_short", "tires": "drag_tires", "exhaust": "race_exhaust", "finish": "finish_satin", "wheels": "wheels_bronze", "neon": "neon_amber"}

static func is_letter(id: String) -> bool:
	return id in IDS

static func found(collectibles: Array) -> int:
	var count := 0
	for id in IDS:
		if collectibles.has(id): count += 1
	return count

static func complete(collectibles: Array) -> bool:
	return found(collectibles) == IDS.size()
