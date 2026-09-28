extends RefCounted
## Cenografia narrativa e preenchimento do corte do túnel secreto. Só visual (mais
## alguns colisores de mobília); nada aqui altera progressão nem save. Cada grupo
## ecoa um id de SecretNetworkProgression para o jogador "ler" o que ainda vai achar:
## mapa (fragmentos), teclado/energia (quadro de disjuntores), fitas de Vicente,
## crachá/relatório/foto do laboratório e os ramais do Porto Sul e da serra.
##
## Linguagem de marcas pintadas, repetida nas galerias e no QG:
## anel azul = Porto Sul, triângulo ferrugem = serra, quadrado verde = esgoto.

const BUILT_RECTS := [
	Rect2(-2.0,-2.0,4.0,10.35),
	Rect2(-2.95,-12.5,5.9,11.2),
	Rect2(-.5,-15.15,37.0,6.3),
	Rect2(32.85,-12.5,6.3,15.0),
	Rect2(35.5,-1.15,21.2,6.3),
	Rect2(50.2,-5.8,15.8,15.6),
	Rect2(55.55,-15.2,4.9,9.6),
]
const STONE := ["62685d","596158","4e5750","6b6d60"]
const PAPER := ["b8ad8d","a99f80"]
const WOOD := "5f4a34"
const WOOD_LIGHT := "6a5539"

static func build(stage) -> void:
	_bedrock(stage)
	_gallery(stage)
	_sealed_arches(stage)
	_pump_station(stage)
	_power_branch(stage)
	_headquarters_shell(stage)
	_pinboard(stage)
	_route_hatches(stage)
	_archive_and_tapes(stage)
	_sealed_sector_traces(stage)

# --- Preenchimento do corte -------------------------------------------------

static func _near_built(x: float,z: float,margin: float) -> bool:
	for rect in BUILT_RECTS:
		if rect.grow(margin).has_point(Vector2(x,z)): return true
	return false

static func _bedrock(stage) -> void:
	# O preto de antes era o fundo da câmera vazando entre as salas. Lajes de rocha
	# em alturas levemente diferentes (sempre abaixo dos pisos) fazem o corte ler
	# como um bloco de subsolo, sem colisão nem piso caminhável extra.
	var rng := RandomNumberGenerator.new()
	rng.seed = 195108
	var palette := ["434b3f","4a5243","3f473c","504d40","3d4640","454d42"]
	var x := -32.0
	while x < 94.0:
		var z := -38.0
		while z < 30.0:
			var top := -.34-rng.randf()*.06
			var color: String = palette[rng.randi()%palette.size()]
			stage._box(Vector3(x+2.5,top-.2,z+2.5),Vector3(5.4,.4,5.4),color,Vector3(0,rng.randf_range(-.05,.05),0))
			z += 5.0
		x += 5.0
	for index in 170:
		var at := Vector3(rng.randf_range(-30.0,92.0),0,rng.randf_range(-36.0,28.0))
		if _near_built(at.x,at.z,1.1): continue
		var size := Vector3(rng.randf_range(.3,1.5),rng.randf_range(.2,.8),rng.randf_range(.3,1.3))
		var rock_color: String = palette[rng.randi()%palette.size()]
		stage._box(Vector3(at.x,-.34+size.y*.4,at.z),size,rock_color,Vector3(rng.randf_range(-.3,.3),rng.randf_range(0,PI),rng.randf_range(-.3,.3)))
	for index in 40:
		var at := Vector3(rng.randf_range(-30.0,92.0),-.335,rng.randf_range(-36.0,28.0))
		if _near_built(at.x,at.z,.6): continue
		stage._box(at,Vector3(rng.randf_range(1.2,3.4),.02,rng.randf_range(.5,1.6)),"34433b" if index%2 else "3f4a42",Vector3(0,rng.randf_range(0,PI),0))
	# Galerias de drenagem enterradas: sugerem a rede maior sem revelar caminho.
	for z in [-22.0,17.5]:
		var start := -30.0
		while start < 88.0:
			stage._pipe(Vector3(start,-.02,z),Vector3(start+8.0,-.02,z),.3,"4a463d")
			start += 8.0

# --- Galeria longa: trilho de serviço, escoras, marcas -----------------------

