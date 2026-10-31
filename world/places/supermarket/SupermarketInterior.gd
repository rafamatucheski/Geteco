extends "res://world/places/supermarket/MarketGeometry.gd"
const PALETTE := ["b34834","dda744","5d874e","437b94","e5d4a5","855671","df763f","32554e"]
## Acabamento com textura de verdade (playtest de 30/10: "ainda tá com as texturas antigas"):
## piso, paredes, gôndolas, balcões, geladeiras e caixotes passam pelos mapas do
## MountainInteriorFinish, o mesmo conjunto de shader do UrbanSurfaces que o Harbor inteiro
## desenha (nada compila ao entrar). Produtos, luminárias e miudezas seguem lisos, em lote.
## GETECO_SUPERMARKET_FINISH=0 volta às caixas lisas (A/B).
const FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const FINISH_KINDS := {"Terrazzo":"epoxy","RearWall":"plaster","SideWall":"plaster","FrontWall":"plaster",
	"Gondola":"painted","Produce":"wood","Crate":"wood","Bakery":"wood","Fridge":"painted",
	"Checkout":"painted","SecurityCabinet":"painted","BasketStand":"painted","EntryMat":"fabric"}
## Vidro da geladeira e puxador continuam lisos.
const FINISH_SKIP := ["FridgeInset", "FridgeHandle"]
## (rótulo, cor, metal) de cada peça texturizada abaixo, para o PaintedFacadePrewarm desenhar os
## mesmos materiais (a chave do cache é tipo + cor + rugosidade + metal) sob a cortina do
## carregamento: a entrada pela porta de empurrar não tem véu e as texturas subiriam para a GPU
## no primeiro quadro dentro da loja. Peça nova texturizada entra aqui também.
const PREWARM := [["Terrazzo","9a9b8e",false],["RearWall","e1d8bf",false],["SideWall","d8d2c1",false],
	["FrontWall","c5cab5",false],["Gondola","e2dbc4",false],["Gondola","46544a",false],["Gondola","e0dbcd",false],
	["Gondola","d9d9cc",false],["Produce","846443",false],["Crate","ba9862",false],["Bakery","977550",false],
	["Fridge","3a4849",true],["Fridge","485654",true],["Checkout","345e4b",false],["Checkout","c0c3b4",false],
	["SecurityCabinet","4d5652",false],["BasketStand","315e49",false],["EntryMat","354c43",false]]
var textured := enabled()

static func enabled() -> bool:
	return OS.get_environment("GETECO_SUPERMARKET_FINISH") != "0"

static func finish_material(label: String, color: String, metal: bool) -> StandardMaterial3D:
	if label in FINISH_SKIP: return null
	for prefix in FINISH_KINDS:
		if label.begins_with(prefix):
			return FINISH.material(FINISH_KINDS[prefix], Color(color), .5 if metal else .88, .35 if metal else 0.0)
	return null

static func prewarm_materials() -> Array:
	var list: Array = []
	if not enabled(): return list
	for row in PREWARM: list.append(finish_material(row[0], row[1], row[2]))
	return list
