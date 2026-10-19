extends RefCounted
## Geometria dos lugares da beira de estrada, só com caixas e cilindros do DesertGeometry
## (materiais em cache por cor: nenhum shader novo). A frente de cada lugar é o +z local,
## virado para a estrada. Sem luz nova: os lugares ficam no escuro à noite, como as casinhas.
const G := preload("res://world/desert/DesertGeometry.gd")

static func station(root: Node3D) -> void:
	var paint := Color("d8c9a8")
	var trim := Color("8a5a3c")
	# Pátio de concreto gasto, cobertura sobre duas bombas e a loja ao fundo.
	G.box(root, "Forecourt", Vector3(0, .03, 5), Vector3(22, .06, 14), Color("a89f90"))
	for x in [-6.0, 6.0]:
		for z in [3.0, 9.0]: G.cylinder(root, "CanopyPost", Vector3(x, 2.4, z), .18, 4.8, Color("d9d4c9"), true)
	G.box(root, "Canopy", Vector3(0, 4.95, 6), Vector3(14, .32, 9), Color("b5533c"))
	G.box(root, "CanopyStripe", Vector3(0, 4.72, 10.52), Vector3(14, .22, .06), Color("e3c25e"))
	for x in [-2.5, 2.5]:
		G.box(root, "Pump", Vector3(x, .8, 6), Vector3(.8, 1.6, .55), Color("c9b98f"), true)
		G.box(root, "PumpHead", Vector3(x, 1.75, 6), Vector3(.9, .3, .65), Color("b5533c"))
	G.box(root, "PumpIsland", Vector3(0, .12, 6), Vector3(8.5, .24, 1.4), Color("cfc8b8"), true)
	# Loja com vitrine e porta; oficina aberta à direita, onde o mecânico atende.
	G.box(root, "ShopBack", Vector3(0, 1.7, -7.4), Vector3(11, 3.4, .3), paint, true)
	for x in [-5.5, 5.5]: G.box(root, "ShopSide", Vector3(x, 1.7, -4.3), Vector3(.3, 3.4, 6.2), paint.darkened(.05), true)
	G.box(root, "ShopFront", Vector3(-3.2, 1.7, -1.2), Vector3(4.6, 3.4, .3), paint, true)
	G.box(root, "ShopFront", Vector3(3.6, 1.7, -1.2), Vector3(3.8, 3.4, .3), paint, true)
	G.box(root, "ShopWindow", Vector3(-3.2, 1.7, -1.02), Vector3(3.4, 1.3, .05), Color("3a4146"))
	G.box(root, "ShopDoor", Vector3(.6, 1.15, -1.02), Vector3(1.2, 2.3, .05), Color("4a3a2c"))
	G.box(root, "ShopRoof", Vector3(0, 3.5, -4.3), Vector3(11.6, .25, 6.8), trim)
	G.box(root, "GarageBack", Vector3(8.5, 2.0, -3.6), Vector3(6.4, 4.0, .3), paint.darkened(.08), true)
	G.box(root, "GarageSide", Vector3(11.6, 2.0, -.6), Vector3(.3, 4.0, 6.0), paint.darkened(.08), true)
	G.box(root, "GarageRoof", Vector3(8.5, 4.1, -.6), Vector3(6.8, .25, 6.4), trim)
	G.box(root, "Workbench", Vector3(10.6, .5, -2.2), Vector3(1.4, 1.0, 2.4), Color("6a5136"), true)
	G.cylinder(root, "TireStack", Vector3(6.2, .5, -2.6), .45, 1.0, Color("2b2a28"), true)
	# Orelhão na parede da loja e a placa alta, legível de longe pela estrada.
	G.box(root, "Payphone", Vector3(-6.2, 1.1, .2), Vector3(.5, 2.2, .35), Color("d9822b"), true)
	G.box(root, "PayphoneHood", Vector3(-6.2, 2.3, .45), Vector3(1.0, .15, .9), Color("d9822b"))
	G.cylinder(root, "SignPole", Vector3(-10, 4.0, 10.5), .2, 8.0, Color("6e6a62"), true)
	G.box(root, "SignBoard", Vector3(-10, 7.6, 10.5), Vector3(4.4, 1.8, .25), Color("d9822b"))
	G.box(root, "SignSun", Vector3(-10, 7.6, 10.66), Vector3(1.6, .9, .05), Color("f2d36b"))
	G.box(root, "RustedCar", Vector3(-9, .55, -4), Vector3(1.8, 1.1, 4.2), Color("8a5a3c"), true)