static func _gallery(stage) -> void:
	for z in [-13.9,-12.9]: stage._box(Vector3(17.0,.03,z),Vector3(32.0,.05,.07),"777063")
	var x := 1.6
	while x < 32.9:
		stage._box(Vector3(x,.0,-13.4),Vector3(.14,.045,1.35),WOOD)
		x += .95
	var trolley := Vector3(31.4,0,-13.4)
	stage._solid("ServiceTrolley",trolley+Vector3(0,.5,0),Vector3(1.7,.9,1.25))
	stage._box(trolley+Vector3(0,.40,0),Vector3(1.6,.10,1.15),WOOD)
	for side in [-1.0,1.0]:
		stage._box(trolley+Vector3(0,.66,side*.55),Vector3(1.6,.42,.08),WOOD_LIGHT)
		stage._box(trolley+Vector3(side*.76,.66,0),Vector3(.08,.42,1.15),WOOD_LIGHT)
		for wheel_z in [-.5,.5]:
			stage._cylinder(trolley+Vector3(side*.5,.17,wheel_z),.17,.07,"303a39",Vector3(PI*.5,0,0),10)
	stage._box(trolley+Vector3(-.2,.86,.05),Vector3(.7,.30,.6),"424943",Vector3(.1,.4,.06))
	stage._box(trolley+Vector3(.35,.80,-.1),Vector3(.5,.22,.44),"4e5750",Vector3(-.08,-.3,.1))
	stage._box(trolley+Vector3(.1,.98,.62),Vector3(1.3,.05,.05),WOOD,Vector3(0,.3,.5))
	# Caixas e barris junto à boca oeste, fora da rota de travessia.
	var crates := Vector3(1.8,0,-13.7)
	stage._solid("ServiceCrates",crates+Vector3(.05,.55,0),Vector3(2.0,1.1,1.3))
	stage._box(crates+Vector3(-.4,.35,.05),Vector3(.9,.7,.8),WOOD_LIGHT)
	stage._box(crates+Vector3(-.4,.36,.46),Vector3(.9,.05,.04),WOOD)
	stage._box(crates+Vector3(.55,.30,.05),Vector3(.8,.6,.7),WOOD_LIGHT,Vector3(0,.12,0))
	stage._box(crates+Vector3(-.4,.95,.05),Vector3(.6,.5,.6),WOOD_LIGHT,Vector3(0,.3,0))
	stage._cylinder(crates+Vector3(.3,.42,-.5),.3,.85,"4a4f52",Vector3.ZERO,10)
	for y in [.2,.66]: stage._cylinder(crates+Vector3(.3,y,-.5),.315,.05,"303a39",Vector3.ZERO,10)
	# Escoras de madeira só no lado da parede visível.
	for x_post in [9.5,16.5,22.0]:
		stage._box(Vector3(x_post,1.55,-14.28),Vector3(.26,3.1,.26),WOOD)
		stage._box(Vector3(x_post,3.0,-13.6),Vector3(.2,.2,1.5),WOOD_LIGHT)
		stage._box(Vector3(x_post,2.4,-13.74),Vector3(.14,.14,1.6),WOOD,Vector3(-.84,0,0))
	stage._box(Vector3(16.5,2.68,-13.3),Vector3(.02,.24,.02),"777063")
	stage._box(Vector3(16.5,2.5,-13.3),Vector3(.14,.2,.14),"c9a75f")
	# Setas de giz: o trajeto que Vicente marcou até o quartel.
	for arrow_x in [14.0,26.0]: _chalk_arrow(stage,Vector3(arrow_x,1.05,-14.5))
	_shift_board(stage,Vector3(12.9,1.15,-14.5))

static func _chalk_arrow(stage,at: Vector3) -> void:
	stage._box(at,Vector3(.8,.05,.02),"b6a36e")
	for side in [-1.0,1.0]:
		stage._box(at+Vector3(.28,side*.09,0),Vector3(.30,.05,.02),"b6a36e",Vector3(0,0,-side*.55))