func _ready() -> void:
	if textured:
		# Piso único de epóxi: o xadrez de 252 ladrilhos em MultiMesh com o material texturizado
		# seria outra variante de pipeline (instância), compilada na primeira entrada.
		box("Terrazzo",Vector3(0,-.035,0),Vector3(18,.06,14),"9a9b8e")
	else:
		box("Terrazzo",Vector3(0,-.035,0),Vector3(18,.06,14),"b5b3a4")
		for x in range(-9,9):
			for z in range(-7,7):
				piece("box",Vector3(x+.5,.001,z+.5),Vector3(.984,.012,.984),"848679" if (x+z)%2 == 0 else "8e9081")
	box("RearWall",Vector3(0,1.7,-6.9),Vector3(18,3.4,.2),"e1d8bf",true)
	for side in [-1,1]:
		box("SideWall%d"%side,Vector3(side*8.9,1.7,0),Vector3(.2,3.4,14),"d8d2c1",true)
		box("FrontWall%d"%side,Vector3(side*5,.65,6.9),Vector3(8,1.3,.2),"c5cab5",true)
		box("GreenTrim%d"%side,Vector3(side*8.77,2.65,0),Vector3(.045,.3,13.7),"2e6150")
	box("RearTrim",Vector3(0,2.65,-6.77),Vector3(17.6,.3,.045),"2e6150")
	# Gondolas stay below eye level, with wide continuous aisles around all ends.
	for index in 4: _gondola(index,-4.8+index*3.2)
	_produce()
	_bakery()
	_fridges()
	for side in [-1,1]: _checkout(side)
	_armor_display()
	box("EntryMat",Vector3(0,.018,5.95),Vector3(2.0,.025,1.5),"354c43")
	# O suporte de cestas usa uma área de colisão completa, incluindo as alças.
	box("BasketStand",Vector3(-1.65,.35,5.8),Vector3(.7,.7,.7),"315e49",true)
	for layer in 5:
		for side in [-1,1]: piece("box",Vector3(-1.65+side*.31,.23+layer*.12,5.8),Vector3(.025,.09,.62),"d2a34e")
	# As luminárias têm um difusor emissivo estável; só duas fontes locais amplas.
	for x in [-4.8,-1.6,1.6,4.8]:
		for z in [-3.5,1.5]:
			box("Pendant",Vector3(x,3.2,z),Vector3(.24,.10,1.6),"45514c",false,true)
			var diffuser := box("Diffuser",Vector3(x,3.135,z),Vector3(.18,.025,1.5),"fff0cd")
			diffuser.material_override = material("fff0cd",false,true)
	for x in [-4.5,4.5]:
		var light := OmniLight3D.new()
		light.position = Vector3(x,4.3,-1)
		light.light_color = Color("fff1d4")
		light.light_energy = .55
		light.omni_range = 12
		light.shadow_enabled = false
		add_child(light)
	flush_batches()

func box(label: String, point: Vector3, size: Vector3, color: String, solid := false, metal := false) -> MeshInstance3D:
	var node := super.box(label, point, size, color, solid, metal)
	if textured:
		var finish := finish_material(label, color, metal)
		if finish != null: node.material_override = finish
	return node

func _gondola(index: int,x: float) -> void:
	var id := "Gondola%d"%index
	box(id,Vector3(x,.77,-.7),Vector3(.16,1.54,5.2),"e2dbc4",true)
	box(id,Vector3(x,.12,-.7),Vector3(1.1,.24,5.2),"46544a",true)
	for z in [-3.25,1.85]:
		box(id,Vector3(x,.8,z),Vector3(1.1,1.6,.08),"e0dbcd",true)
	for level in 4:
		var y := .27+level*.39
		box(id,Vector3(x,y,-.7),Vector3(1.1,.055,5.2),"d9d9cc",true)
		for side in [-1,1]:
			piece("box",Vector3(x+side*.552,y-.02,-.7),Vector3(.018,.06,5.15),"315d48")
			for bay in 12:
				var z := -3.02+bay*.415
				for depth in 2:
					product((index+level)%4,Vector3(x+side*(.20+depth*.21),y+.032,z),PALETTE[(index*2+int(bay/3.0))%PALETTE.size()])
				piece("box",Vector3(x+side*.565,y-.015,z),Vector3(.012,.035,.10),"f4e9c5")

func _produce() -> void:
	for i in 6:
		var x := -5.5+i*2.2
		box("Produce%d"%i,Vector3(x,.48,-5.8),Vector3(2.05,.96,1.15),"846443",true)
		box("Crate%d"%i,Vector3(x,1,-5.8),Vector3(1.98,.12,1.08),"ba9862")
		for a in 8:
			for b in 4: product(4,Vector3(x-.82+a*.23,1.07,-6.15+b*.23),["b94832","a5a73e","e0a43e","6c8c45","ad6241","d2b568"][i])
		for side in [-1,1]: piece("box",Vector3(x+side*.99,1.17,-5.8),Vector3(.045,.30,1.10),"876744")

