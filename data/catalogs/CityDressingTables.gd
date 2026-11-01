extends RefCounted
## Tabelas de sorteio do acabamento dos trechos do porto (CityChunkDressing e auxiliares), separadas
## do código em 01/11 (Onda 1 do plano de divisão). O dono reexporta cada uma com o mesmo nome
## (`CityChunkDressing.FURNITURE` etc.), então quem lê pelo dono não muda. Mudar peso ou ordem
## muda o sorteio determinístico de todos os trechos.

## Pátio de veículos da oficina: mobília da calçada e postes ficam de fora (ver _workshop_driving).
const WORKSHOP_VEHICLE_ACCESS := [Rect2(153.0,100.8,10.0,10.7),Rect2(167.0,97.2,11.1,5.5),Rect2(156.8,109.7,33.0,2.4)]

## Calçada: hidrante, lixeira, jornaleiro, caixa de correio, orelhão, banco (tipo, peso).
const FURNITURE := [
	["hydrant", 0.13], ["trash_can", 0.14], ["news_box", 0.07], ["mailbox", 0.05],
	["phone_booth", 0.03], ["bench_seat", 0.04], ["trash_bags", 0.05], ["planter", 0.03],
]

## Telhados: tons da laje (ROOF_TINTS, decalque "roof_<n>") e adereços sorteados (tipo, peso).
const ROOF_TINTS := [
	Color(0.10, 0.10, 0.11, 0.35), Color(0.45, 0.30, 0.24, 0.28), Color(0.62, 0.62, 0.58, 0.30),
	Color(0.26, 0.33, 0.29, 0.30), Color(0.20, 0.22, 0.28, 0.32), Color(0.55, 0.47, 0.36, 0.26),
]
const ROOF_PROPS := [["ac_unit", 0.2], ["vent", 0.14], ["roof_hatch", 0.06], ["antenna", 0.06], ["dish", 0.07], ["pipe_run", 0.06], ["roof_shed", 0.06], ["roof_garden", 0.06], ["roof_chairs", 0.04], ["water_tank", 0.06], ["skylight", 0.07], ["solar_row", 0.05], ["cooling_tower", 0.04]]

## Adereços que leem como saída do telhado (casinha da escada, alçapão): um por prédio.
const ROOF_EXITS := ["roof_shed", "roof_hatch"]