static func _shift_board(stage,at: Vector3) -> void:
	# Quadro de turnos da manutenção (audio_maintenance_shift): traços de giz
	# terminam antes da última linha, no dia do apagão.
	stage._box(at,Vector3(1.5,.9,.04),"2b312e")
	for y in [-.47,.47]: stage._box(at+Vector3(0,y,.01),Vector3(1.62,.09,.06),WOOD)
	for side in [-.79,.79]: stage._box(at+Vector3(side,0,.01),Vector3(.09,.9,.06),WOOD)
	var groups := [3,3,2]
	for row in groups.size():
		for group in groups[row]:
			var origin := at+Vector3(-.5+float(group)*.42,.28-float(row)*.2,.03)
			for stroke in 4: stage._box(origin+Vector3(float(stroke)*.06,0,0),Vector3(.02,.15,.01),"b8ad8d")
			if not (row == 2 and group == 1): stage._box(origin+Vector3(.09,0,.005),Vector3(.26,.02,.01),"b8ad8d",Vector3(0,0,.55))
	stage._box(at+Vector3(1.15,.2,.02),Vector3(.36,.15,.30),"8b744a",Vector3(0,.3,0))
	stage._box(at+Vector3(1.15,.10,.02),Vector3(.42,.04,.36),"8b744a",Vector3(0,.3,0))

# --- Arcos emparedados: ramais do Porto Sul e da serra -----------------------

static func _sealed_arches(stage) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 195109
	_sealed_arch(stage,4.5,-14.5,rng)
	_mark_ring(stage,Vector3(4.5+1.75,1.6,-14.5))
	_sealed_arch(stage,28.0,-14.5,rng)
	_mark_triangle(stage,Vector3(28.0+1.75,1.55,-14.5))

static func _sealed_arch(stage,x: float,zf: float,rng: RandomNumberGenerator) -> void:
	stage._box(Vector3(x,1.15,zf-.01),Vector3(2.1,2.3,.04),"141a18")
	for side in [-1.0,1.0]:
		for stone in 4:
			stage._box(Vector3(x+side*1.1,.3+float(stone)*.55,zf+.02),Vector3(.34,.5,.16),STONE[(stone+int(side)+2)%4])
	for index in 7:
		var t := (float(index)-3.0)/3.0
		stage._box(Vector3(x+t*1.05,2.15+(1.0-absf(t))*.5,zf+.02),Vector3(.42,.34,.16),STONE[index%4],Vector3(0,0,-t*.6))
	var fill := [.95,.92,.9,.7,.45,.25]
	for row in fill.size():
		var y := .17+float(row)*.36
		var cursor := -.95 if row%2==0 else -.95+.31
		while cursor < .95:
			var width := .62
			if rng.randf() < fill[row]:
				var run := minf(width,.95-cursor)
				if run > .2:
					stage._box(Vector3(x+cursor+run*.5,y,zf+.04),Vector3(run-.04,.32,.12),STONE[rng.randi()%4],Vector3(0,0,rng.randf_range(-.03,.03)))
			cursor += width
	for side in [-1.0,1.0]: stage._box(Vector3(x,1.25,zf+.11),Vector3(2.3,.14,.05),WOOD,Vector3(0,0,side*.42))
	stage._box(Vector3(x,1.25,zf+.15),Vector3(.14,.2,.06),"8b744a")
	stage._box(Vector3(x-.5,.14,zf+.5),Vector3(.7,.28,.5),"424943",Vector3(.1,.5,.06))
	stage._box(Vector3(x+.45,.10,zf+.6),Vector3(.55,.20,.42),"4e5750",Vector3(-.1,-.4,.1))
	stage._box(Vector3(x+.15,.05,zf+.95),Vector3(.9,.06,.6),"3a382f",Vector3(0,.3,0))

static func _mark_ring(stage,at: Vector3) -> void:
	stage._cylinder(at,.30,.03,"3f7f91",Vector3(PI*.5,0,0),16)
	stage._cylinder(at+Vector3(0,0,.012),.19,.03,"252b27",Vector3(PI*.5,0,0),16)
	stage._cylinder(at+Vector3(0,0,.024),.07,.03,"3f7f91",Vector3(PI*.5,0,0),10)

static func _mark_triangle(stage,at: Vector3) -> void:
	stage._box(at+Vector3(0,-.30,0),Vector3(.72,.07,.03),"9b5a34")
	stage._box(at+Vector3(-.175,0,0),Vector3(.72,.07,.03),"9b5a34",Vector3(0,0,1.047))
	stage._box(at+Vector3(.175,0,0),Vector3(.72,.07,.03),"9b5a34",Vector3(0,0,-1.047))

