extends Node3D
const L := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var _caches: Array[Node3D]=[]

static func build() -> Node3D:
	var site = load("res://world/desert/canyon/DesertSmugglerSite.gd").new()
	site.name="DesertSmugglerSite"
	site.position=L.CENTER
	site._build()
	return site

func set_cache_collected(index: int,collected: bool) -> void:
	if index>=0 and index<_caches.size(): _caches[index].visible=not collected

func _build() -> void:
	# Short defensive walls create flank routes without concealing the abyss.
	for at in [Vector3(-12,.65,-14),Vector3(12,.65,-14),Vector3(-17,.65,0),Vector3(17,.65,0)]:
		G.box(self,"FortifiedCover",at,Vector3(5.0,1.3,1.0),Color("8e8067"),true)
		for x in [-1.8,-.6,.6,1.8]: G.box(self,"Sandbag",at+Vector3(x,.76,0),Vector3(1.06,.25,.8),Color("aaa181"),true)
	# Caixas militares empilhadas e fardos lacrados de narcóticos comunicam o depósito.
	for offset in [Vector3(-25,0,-2),Vector3(25,0,-2),Vector3(16,0,12),Vector3(-14,0,17)]:
		for i in 3:
			var at: Vector3=offset+Vector3(float(i%2)*1.35,.43+float(floori(i/2.0))*.86,0)
			var crate := G.box(self,"SealedCargo",at,Vector3(1.18,.86,.9),Color("565d49"),true)
			for x in [-.43,.43]: G.box(crate,"SteelStrap",Vector3(x,0,0),Vector3(.075,.9,.94),Color("333b35"))
	for i in 9:
		var p := Vector3(24+float(i%3)*.52,.2+float(floori(i/3.0))*.4,8)
		var bale := G.box(self,"WrappedContraband",p,Vector3(.46,.4,.78),Color("cec4a2"),true)
		G.box(bale,"ParcelTape",Vector3(0,0,0),Vector3(.09,.415,.795),Color("665e4b"))
	for i in 2:
		var cache_at := L.ARMORY_POS-L.CENTER+Vector3(-1.35,0,float(i)*3)
		G.box(self,"ArmoryCase",cache_at+Vector3(0,.42,0),Vector3(1.8,.84,1.35),Color("49523f"),true)
		G.box(self,"OpenCaseLid",cache_at+Vector3(0,1.12,-.69),Vector3(1.8,.62,.08),Color("384133"),true)
		var goods := Node3D.new()
		goods.name="SmugglerCache%d"%i
		goods.position=cache_at+Vector3(0,.9,0)
		add_child(goods)
		_caches.append(goods)
		if i==0:
			var gun := Node3D.new()
			goods.add_child(gun)
			preload("res://gameplay/ArsenalWeapon3D.gd").build_cached(gun,"ak47")
			gun.rotation=Vector3(0,PI*.5,PI*.5)
		else:
			for x in [-.5,0,.5]: preload("res://gameplay/ArsenalWeapon3D.gd").build_cached(_grenade_anchor(goods,float(x)),"grenade")
	_build_hideout()
	G.batch_repeated_meshes(self)

