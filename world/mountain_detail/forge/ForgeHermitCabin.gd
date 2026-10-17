extends Node3D
## Cabana do Mestre Aurélio, o ferreiro aposentado que ensinou o Seu Bento. Fica sozinha
## no alto da serra, uns 480 m ao norte da forja e a ~55 m da Passagem de pedra, no fim de
## uma trilha que sai das pistas de esqui. Origem do nó = CENTER; a porta olha para +Z
## (de onde a trilha chega). Sem interior: só o pátio, a fogueira e o velho na porta.
const GEO := preload("res://world/mountain_detail/forge/ForgeGeometry.gd")
const RESIDENT := preload("res://world/mountain_detail/forge/ForgeResident.gd")
const CENTER := Vector3(700,0,-845)
const FOOTPRINT := Rect2(686,-858,28,27)
## Fogueira do pátio, local: é a fonte de calor `hermit_camp` (OriginalHeatSources).
const FIRE := Vector3(2.6,0,3.4)
const HERMIT_STAND := Vector3(.9,.06,3.2)
var hermit: Node3D
var session

## Trilha das pistas de esqui até o pátio; o terreno se aplana em volta dela.
static func approach() -> Dictionary:
	return {"id":"forge_hermit_trail","width":1.8,"points":PackedVector3Array([Vector3(714,0,-618),Vector3(709,0,-668),Vector3(702,0,-724),Vector3(697,0,-780),Vector3(699,0,-818),Vector3(700,0,-833)])}

func _ready() -> void:
	name = "ForgeHermitCabin"
	add_to_group("blade_forge_site")
	var g := GEO.new()
	GEO.polygon(self, PackedVector2Array([Vector2(-9,-9),Vector2(8,-10),Vector2(11,-2),Vector2(9,9),Vector2(-2,11),Vector2(-10,6)]), .035, Color("8d8a5a"))
	_cabin(g)
	_yard(g)
	g.flush(self)
	hermit = RESIDENT.new()
	hermit.name = "Hermit"
	hermit.site_id = "hermit"
	hermit.speaker = "Mestre Aurélio"
	hermit.identity = 742
	hermit.stand = HERMIT_STAND
	# Olhando a fogueira (+X).
	hermit.facing = -PI*.5
	add_child(hermit)

func nearest_action() -> Dictionary:
	return hermit.nearest_action() if is_instance_valid(hermit) else {}

func _cabin(g: RefCounted) -> void:
	# Cabana de toras 6 × 5 m sobre base de pedra, porta fechada, telhado coberto de neve.
	var c := Vector3(-1.5,0,-3.0)
	g.part("box", c+Vector3(0,.2,0), Vector3(6.4,.4,5.4), "6f6f65")
	for row in 7:
		var y := .55+float(row)*.38
		for side in [-1.0,1.0]:
			g.part("pole", c+Vector3(0,y,side*2.5), Vector3(.4,6.5,.4), "6a4b30" if row%2==0 else "5f432b", Vector3(0,0,PI*.5))
			g.part("pole", c+Vector3(side*3.0,y+.19,0), Vector3(.4,5.4,.4), "5f432b" if row%2==0 else "6a4b30", Vector3(PI*.5,0,0))
	GEO.solid(self, "CabinWalls", c+Vector3(0,1.6,0), Vector3(6.4,3.2,5.4))
	for side in [-1.0,1.0]:
		# Rotação positiva em X abaixa a ponta +Z: cada água desce para o seu lado.
		g.part("box", c+Vector3(0,3.75,side*1.45), Vector3(7.2,.2,3.4), "4d4038", Vector3(side*.55,0,0))
		g.part("box", c+Vector3(0,3.88,side*1.45), Vector3(7.3,.08,3.45), "e8ecef", Vector3(side*.55,0,0))
	# Porta, janela com luz quente e chaminé de pedra soltando calor da lareira.
	g.part("box", c+Vector3(.6,1.05,2.72), Vector3(1.0,1.9,.08), "3d3129")
	g.part("box", c+Vector3(-1.6,1.5,2.72), Vector3(.9,.7,.06), "d9a35a")
	g.part("box", c+Vector3(-1.6,1.5,2.75), Vector3(1.0,.08,.04), "3d3129")
	g.part("box", c+Vector3(2.4,2.9,-1.2), Vector3(.8,3.2,.8), "6f6f65")
	# Alpendre: tábuas e banco.
	g.part("box", c+Vector3(0,.42,3.25), Vector3(6.4,.08,1.1), "6b5236")
	g.part("box", c+Vector3(-1.7,.75,3.2), Vector3(1.6,.12,.45), "806044")
	GEO.solid(self, "PorchBench", c+Vector3(-1.7,.45,3.2), Vector3(1.6,.9,.5))

func _yard(g: RefCounted) -> void:
	# A bigorna velha do mestre, sem uso, com neve por cima: o ofício que ele largou.
	var anvil := Vector3(-6.2,0,2.0)
	g.part("pole", anvil+Vector3(0,.28,0), Vector3(.7,.56,.7), "5f4a33")
	g.part("box", anvil+Vector3(0,.68,0), Vector3(.32,.22,.58), "3a3634")
	g.part("box", anvil+Vector3(0,.85,0), Vector3(.4,.12,.74), "3f3b38")
	g.part("box", anvil+Vector3(0,.93,0), Vector3(.38,.03,.7), "e8ecef")
	GEO.solid(self, "OldAnvil", anvil+Vector3(0,.45,0), Vector3(.75,.9,.85))
	# Toco de rachar lenha com machado cravado e a pilha ao lado.
	var block := Vector3(5.6,0,-1.5)
	g.part("pole", block+Vector3(0,.3,0), Vector3(.7,.6,.7), "6a4b30")
	g.part("box", block+Vector3(.1,.75,0), Vector3(.06,.5,.06), "806044", Vector3(0,0,.5))
	g.part("box", block+Vector3(-.02,.62,0), Vector3(.2,.14,.04), "2d3033", Vector3(0,0,.5))
	GEO.solid(self, "ChoppingBlock", block+Vector3(0,.3,0), Vector3(.7,.6,.7))
	for row in 2:
		for i in 4-row:
			g.part("pole", Vector3(6.4,.18+row*.32,-4.6+float(i)*.36+row*.18), Vector3(.32,1.6,.32), "7a5a3a", Vector3(0,0,PI*.5))
	GEO.solid(self, "CabinWoodpile", Vector3(6.4,.4,-4.1), Vector3(1.7,.8,1.6))
	# Troncos-banco em volta da fogueira (a fogueira em si vem da fonte de calor).
	for at in [FIRE+Vector3(1.8,0,.4), FIRE+Vector3(-.2,0,1.9)]:
		g.part("pole", at+Vector3(0,.22,0), Vector3(.42,1.3,.42), "6a4b30", Vector3(0,0,PI*.5))
		GEO.solid(self, "LogSeat", at+Vector3(0,.22,0), Vector3(1.3,.44,.45))
	for i in 9:
		var angle := float(i)/9.0*TAU
		g.part("round", Vector3(cos(angle)*12.0,.25,sin(angle)*11.5), Vector3(1.4,.8,1.1), "62704b" if i%3 else "77776c")