static func _mark_square(stage,at: Vector3) -> void:
	for y in [-.28,.28]: stage._box(at+Vector3(0,y,0),Vector3(.62,.07,.03),"5f9a5a")
	for x in [-.28,.28]: stage._box(at+Vector3(x,0,0),Vector3(.07,.62,.03),"5f9a5a")

# --- Estação de bombeamento (map_pump_station) -------------------------------

static func _pump_station(stage) -> void:
	var p := Vector3(35.0,0,-4.7)
	stage._solid("PumpStation",p+Vector3(0,.6,0),Vector3(1.2,1.2,1.7))
	stage._box(p+Vector3(0,.12,0),Vector3(1.2,.24,1.7),"303a39")
	stage._cylinder(p+Vector3(-.1,.72,-.3),.36,1.0,"5b674f",Vector3(PI*.5,0,0),12)
	for z in [-.6,-.4,-.2,0.0]: stage._cylinder(p+Vector3(-.1,.72,z),.40,.05,"4b4437",Vector3(PI*.5,0,0),12)
	stage._cylinder(p+Vector3(.05,.66,.62),.5,.55,"696d65",Vector3(PI*.5,0,0),12)
	stage._box(p+Vector3(.05,1.05,.62),Vector3(.3,.3,.3),"696d65")
	# Recalque sobe rente à parede até o teto, longe da altura da cabeça.
	stage._pipe(p+Vector3(-.5,1.2,.62),p+Vector3(-.5,3.0,.62),.08,"6f6657")
	stage._cylinder(p+Vector3(.05,.66,.93),.27,.03,"8d3f35",Vector3(PI*.5,0,0),12)
	stage._box(p+Vector3(.05,.66,.95),Vector3(.56,.04,.03),"8d3f35")
	stage._box(p+Vector3(.05,.66,.95),Vector3(.04,.56,.03),"8d3f35")
	stage._cylinder(p+Vector3(.05,.66,.97),.06,.05,"777063",Vector3(PI*.5,0,0),8)
	stage._cylinder(p+Vector3(-.45,1.05,.90),.12,.04,"c9a75f",Vector3(PI*.5,0,0),12)
	stage._box(p+Vector3(-.45,1.06,.925),Vector3(.02,.09,.01),"76564a",Vector3(0,0,.7))
	stage._pipe(p+Vector3(-.10,.30,.62),p+Vector3(-.10,.30,1.6),.09,"6f6657")
	stage._puddle(p+Vector3(-.2,.014,1.75),Vector2(.9,.5),.3,"243b3a",2)
	# Grade de drenagem no piso, com água parada por baixo.
	var grate := Vector3(37.3,0,-6.3)
	stage._box(grate+Vector3(0,.005,0),Vector3(1.24,.01,.84),"141a18")
	for index in 8: stage._box(grate+Vector3(0,.022,-.36+float(index)*.103),Vector3(1.2,.025,.05),"777063")
	for side in [-1.0,1.0]: stage._box(grate+Vector3(side*.6,.016,0),Vector3(.06,.04,.9),"303a39")
	_glow(stage,p+Vector3(1.0,2.0,.9),Color("8fb3a0"),3.6,.42)

static func _glow(stage,at: Vector3,color: Color,reach: float,energy: float) -> void:
	# Luz sem luminária: usada onde a fonte é uma lanterna ou o próprio equipamento.
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.omni_range = reach
	lamp.light_energy = energy*4.0
	lamp.shadow_enabled = false
	lamp.set_meta("base_energy",energy*4.0)
	stage.add_child(lamp)
	stage.lights.append(lamp)

# --- Ramal de energia (map_power_branch, power_*) ----------------------------

static func _power_branch(stage) -> void:
	var at := Vector3(41.5,1.45,-.48)
	stage._box(at,Vector3(1.05,1.35,.14),"3d4541")
	for y in [-.66,.66]: stage._box(at+Vector3(0,y,.03),Vector3(1.13,.07,.16),"303a39")
	# Um farol por nó (principal, drenagem, setor selado); só o principal aceso.
	var lamp_colors := ["6b8f6a","76564a","76564a"]
	for index in 3:
		var x := -.3+float(index)*.3
		stage._cylinder(at+Vector3(x,.42,.09),.065,.05,lamp_colors[index],Vector3(PI*.5,0,0),10)
		stage._box(at+Vector3(x,-.05,.08),Vector3(.05,.36,.03),"777063")
		stage._box(at+Vector3(x,.10 if index==0 else -.20,.10),Vector3(.10,.07,.05),"8b744a")
	stage._box(at+Vector3(0,.08,.085),Vector3(.98,.05,.02),"8b744a")
	var points: Array[Vector3] = []
	for index in 8:
		var x := 42.0+float(index)*1.2
		var sag := .16 if index%2 else -.06
		points.append(Vector3(x,1.12+sag,-.53))
	for index in points.size()-1: stage._pipe(points[index],points[index+1],.03,"292d2a")
	for point in points: stage._box(point+Vector3(0,.09,.0),Vector3(.10,.16,.06),"777063")