static func tower(root: Node3D) -> void:
	var steel := Color("8f8a80")
	# Torre treliçada de 24 m: quatro pernas, travessas a cada 4 m e a plataforma no topo.
	for x in [-2.2, 2.2]:
		for z in [-2.2, 2.2]: G.box(root, "Leg", Vector3(x, 12, z), Vector3(.28, 24, .28), steel, true)
	for level in range(1, 6):
		var y := float(level) * 4.0
		G.box(root, "BraceX", Vector3(0, y, -2.2), Vector3(4.4, .14, .14), steel)
		G.box(root, "BraceX", Vector3(0, y, 2.2), Vector3(4.4, .14, .14), steel)
		G.box(root, "BraceZ", Vector3(-2.2, y, 0), Vector3(.14, .14, 4.4), steel)
		G.box(root, "BraceZ", Vector3(2.2, y, 0), Vector3(.14, .14, 4.4), steel)
	G.box(root, "Platform", Vector3(0, 24.1, 0), Vector3(6, .25, 6), Color("6e6a62"))
	G.cylinder(root, "Antenna", Vector3(0, 28.5, 0), .14, 9.0, Color("c9c3b6"))
	G.box(root, "Dish", Vector3(1.6, 25.6, 1.6), Vector3(1.4, 1.4, .2), Color("d9d4c9"))
	G.box(root, "Ladder", Vector3(0, 12, 2.45), Vector3(.7, 24, .08), Color("b5533c"))
	# Casinha do equipamento e cerca baixa.
	G.box(root, "Shed", Vector3(5.6, 1.3, -1), Vector3(4, 2.6, 3), Color("c2b08f"), true)
	G.box(root, "ShedRoof", Vector3(5.6, 2.7, -1), Vector3(4.4, .2, 3.4), Color("7d7468"))
	G.box(root, "ShedDoor", Vector3(5.6, 1.05, .52), Vector3(1.0, 2.1, .05), Color("4a3a2c"))
	for side in [-1.0, 1.0]: G.box(root, "Fence", Vector3(side * 8, .6, 0), Vector3(.1, 1.2, 14), Color("8f8a80"), true)
	G.box(root, "FenceBack", Vector3(0, .6, -7), Vector3(16, 1.2, .1), Color("8f8a80"), true)

static func scrapyard(root: Node3D) -> void:
	var sheet := Color("8a7f6c")
	# Cerca de chapa com portão aberto para a estrada (+z) e o pátio de venda na frente.
	G.box(root, "FenceBack", Vector3(0, 1.3, -12), Vector3(30, 2.6, .2), sheet, true)
	for side in [-1.0, 1.0]:
		G.box(root, "FenceSide", Vector3(side * 15, 1.3, -2), Vector3(.2, 2.6, 20), sheet.darkened(.06), true)
		G.box(root, "FenceFront", Vector3(side * 9.5, 1.3, 8), Vector3(11, 2.6, .2), sheet, true)
	G.box(root, "SaleBay", Vector3(0, .03, 3), Vector3(6, .06, 7), Color("6e665a"))
	# Pilhas de carros prensados, prensa e guindaste ao fundo.
	var rust := [Color("8a4f33"), Color("6f6a5e"), Color("4f5a63"), Color("9a7a4a"), Color("5d4a3c")]
	for i in 9:
		var x := -11.0 + float(i % 3) * 2.4
		var y := .6 + floorf(float(i) / 3.0) * 1.2
		G.box(root, "CrushedCar", Vector3(x, y, -9.5), Vector3(2.0, 1.1, 3.6), rust[i % rust.size()], true)
	for i in 6:
		var x := 4.0 + float(i % 3) * 2.4
		G.box(root, "CrushedCar", Vector3(x, .6 + floorf(float(i) / 3.0) * 1.2, -9.5), Vector3(2.0, 1.1, 3.6), rust[(i + 2) % rust.size()], true)
	G.box(root, "Crusher", Vector3(-8, 1.6, -3), Vector3(5.5, 3.2, 4), Color("4a4a46"), true)
	G.box(root, "CrusherPlate", Vector3(-8, 3.4, -3), Vector3(5.8, .3, 4.3), Color("c79a2a"))
	G.cylinder(root, "CraneMast", Vector3(-12, 5, 3), .3, 10, Color("c79a2a"), true)
	G.box(root, "CraneBoom", Vector3(-8, 9.8, 3), Vector3(8, .35, .35), Color("c79a2a"))
	G.box(root, "Office", Vector3(9.5, 1.4, -4), Vector3(5, 2.8, 4), Color("b8a98c"), true)
	G.box(root, "OfficeRoof", Vector3(9.5, 2.9, -4), Vector3(5.4, .2, 4.4), Color("7d7468"))
	G.box(root, "OfficeWindow", Vector3(9.5, 1.7, -1.98), Vector3(1.6, .9, .05), Color("3a4146"))
	G.box(root, "Sign", Vector3(0, 3.6, 8.15), Vector3(6, 1.2, .15), Color("c79a2a"))

static func food_truck(root: Node3D) -> void:
	# Furgão amarelo com balcão virado para a pista, toldo e duas mesas.
	G.box(root, "Body", Vector3(0, 1.6, 0), Vector3(6, 2.8, 2.4), Color("e0c14f"), true)
	G.box(root, "Cab", Vector3(3.9, 1.25, 0), Vector3(1.9, 2.1, 2.3), Color("d1b046"), true)
	G.box(root, "Windshield", Vector3(4.86, 1.7, 0), Vector3(.05, .8, 1.9), Color("3a4146"))
	for x in [-2.0, 2.4, 4.0]:
		for z in [-1.1, 1.1]: G.cylinder(root, "Wheel", Vector3(x, .4, z), .4, .3, Color("2b2a28")).rotation.x = PI * .5
	G.box(root, "Counter", Vector3(-.4, 1.25, 1.28), Vector3(3.2, .12, .5), Color("8a5a3c"))
	G.box(root, "ServeWindow", Vector3(-.4, 1.9, 1.21), Vector3(3.0, 1.0, .05), Color("3a3330"))
	G.box(root, "Awning", Vector3(-.4, 2.95, 1.9), Vector3(3.6, .08, 1.5), Color("b5533c"))
	for x in [-2.6, 1.6]:
		G.cylinder(root, "Table", Vector3(x, .38, 5.0), .6, .06, Color("d9d4c9")).position.y = .75
		G.cylinder(root, "TableLeg", Vector3(x, .37, 5.0), .06, .74, Color("6e6a62"), true)
	G.cylinder(root, "TrashCan", Vector3(3.6, .45, 3.2), .35, .9, Color("4f5a4c"), true)