func _bakery() -> void:
	for i in 3:
		var z := -3.2+i*2.1
		box("Bakery%d"%i,Vector3(-8,.62,z),Vector3(1.15,1.24,1.95),"977550",true)
		for level in 3:
			piece("box",Vector3(-8,.50+level*.42,z),Vector3(1.1,.05,1.85),"d6b486")
			for a in 3:
				for b in 6: product(4,Vector3(-8.32+a*.3,.54+level*.42,z-.76+b*.29),"c89650" if b%2 else "e4bb78")

func _fridges() -> void:
	for i in 4:
		var z := -3.65+i*1.65
		box("Fridge%d"%i,Vector3(8,1.08,z),Vector3(1.2,2.16,1.55),"3a4849",true,true)
		box("Fridge%d"%i,Vector3(7.78,.11,z),Vector3(1.7,.22,1.55),"485654",true,true)
		box("FridgeInset",Vector3(7.385,1.1,z),Vector3(.045,1.87,1.40),"c1d3cb")
		for level in 4:
			piece("box",Vector3(7.2,.27+level*.43,z),Vector3(.38,.04,1.35),"bac8bd")
			for b in 6: product(1,Vector3(7.18,.30+level*.43,z-.57+b*.23),PALETTE[(i+level)%8])
		box("FridgeHandle",Vector3(7.06,1.10,z+.63),Vector3(.045,.72,.04),"283c3b",false,true)

func _checkout(side: int) -> void:
	var x := side*5.4
	box("Checkout%d"%side,Vector3(x,.51,4.4),Vector3(1.2,1.02,2.45),"345e4b",true)
	box("Checkout%d"%side,Vector3(x,1.05,4.4),Vector3(1.28,.10,2.5),"c0c3b4",true)
	box("Conveyor",Vector3(x,1.115,3.9),Vector3(.9,.035,1.25),"303b3c")
	for z in [3.31,4.49]: piece("round",Vector3(x,1.13,z),Vector3(.055,.04,.055),"acb3ac")
	box("Scanner",Vector3(x,1.13,4.65),Vector3(.45,.045,.40),"293b3b")
	box("ScannerGlass",Vector3(x,1.158,4.65),Vector3(.22,.009,.27),"577a75")
	box("Till",Vector3(x,1.16,5.1),Vector3(.5,.18,.42),"c7c9bc")
	box("TillScreen",Vector3(x,1.4,5.09),Vector3(.44,.27,.075),"30423d")
	box("TillDisplay",Vector3(x,1.4,5.134),Vector3(.35,.19,.009),"82a893")
	box("CardReader",Vector3(x-side*.42,1.18,4.96),Vector3(.16,.16,.27),"263735")
	for i in 3: product(i,Vector3(x-.28+i*.25,1.15,3.9),PALETTE[i+1])
	box("PaperBag",Vector3(x,1.32,5.48),Vector3(.35,.40,.25),"b89a6c")

func _armor_display() -> void:
	box("SecurityCabinet",Vector3(-7.8,1.2,5.35),Vector3(1.2,2.4,1.0),"4d5652",true)
	box("SecurityCabinet",Vector3(-7.8,.10,5.5),Vector3(1.2,.2,1.15),"4d5652",true)
	box("CabinetBack",Vector3(-7.8,1.2,5.87),Vector3(1.1,2.25,.05),"a5af9c")
	for x in [-8.08,-7.52]:
		box("Vest",Vector3(x,1.35,5.93),Vector3(.42,.56,.13),"323f40")
		for side in [-1,1]: box("VestStrap",Vector3(x+side*.13,1.69,5.94),Vector3(.10,.20,.11),"36494a")
		for side in [-1,1]: box("VestPocket",Vector3(x+side*.105,1.29,6.015),Vector3(.18,.16,.055),"53605b")