# --- Casco do QG: parede sul, tapete, caixas ---------------------------------

static func _headquarters_shell(stage) -> void:
	var c: Vector3 = stage.HQ_CENTER
	var rng := RandomNumberGenerator.new()
	rng.seed = 195110
	# O QG não tinha parede sul: o jogador podia cair no vazio. O colisor é de
	# altura cheia; o visual é baixo e quebrado para não esconder a sala da câmera.
	var wall_z := c.z+7.6
	stage._solid("HeadquartersSouthWall",Vector3(c.x,1.7,wall_z),Vector3(15.6,3.4,.35))
	var x := c.x-7.775
	var index := 0
	while x < c.x+7.775:
		var width := minf(rng.randf_range(1.0,1.6),c.x+7.775-x)
		var height := rng.randf_range(.5,1.15)
		stage._box(Vector3(x+width*.5,height*.5,wall_z),Vector3(width-.05,height,.35),STONE[index%4])
		stage._box(Vector3(x+width*.5,height*.5+.05,wall_z+.19),Vector3(width-.16,height-.16,.03),STONE[(index+2)%4])
		if rng.randf() < .4: stage._box(Vector3(x+width*.5,.10,wall_z+.6),Vector3(.5,.20,.4),"424943",Vector3(.1,rng.randf_range(0,PI),.08))
		x += width
		index += 1
	# Tapete gasto sob a mesa de operações.
	var rug := c+Vector3(0,.0,1.2)
	stage._box(rug,Vector3(5.0,.02,3.6),"5c3f3a")
	for z in [-1.72,1.72]: stage._box(rug+Vector3(0,0,z),Vector3(5.0,.024,.14),"7c6247")
	for side in [-2.43,2.43]: stage._box(rug+Vector3(side,0,0),Vector3(.14,.024,3.6),"7c6247")
	# Lampião sobre a mesa: emissivo, sem luz real.
	var lantern := c+Vector3(1.5,.93,.4)
	stage._cylinder(lantern,.10,.05,"303a39",Vector3.ZERO,8)
	stage._cylinder(lantern+Vector3(0,.11,0),.075,.16,"c9a75f",Vector3.ZERO,8)
	stage._cylinder(lantern+Vector3(0,.21,0),.09,.03,"303a39",Vector3.ZERO,8)
	# Suprimentos no canto sudeste e tambores junto ao gerador.
	var stack := c+Vector3(6.3,0,6.5)
	stage._solid("SupplyCrates",stack+Vector3(0,.62,0),Vector3(1.05,1.25,1.0))
	stage._box(stack+Vector3(0,.3,0),Vector3(.95,.6,.9),WOOD_LIGHT)
	stage._box(stack+Vector3(.05,.9,0),Vector3(.8,.5,.75),WOOD_LIGHT,Vector3(0,.25,0))
	stage._box(stack+Vector3(0,.31,.46),Vector3(.9,.05,.04),WOOD)
	stage._solid("FuelDrums",c+Vector3(-2.1,.45,6.6),Vector3(1.3,.9,.7))
	for drum in [[-2.4,"6b3f36"],[-1.8,"3d4a55"]]:
		stage._cylinder(c+Vector3(drum[0],.45,6.6),.3,.9,drum[1],Vector3.ZERO,10)
		for y in [.15,.75]: stage._cylinder(c+Vector3(drum[0],y,6.6),.315,.05,"303a39",Vector3.ZERO,10)

# --- Mural de investigação (fragmentos, foto do incidente, crachá, relatório) -

