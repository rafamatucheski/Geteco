extends RefCounted
## Tabela única do dinheiro que dá para ajustar sem quebrar save. Antes cada sistema tinha o
## seu número e ninguém via o conjunto: a história inteira do Harbor pagava R$ 2.170 enquanto
## o guincho, aberto desde o primeiro minuto, pagava R$ 20.000 por rodada, e um carro-forte
## valia uma casa (revisão cruzada de 18/10/2026).
##
## Ideia: a história é o melhor dinheiro enquanto dura e libera os serviços que rendem mais;
## o trabalho repetível vira renda de bolso; o golpe grande continua grande, com risco.
##
## FORA desta tabela (contratos de recibo; mudar invalida todo save que já recebeu o valor):
## a recompensa base de cada missão (HarborMissions.reward), prêmios de motocross e esqui
## (RaceReceipts), descida e jipe da serra, carros e peças do deserto, preços de loja gravados
## em recibo. Para mexer nesses, pague a diferença com um recibo novo, como STORY_BONUS faz.

## Bônus de conclusão por cima de HarborMissions.reward (recibo "campaign_bonus:<id>"). Total
## por missão: 1.000 / 1.500 / 2.000 / 2.500 / 3.000 (+ cofre) / 3.500 / 8.000 = R$ 21.500.
## Mudar um valor só afeta quem ainda não recebeu aquela missão.
const STORY_BONUS := {
	"primeiro_giro": 850,
	"cobra_contact": 1380,
	"cobra_race": 1800,
	"cobra_collection": 2250,
	"jessica_bank": 2500,
	"cobra_supply": 3150,
	"cobra_finale": 7400,
}

## Guincho (TowJobs.JOBS, mesma ordem). Cada faixa abre com uma missão: no começo só o reboque
## simples; o resto entra conforme Dante ganha a confiança da cidade. Rodada completa: R$ 7.100.
const TOW_TIERS := [
	{"reward": 600, "requires": ""},
	{"reward": 900, "requires": "primeiro_giro"},
	{"reward": 1400, "requires": "cobra_collection"},
	{"reward": 1800, "requires": "jessica_bank"},
	{"reward": 2400, "requires": "cobra_finale"},
]
## Valores antigos ainda aceitos num contrato de guincho já gravado (save de antes da mudança).
const TOW_LEGACY_REWARDS := [1800, 3200, 4200, 4800, 6000]

## Carro-forte (só depois do fim do Harbor). Era 40.000: um golpe comprava a casa mais cara.
const ARMORED_CASH_PER_TRUCK := 20000

## Morte e prisão (RecoveryPenalty): parte do dinheiro na mão, com teto.
const RECOVERY_RATE := 0.10
const RECOVERY_CAP := 2000

## Beira de estrada do deserto (runtime/desert/roadside, 19/10/2026). Renda de bolso, como o
## guincho do começo: o ferro-velho do Nonato paga a sucata pela regra e pelo limite diário da
## prensa do Neco (GarageRewards.scrap_value), por isso não aparece aqui.
## Conserto no Sol Poente: mais caro que a oficina de Northgate (100), que ainda tira a polícia.
const ROADSIDE_REPAIR := 150
## Entregas do orelhão por destino (RoadsideLayout.COURIER_ROUTES).
const ROADSIDE_COURIER := {"miragem": 350, "arrancada": 600, "sal": 450}
## Lugares da Estrada do Sal (20/10): quarto no Motel Oásis até as 7h (cura e salva, pago, ao contrário
## do descanso de graça do Horizonte, que só vai até as 20h para a arrancada) e a vela da capela (cura pouca).
const ROADSIDE_MOTEL_ROOM := 80
const ROADSIDE_CANDLE := 10
const ROADSIDE_CANDLE_HEAL := 25.0
## Caminhão quebrado: ajudar o caminhoneiro paga por recibo; se ele não está mais lá, a caixinha
## da cabine é dinheiro solto (Economy.collect_loose_cash aceita até 300).
const ROADSIDE_TRUCK_HELP := 200
const ROADSIDE_TRUCK_CASHBOX := Vector2i(120, 240)
## Bloqueio de bandidos: o que sobra na picape depois da briga (dinheiro solto).
const ROADSIDE_ROADBLOCK_LOOT := Vector2i(220, 300)
