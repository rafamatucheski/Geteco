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