static func _pinboard(stage) -> void:
	var c: Vector3 = stage.HQ_CENTER
	var zb := c.z-7.17
	var mid := Vector3(c.x-5.15,2.3,zb)
	stage._box(mid,Vector3(3.4,1.5,.04),"8a6f4b")
	for y in [-.75,.75]: stage._box(mid+Vector3(0,y,.01),Vector3(3.5,.09,.06),WOOD)
	for x in [-1.7,1.7]: stage._box(mid+Vector3(x,0,.01),Vector3(.09,1.5,.06),WOOD)
	var pins: Array[Vector3] = []
	var index := 0
	for row in 2:
		for col in 3:
			var at := mid+Vector3(-1.15+float(col)*.75,.36-float(row)*.64,.03)
			var tilt := .06*float((index*5)%3-1)
			stage._box(at,Vector3(.62,.48,.012),PAPER[index%2],Vector3(0,0,tilt))
			stage._box(at+Vector3(-.06,.08,.008),Vector3(.38,.025,.006),"526f73",Vector3(0,0,tilt+.2))
			stage._box(at+Vector3(.05,-.07,.008),Vector3(.30,.025,.006),"5c5850",Vector3(0,0,tilt-.3))
			pins.append(at+Vector3(0,.2,.022))
			index += 1
	# O sexto fragmento (anexo lacrado) está rasgado e manchado.
	stage._box(mid+Vector3(.35,-.32,.04),Vector3(.30,.20,.014),"3a1f1d",Vector3(0,0,.5))
	for photo in [Vector2(1.22,.42),Vector2(1.25,-.24)]:
		var at := mid+Vector3(photo.x,photo.y,.03)
		stage._box(at,Vector3(.38,.30,.012),"d8d2bf",Vector3(0,0,photo.x*.05))
		stage._box(at+Vector3(0,.01,.008),Vector3(.32,.22,.006),"2d2f2c")
		pins.append(at+Vector3(0,.13,.022))
	stage._box(mid+Vector3(1.28,-.22,.045),Vector3(.10,.16,.004),"5c625a",Vector3(0,0,.3))
	for pair in [[0,1],[1,4],[4,2],[2,6],[6,7],[3,4],[5,7]]:
		stage._pipe(pins[pair[0]],pins[pair[1]],.008,"8d3f35")
	for pin in pins: stage._cylinder(pin,.03,.04,"9f513f",Vector3(PI*.5,0,0),8)
	# Prancheta do relatório de energia e crachá de acesso do laboratório.
	var clip := Vector3(c.x-3.15,1.55,zb)
	stage._box(clip,Vector3(.34,.46,.02),WOOD)
	stage._box(clip+Vector3(0,-.01,.014),Vector3(.28,.38,.008),"b8ad8d")
	stage._box(clip+Vector3(0,.24,.02),Vector3(.14,.05,.03),"777063")
	for line in 4: stage._box(clip+Vector3(0,.10-float(line)*.07,.02),Vector3(.20,.014,.004),"5c5850")
	var badge := Vector3(c.x-2.82,1.6,zb)
	stage._box(badge+Vector3(0,.32,0),Vector3(.02,.42,.012),"324b58")
	stage._box(badge,Vector3(.24,.34,.014),"b8ad8d")
	stage._box(badge+Vector3(0,.09,.01),Vector3(.20,.07,.004),"9f513f")
	stage._box(badge+Vector3(-.03,-.05,.01),Vector3(.12,.10,.004),"2d2f2c")
	_glow(stage,Vector3(c.x-4.2,3.0,c.z-5.4),Color("d0a15e"),4.6,.5)

# --- Escotilhas dos ramais (rota do esgoto, Porto Sul, serra) ----------------

