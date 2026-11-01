extends RefCounted
## Dados do ato 2 lidos pela VicenteReunion: o título de cada missão da cadeia e onde cada personagem
## espera (com os dois pontos do mundo que SPOTS usa). Saíram de lá em 01/11 só para ela caber na
## leitura; ela reexporta cada constante com o mesmo nome (REUNION.SPOTS, REUNION.STAGING...).
const COMMUNITY := preload("res://world/desert/community/DesertCommunitySite.gd")

const CHAIN_TITLES := {"cargo": "Peso morto", "order": "A ordem alterada", "brothers": "Racha de irmãos", "cave": "Mesa de pedra",
	"letters": "Destinatário desconhecido", "bet": "Chave na chave", "trunk": "Porta-malas novo", "convoy": "Comboio da madrugada",
	"salt": "Sal na ferida", "teodoro": "Teodoro", "finale": "Os oito anos"}

## Porta do Cobre (DesertLayout.place_definitions: entrada a 1,4 m da fachada); Irene espera no pátio,
## além das saídas laterais (2,8 m), fora do caminho da porta.
const BANK_DOOR := Vector3(-210, 0, -911.6)

## Concentração da arrancada (DesertLayout.DRAG_STAGING), onde as provas de história começam; o Cascavel
## espera na beira dela ("meet_edge").
const STAGING := Vector3(-915, 0, -1304)

## Onde cada um espera. "site": lugar da Estrada do Sal (local do lugar); "anchor": ponto do mundo (+ local);
## "cave": caverna do DesertWilds (local da caverna). Pontos candidatos: o primeiro livre vale.
## Motel: calçada sob a marquise, na frente da porta do quarto 6 (fora das colunas, da lixeira e da
## máquina de gelo). Capela: no terreiro, longe da zeladora (que atende a vela a 2,4 m dela).
const SPOTS := {
	"motel": {"site": "motel", "points": [Vector3(2.6, 0, 1.0), Vector3(-1.6, 0, 1.0), Vector3(-1.0, 0, 4.2)], "face": Vector3(0, 0, 6)},
	"chapel": {"site": "chapel", "points": [Vector3(-2.6, 0, 3.8), Vector3(-2.4, 0, 6.0), Vector3(2.4, 0, 6.4)], "face": Vector3(0, 0, -1)},
	# Na frente do guarda-corpo (sólido em z 4), olhando a reta; a mais de 2,4 m do Seu Zé (18,3; 3),
	# que tem a ação dele na beira de estrada e vem antes na ordem das ações.
	"grandstand": {"site": "grandstand", "points": [Vector3(13.0, 0, 5.5), Vector3(10.0, 0, 5.5), Vector3(13.0, 0, 7.0)], "face": Vector3(13.0, 0, 30.0)},
	# A2-04: Irene sai do caixa depois das 20h e espera no pátio do banco (só à noite).
	"bank_night": {"anchor": BANK_DOOR, "night": true, "points": [Vector3(4.2, 0, 2.2), Vector3(-4.2, 0, 2.2), Vector3(4.2, 0, 4.0)], "face": Vector3(0, 0, 0)},
	# A2-06: perto da fogueira da caverna do Coyote (pontos calculados pelo lado da caverna em _points).
	"cave": {"cave": "cave_brother", "points": [], "face": Vector3.ZERO, "ray": 1.6},
	# A2-08: Cascavel na beira da concentração, do lado do encontro (fora das faixas da pista).
	"meet_edge": {"anchor": STAGING, "points": [Vector3(-9, 0, 9), Vector3(-12, 0, 11), Vector3(-7, 0, 13)], "face": Vector3(0, 0, 0)},
	# A2-12/A2-13: na pista da passagem norte, antes dos operários (z -1786 a -1791) e da área fechada da
	# obra (DesertNorthPassLayout.restore_point devolve quem salva além de z -1786); a barreira em si fica
	# colada nas pedras e não deixa lugar livre para conversar.
	# Santa Lua: a caixa-d'água junto da torre da cooperativa (A2-07) e a praça perto da casa da Helena (A2-11).
	"water_tower": {"anchor": COMMUNITY.ORIGIN, "points": [Vector3(2.5, 0, 3.0), Vector3(-2.5, 0, 3.0), Vector3(3.5, 0, -2.0)], "face": Vector3(0, 0, 8)},
	"santa_lua": {"anchor": Vector3(-528, 0, -830), "points": [Vector3(3.0, 0, 2.0), Vector3(-3.0, 0, 2.0), Vector3(0, 0, 5.0)], "face": Vector3(0, 0, -6)},
	"gate": {"anchor": Vector3(342.5, 0, -1810), "points": [Vector3(0, 0, 35), Vector3(4, 0, 37), Vector3(-4, 0, 37)], "face": Vector3(0, 0, 0)},
}