func _build_hideout() -> void:
	# Um esconderijo de trabalho ao ar livre, não um cômodo novo: sem teto, portas,
	# troca de câmera nem dono de streaming. O centro continua uma faixa de tiro/flanco.
	var shelter := Node3D.new()
	shelter.name="OpenSmugglerHideout"
	add_child(shelter)
	for x in [-4.0,2.0,8.0]:
		G.box(shelter,"SalvagedSteelUpright",Vector3(float(x),1.05,9),Vector3(.15,2.1,.15),Color("5b4e40"),true)
		G.box(shelter,"PostFoot",Vector3(float(x),.1,9),Vector3(.48,.2,.5),Color("827159"),true)
	# Lona vertical fina e chapas onduladas enferrujadas quebram a silhueta
	# e deixam a cabeça do jogador e o desfiladeiro além legíveis.
	for i in 6:
		var x := -3.0+float(i)*2.0
		var panel := G.box(shelter,"SalvagedWindbreak",Vector3(x,.72,9),Vector3(1.96,1.44,.12),Color("6a6150") if i%2==0 else Color("80644c"),true)
		for rib in [-.74,-.24,.24,.74]: G.box(panel,"SheetRib",Vector3(float(rib),0,-.08),Vector3(.055,1.43,.045),Color("8c7658"))
	G.box(shelter,"TiedCanvasScreen",Vector3(-1.0,1.65,9),Vector3(5.8,.40,.055),Color("65715a"),true)
	for x in [-4.0,8.0]:
		G.box(shelter,"SideWindbreak",Vector3(float(x),.62,7),Vector3(.14,1.24,3.8),Color("75664c"),true)
		G.box(shelter,"SideBrace",Vector3(float(x),.68,7),Vector3(.20,.10,3.8),Color("504937"))
	# Caixas na altura da cintura definem a borda do fundo; cada pilha visível dá cobertura real.
	for x in [-2.7,-1.35,0.0,1.35,2.7]:
		var crate := G.box(shelter,"ReserveAmmunitionCase",Vector3(float(x),.47,8.05),Vector3(1.2,.94,1.0),Color("505843"),true)
		for strap in [-.39,.39]: G.box(crate,"AmmoCaseBand",Vector3(float(strap),0,0),Vector3(.06,.97,1.035),Color("30392e"))
	# A bancada reserva a área completa, incluindo o espaço abaixo
	# do tampo. Andar não pode pôr o jogador nem os guardas dentro do móvel.
	var bench := Node3D.new()
	bench.name="SmugglerWeaponsBench"
	bench.position=Vector3(2,.45,3)
	shelter.add_child(bench)
	G.collision(bench,Vector3(4.2,.9,1.2))
	G.box(bench,"WornWorkbenchTop",Vector3(0,.39,0),Vector3(4.2,.12,1.2),Color("887151"))
	for x in [-1.83,1.83]:
		for z in [-.43,.43]: G.box(bench,"WorkbenchLeg",Vector3(float(x),-.06,float(z)),Vector3(.13,.78,.13),Color("514f42"))
	G.box(bench,"WorkbenchCrossbar",Vector3(0,-.19,0),Vector3(3.8,.12,.10),Color("514f42"))
	_weapon_prop(bench,"ak47",Vector3(-.8,.47,0),0.25)
	_weapon_prop(bench,"m4a1",Vector3(.8,.47,0),-0.20)
	for x in [-1.7,1.55]:
		G.box(bench,"LooseMagazine",Vector3(float(x),.51,.27),Vector3(.10,.12,.29),Color("343b30"))
	# Um suporte baixo de fuzis encosta nas caixas de reserva sólidas. As armas são carga
	# visual; os dois esconderijos estabelecidos do arsenal continuam as únicas recompensas únicas.
	for i in 3:
		_weapon_prop(shelter,"ak47" if i!=1 else "m4a1",Vector3(3.7+float(i)*.48,.92,8.0),PI*.5)
	G.box(shelter,"RifleRackFoot",Vector3(4.18,.2,8.0),Vector3(1.8,.4,1.0),Color("554939"),true)
	G.box(shelter,"RifleRackBack",Vector3(4.18,.74,8.35),Vector3(1.8,1.08,.12),Color("6c5b40"),true)
	G.box(shelter,"RifleRackShelf",Vector3(4.18,.85,8.0),Vector3(1.8,.08,1.0),Color("6c5b40"),true)
	for i in 6:
		var bale := G.box(shelter,"ShelteredContraband",Vector3(6.55+float(i%2)*.54,.24+float(floori(i/2.0))*.48,7.8),Vector3(.5,.48,.86),Color("c5bba0"),true)
		G.box(bale,"CargoBinding",Vector3.ZERO,Vector3(.10,.495,.88),Color("695f4a"))
	_sandbag_barricade(shelter,Vector3(-5,0,-4),4)
	_sandbag_barricade(shelter,Vector3(8,0,-6),3)
	G.batch_repeated_meshes(bench)
	G.batch_repeated_meshes(shelter)

func _sandbag_barricade(parent: Node3D, at: Vector3, count: int) -> void:
	for layer in 3:
		for i in count:
			var x := (float(i)-float(count-1)*.5)*.98+(.12 if layer%2==1 else -.12)
			var bag := G.box(parent,"StackedCoverSandbag",at+Vector3(x,.2+float(layer)*.4,0),Vector3(.96,.4,.75),Color("a09573") if (i+layer)%2==0 else Color("918566"),true)
			G.box(bag,"SandbagSeam",Vector3(0,.19,-.35),Vector3(.82,.022,.028),Color("776e55"))

func _weapon_prop(parent: Node3D, id: String, at: Vector3, yaw: float) -> void:
	var gun := Node3D.new()
	gun.name="SmugglerCargoWeapon"
	gun.position=at
	gun.rotation=Vector3(0,yaw,PI*.5)
	parent.add_child(gun)
	preload("res://gameplay/ArsenalWeapon3D.gd").build_cached(gun,id)

func _grenade_anchor(parent: Node3D,x: float) -> Node3D:
	var anchor := Node3D.new()
	anchor.position.x=x
	parent.add_child(anchor)
	return anchor