static func _route_hatches(stage) -> void:
	var c: Vector3 = stage.HQ_CENTER
	var zb := c.z-7.17
	var hatches := [
		{"x":3.4,"mark":"ring","open":false},
		{"x":4.75,"mark":"square","open":true},
		{"x":6.1,"mark":"triangle","open":false},
	]
	for hatch in hatches:
		var at := Vector3(c.x+float(hatch.x),1.5,zb)
		stage._cylinder(at,.52,.07,"303a39",Vector3(PI*.5,0,0),16)
		stage._cylinder(at+Vector3(0,0,.04),.43,.09,"4b5550",Vector3(PI*.5,0,0),16)
		stage._box(at+Vector3(0,0,.10),Vector3(.72,.05,.05),"777063")
		stage._box(at+Vector3(0,0,.10),Vector3(.05,.72,.05),"777063")
		stage._cylinder(at+Vector3(0,0,.12),.07,.05,"777063",Vector3(PI*.5,0,0),8)
		stage._box(at+Vector3(.28,-.38,.10),Vector3(.05,.6,.02),"5b4030",Vector3(0,0,.05))
		var mark_at := at+Vector3(0,.95,-.02)
		match hatch.mark:
			"ring": _mark_ring(stage,mark_at)
			"square": _mark_square(stage,mark_at)
			"triangle": _mark_triangle(stage,mark_at)
		if hatch.open:
			stage._cylinder(at+Vector3(0,.78,.02),.06,.05,"6b8f6a",Vector3(PI*.5,0,0),8)
			stage._box(at+Vector3(0,-.52,.06),Vector3(.85,.06,.5),"243b3a")
		else:
			for side in [-1.0,1.0]: stage._box(at+Vector3(0,0,.16),Vector3(.95,.05,.05),"6f6657",Vector3(0,0,side*.6))
			stage._box(at+Vector3(0,0,.20),Vector3(.14,.18,.06),"8b744a")

# --- Fitas de Vicente e gaveteiros do arquivo --------------------------------

static func _archive_and_tapes(stage) -> void:
	var c: Vector3 = stage.HQ_CENTER
	var rng := RandomNumberGenerator.new()
	rng.seed = 195111
	stage._solid("FilingCabinets",c+Vector3(-5.5,.74,-6.95),Vector3(2.4,1.48,.5))
	for cabinet in 3:
		var x := -6.3+float(cabinet)*.8
		var at := c+Vector3(x,.72,-6.94)
		stage._box(at,Vector3(.72,1.45,.48),"4b5550")
		for y in [-.45,.05,.55]:
			stage._box(at+Vector3(0,y,.245),Vector3(.62,.02,.02),"292d2a")
			stage._box(at+Vector3(0,y+.22,.255),Vector3(.20,.04,.03),"777063")
			stage._box(at+Vector3(0,y+.10,.25),Vector3(.20,.07,.01),"b8ad8d")
	# Gaveta aberta com pastas e folhas espalhadas no chão.
	var open_drawer := c+Vector3(-4.7,1.17,-6.62)
	stage._box(open_drawer,Vector3(.6,.24,.36),"4b5550")
	stage._box(open_drawer+Vector3(0,.16,0),Vector3(.5,.10,.30),"b8ad8d",Vector3(0,.1,0))
	for sheet in 6:
		stage._box(c+Vector3(-4.4+rng.randf_range(-.9,.9),.012,-6.0+rng.randf_range(-.4,.5)),Vector3(.36,.006,.26),PAPER[sheet%2],Vector3(0,rng.randf_range(0,PI),0))
	# Mesa do gravador: uma fita para cada registro de áudio.
	var table := c+Vector3(3.4,0,-5.0)
	stage._solid("TapeTable",table+Vector3(0,.42,0),Vector3(1.3,.85,.7))
	stage._box(table+Vector3(0,.82,0),Vector3(1.3,.06,.7),"675d4b")
	for x in [-.55,.55]:
		for z in [-.28,.28]: stage._box(table+Vector3(x,.4,z),Vector3(.10,.8,.10),"4a4133")
	stage._box(table+Vector3(-.15,.93,0),Vector3(.9,.16,.5),"3d4541")
	for x in [-.37,-.03]:
		stage._cylinder(table+Vector3(x,1.03,-.03),.20,.03,"777063",Vector3.ZERO,12)
		stage._cylinder(table+Vector3(x,1.045,-.03),.155,.035,"3b2f26",Vector3.ZERO,12)
		stage._cylinder(table+Vector3(x,1.06,-.03),.04,.04,"777063",Vector3.ZERO,8)
	stage._box(table+Vector3(-.15,.94,.22),Vector3(.7,.05,.06),"777063")
	for x in [.10,.20,.30]: stage._cylinder(table+Vector3(-.45+x*2.0,.93,.28),.03,.05,"8b744a",Vector3(PI*.5,0,0),8)
	var tape_colors := ["704f42","5b674f","796a4e","3a1f1d"]
	for index in tape_colors.size():
		stage._box(table+Vector3(.42,.875+float(index)*.06,.05),Vector3(.32,.055,.32),tape_colors[index],Vector3(0,.15*float(index%3-1),0))
	stage._box(table+Vector3(.42,1.12,.05),Vector3(.20,.005,.12),"b8ad8d",Vector3(0,.3,0))
	# Fones esquecidos ao lado do gravador.
	stage._cylinder(table+Vector3(.44,.86,-.26),.06,.03,"292d2a",Vector3.ZERO,8)
	stage._cylinder(table+Vector3(.30,.86,-.28),.06,.03,"292d2a",Vector3.ZERO,8)
	stage._box(table+Vector3(.37,.865,-.27),Vector3(.20,.015,.015),"292d2a")

# --- Setor lacrado: vestígios sem explicação ---------------------------------

static func _sealed_sector_traces(stage) -> void:
	var c: Vector3 = stage.HQ_CENTER
	var gate := c+Vector3(0,0,-7.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 195112
	var floor_y := -.005
	stage._puddle(gate+Vector3(.35,floor_y,-3.0),Vector2(.9,.6),.5,"3a1f1d",1)
	stage._puddle(gate+Vector3(-1.0,floor_y,-5.9),Vector2(.5,.4),-.3,"3a1f1d",3)
	for drag in 4: stage._box(gate+Vector3(-.3+float(drag)*.12,floor_y,-3.7-float(drag)*.28),Vector3(.06,.006,.7),"3a1f1d",Vector3(0,.35,0))
	# Suporte de soro com a bolsa ainda pendurada e o tubo caído até a maca.
	var stand := gate+Vector3(-1.55,0,-4.0)
	stage._box(stand+Vector3(0,floor_y,0),Vector3(.5,.03,.05),"777063")
	stage._box(stand+Vector3(0,floor_y,0),Vector3(.05,.03,.5),"777063")
	stage._box(stand+Vector3(0,.95,0),Vector3(.03,1.7,.03),"777063")
	stage._box(stand+Vector3(0,1.72,.03),Vector3(.11,.22,.04),"8fa3a5")
	stage._pipe(stand+Vector3(0,1.6,.03),gate+Vector3(-1.05,.85,-4.35),.012,"8fa3a5")
	# Prateleira de frascos: alguns quebrados no chão, outros ainda escuros por dentro.
	var shelf := gate+Vector3(-1.15,0,-6.5)
	for y in [.45,.95,1.45]: stage._box(shelf+Vector3(0,y,0),Vector3(2.0,.06,.35),WOOD)
	for x in [-.96,.96]: stage._box(shelf+Vector3(x,.75,0),Vector3(.07,1.6,.35),WOOD)
	for level in 3:
		for jar in 5:
			if level == 2 and jar == 3: continue
			var jar_x := -.78+float(jar)*.39
			stage._cylinder(shelf+Vector3(jar_x,.62+float(level)*.5,rng.randf_range(-.04,.04)),.10,.30,"6f8f86",Vector3.ZERO,8)
	stage._cylinder(gate+Vector3(-.2,floor_y+.06,-5.7),.10,.30,"6f8f86",Vector3(0,0,PI*.5),8)
	for shard in 9:
		stage._box(gate+Vector3(rng.randf_range(-1.6,-.1),floor_y+.004,rng.randf_range(-6.0,-4.9)),Vector3(rng.randf_range(.05,.16),.008,rng.randf_range(.04,.10)),"8fa3a5",Vector3(0,rng.randf_range(0,PI),0))
	for sheet in 5:
		stage._box(gate+Vector3(rng.randf_range(-1.7,1.6),floor_y+.004,rng.randf_range(-6.2,-2.4)),Vector3(.30,.006,.22),"b8ad8d",Vector3(0,rng.randf_range(0,PI),0))
	# Marcas de arranhão na parede do fundo, acima da prateleira.
	for scratch in 4:
		stage._box(gate+Vector3(-1.4+float(scratch)*.11,2.35,-6.70),Vector3(.025,.55,.01),"5c625a",Vector3(0,0,.12*float(scratch-2)))
	# Cadeira tombada.
	var chair := gate+Vector3(1.3,0,-3.4)
	stage._box(chair+Vector3(0,floor_y+.10,0),Vector3(.44,.05,.44),WOOD,Vector3(1.4,.4,0))
	for leg in [-.16,.16]: stage._box(chair+Vector3(leg,floor_y+.03,.28),Vector3(.05,.44,.05),WOOD,Vector3(1.5,.4,0))
