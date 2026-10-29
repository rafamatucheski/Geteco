extends Node3D
## Sala da guarita da Serra Bruta: console de vigilância com monitores, cadeira, armários de
## aço, arquivo, bebedouro e mesa do rádio. Estática; NativePlace tira os sólidos dos volumes
## marcados com `interior_solid_id` (móvel inteiro, não só as pernas).
const OFFICE := preload("res://world/mining/MiningOffice.gd")
const SHOP := preload("res://world/places/ShopInteriorMaterials.gd")
const WALL_H := 2.7
const WALL := .24
## Soleira além do vão da frente: quem não sai pelo controle de acesso não anda para o vazio.
var solids: Array[Rect2] = [Rect2(-.9, OFFICE.ROOM_SIZE.y * .5, 1.8, .2)]
var variant := 0
var _materials: Dictionary = {}

func _ready() -> void:
	_shell()
	_console(Vector3(-2.0, 0, -2.55))
	_chair(Vector3(-2.0, 0, -1.72))
	_lockers(Vector3(4.11, 0, -1.85))
	_filing_cabinet(Vector3(2.27, 0, -2.62))
	_radio_table(Vector3(-4.06, 0, -.55))
	# Afastado da parede: a cápsula passa atrás dele (encobre as pernas para a câmera).
	_water_cooler(Vector3(-3.75, 0, 1.4))
	_coat_rack(Vector3(3.95, 0, 2.35))
	_lighting()
	set_process(false)
	set_physics_process(false)

func _material(color: Color, kind := "", glow := 0.0) -> Material:
	var key := color.to_html() + kind + str(glow)
	if _materials.has(key): return _materials[key]
	var mat: StandardMaterial3D
	if not kind.is_empty():
		mat = SHOP.material(kind, color)
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .7
		if glow > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = glow
	_materials[key] = mat
	return mat

func _box(id: String, at: Vector3, size: Vector3, color: String, solid := "", kind := "", glow := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	mesh.material_override = _material(Color(color), kind, glow)
	if not solid.is_empty(): mesh.set_meta("interior_solid_id", solid)
	add_child(mesh)
	return mesh

func _cylinder(id: String, at: Vector3, radius: float, height: float, color: String, solid := "", kind := "") -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 20
	mesh.mesh = shape
	mesh.position = at
	mesh.material_override = _material(Color(color), kind)
	if not solid.is_empty(): mesh.set_meta("interior_solid_id", solid)
	add_child(mesh)
	return mesh

func _shell() -> void:
	var size := OFFICE.ROOM_SIZE
	var half := size * .5
	var wall := "c9c1ad"
	_box("VinylFloor", Vector3(0, -.03, 0), Vector3(size.x, .06, size.y), "8a8a80", "", "stone")
	_box("BackWall", Vector3(0, WALL_H * .5, -half.y + WALL * .5), Vector3(size.x, WALL_H, WALL), wall, "BackWall", "plaster")
	_box("Skirting", Vector3(0, .06, -half.y + WALL + .01), Vector3(size.x - WALL * 2, .12, .02), "5d5f58")
	for side in [-1.0, 1.0]:
		# Metade do fundo inteira e metade da frente baixa: a câmera alinhada vê a sala; as duas
		# partes são um sólido só, a parede inteira.
		_box("SideWall", Vector3(side * (half.x - WALL * .5), WALL_H * .5, -half.y * .45), Vector3(WALL, WALL_H, size.y * .55), wall, "SideWall%d" % side, "plaster")
		_box("LowSideWall", Vector3(side * (half.x - WALL * .5), .45, half.y * .55), Vector3(WALL, .9, size.y * .45), wall, "SideWall%d" % side, "plaster")
		var width := half.x - .8
		_box("FrontWall", Vector3(side * (.8 + width * .5), WALL_H * .5, half.y - WALL * .5), Vector3(width, WALL_H, WALL), wall, "FrontWall%d" % side, "plaster")
		_box("DoorJamb", Vector3(side * .82, .45, half.y - WALL * .5), Vector3(.1, .9, WALL + .06), "4f5a5c", "DoorJamb%d" % side)
	# Janela do fundo sobre o console: dá para a cava, como numa guarita de verdade.
	_box("PitWindow", Vector3(-2.0, 1.8, -half.y + WALL + .005), Vector3(2.6, .9, .02), "7c9aa3", "", "", .35)
	for x in [-3.33, -2.0, -.67]: _box("WindowMullion", Vector3(x, 1.8, -half.y + WALL + .02), Vector3(.06, .98, .04), "56605f")
	for y in [1.32, 2.28]: _box("WindowFrame", Vector3(-2.0, y, -half.y + WALL + .02), Vector3(2.72, .07, .05), "56605f")
	_box("EntryMat", Vector3(0, .004, half.y - .9), Vector3(1.5, .016, .8), "3b3d38", "", "cloth")
	# Faixa amarela de segurança no piso, só no caminho da porta ao console.
	_box("SafetyStripe", Vector3(-1.0, .003, -.4), Vector3(.08, .006, 3.6), "c9a23a")
	_box("WallClockFace", Vector3(.9, 2.25, -half.y + WALL + .02), Vector3(.34, .34, .03), "e8e4d8")
	_box("WallClockRim", Vector3(.9, 2.25, -half.y + WALL + .005), Vector3(.4, .4, .02), "2e3132")
	# Quadro de chaves na parede, sólido para a cápsula não entrar nele de frente.
	_box("KeyCabinet", Vector3(.9, 1.5, -half.y + WALL + .06), Vector3(.56, .7, .12), "6b7472", "KeyCabinet", "metal")
	for row in 3:
		for column in 4:
			_box("KeyTag", Vector3(.72 + column * .12, 1.68 - row * .16, -half.y + WALL + .13), Vector3(.05, .08, .01), ["c9a23a", "a4553f", "5b7a8a"][(row + column) % 3])
	# Mapa da cava na parede esquerda, acima da mesa do rádio.
	_box("PitMapBoard", Vector3(-half.x + WALL + .02, 1.65, -.55), Vector3(.03, .82, 1.3), "d9cfb4")
	for i in 5:
		_box("PitMapContour", Vector3(-half.x + WALL + .04, 1.36 + i * .12, -.55), Vector3(.01, .025, 1.1 - i * .17), "8a6a4a")

func _console(at: Vector3) -> void:
	var metal := "58605f"
	_box("ConsoleTop", at + Vector3(0, .75, 0), Vector3(3.6, .05, .8), "6f6a5d", "ConsoleDesk", "wood")
	_box("ConsoleModesty", at + Vector3(0, .4, -.32), Vector3(3.5, .66, .04), metal, "ConsoleDesk", "metal")
	for x in [-1.75, 1.75]: _box("ConsoleEnd", at + Vector3(x, .37, 0), Vector3(.06, .74, .76), metal, "ConsoleDesk", "metal")
	_box("DrawerPedestal", at + Vector3(1.38, .37, .02), Vector3(.5, .7, .7), metal, "ConsoleDesk", "metal")
	for i in 3: _box("DrawerFront", at + Vector3(1.38, .15 + i * .22, .375), Vector3(.44, .19, .02), "68716f")
	# Três monitores do circuito interno, o teclado, o rádio base e o livro de ocorrências.
	for i in 3:
		var x := -1.15 + i * 1.0
		_box("MonitorStand", at + Vector3(x, .83, -.15), Vector3(.12, .12, .12), "2a2c2d")
		_box("MonitorCase", at + Vector3(x, 1.08, -.17), Vector3(.62, .4, .1), "26292a")
		_box("CameraFeed", at + Vector3(x, 1.08, -.115), Vector3(.55, .33, .01), ["7f948f", "8a9488", "77878f"][i], "", "", .55)
		for band in 2: _box("FeedBand", at + Vector3(x, 1.0 + band * .14, -.108), Vector3(.5, .025, .005), "4e5a58", "", "", .3)
	_box("Keyboard", at + Vector3(-.15, .785, .18), Vector3(.48, .02, .16), "2e3132")
	_box("RadioBase", at + Vector3(.95, .83, .05), Vector3(.32, .12, .24), "333738")
	_box("RadioDisplay", at + Vector3(.95, .85, .175), Vector3(.14, .04, .005), "c79a3a", "", "", .5)
	_cylinder("RadioAntenna", at + Vector3(1.07, 1.05, -.02), .008, .36, "1f2122")
	_box("Logbook", at + Vector3(-1.3, .79, .2), Vector3(.3, .03, .22), "6d3b2e", "", "cloth")
	_cylinder("CoffeeMug", at + Vector3(.55, .82, .22), .04, .09, "e3ddce")

func _chair(at: Vector3) -> void:
	# De costas para a porta, virada para os monitores.
	_box("ChairSeat", at + Vector3(0, .48, 0), Vector3(.5, .08, .48), "2f3437", "OfficeChair", "cloth")
	_box("ChairBack", at + Vector3(0, .82, .23), Vector3(.46, .56, .07), "2f3437", "OfficeChair", "cloth")
	_cylinder("ChairColumn", at + Vector3(0, .3, 0), .03, .36, "1f2122")
	for i in 5:
		var angle := float(i) * TAU / 5.0
		var leg := _box("ChairLeg", at + Vector3(sin(angle) * .14, .07, cos(angle) * .14), Vector3(.05, .04, .28), "1f2122", "OfficeChair")
		leg.rotation.y = angle

func _lockers(at: Vector3) -> void:
	for i in 3:
		var p := at + Vector3(0, 0, (float(i) - 1.0) * .7)
		_box("SteelLocker", p + Vector3(0, .975, 0), Vector3(.5, 1.95, .68), "52707a", "Lockers", "metal")
		_box("LockerSeam", p + Vector3(-.252, .975, .34), Vector3(.01, 1.9, .015), "3b5158")
		for slot in 4: _box("LockerVent", p + Vector3(-.252, 1.62 + slot * .06, 0), Vector3(.01, .02, .4), "33474d")
		_box("LockerHandle", p + Vector3(-.26, 1.05, .22), Vector3(.03, .16, .04), "c7c9c4")
	_cylinder("HardHat", at + Vector3(0, 2.0, -.35), .15, .1, "d9a62d")
	_cylinder("HardHat", at + Vector3(0, 2.0, .45), .15, .1, "e3e1d8")

func _filing_cabinet(at: Vector3) -> void:
	_box("FilingCabinet", at + Vector3(0, .66, 0), Vector3(.55, 1.32, .65), "7d8382", "FilingCabinet", "metal")
	for i in 4:
		_box("FileDrawer", at + Vector3(0, .17 + i * .32, .33), Vector3(.5, .28, .015), "8b9190")
		_box("FileHandle", at + Vector3(0, .25 + i * .32, .345), Vector3(.16, .025, .03), "3a3d3e")
	_box("FileBinder", at + Vector3(-.12, 1.45, 0), Vector3(.07, .26, .3), "2f4f6b")
	_box("FileBinder", at + Vector3(-.03, 1.45, 0), Vector3(.07, .26, .3), "a4553f")

func _radio_table(at: Vector3) -> void:
	_box("RadioTableTop", at + Vector3(0, .74, 0), Vector3(.6, .04, 1.2), "6f6a5d", "RadioTable", "wood")
	for x in [-.26, .26]:
		for z in [-.55, .55]: _box("RadioTableLeg", at + Vector3(x, .36, z), Vector3(.04, .72, .04), "3a3d3e", "RadioTable")
	# Carregador com rádios portáteis e a cafeteira do turno.
	_box("ChargerRack", at + Vector3(.02, .8, -.3), Vector3(.24, .08, .44), "2e3132")
	for i in 3: _box("HandheldRadio", at + Vector3(.02, .92, -.45 + i * .15), Vector3(.06, .2, .05), "1f2122")
	_box("CoffeeMaker", at + Vector3(0, .93, .32), Vector3(.24, .34, .22), "26292a")
	_cylinder("CoffeePot", at + Vector3(.1, .84, .32), .06, .14, "4a3528")

func _water_cooler(at: Vector3) -> void:
	_box("CoolerBody", at + Vector3(0, .5, 0), Vector3(.36, 1.0, .36), "d8d6cf", "WaterCooler")
	_box("CoolerTap", at + Vector3(.19, .82, 0), Vector3.ONE * .05, "3f6fa0")
	_cylinder("WaterBottle", at + Vector3(0, 1.2, 0), .14, .4, "8fb3c6", "WaterCooler")

func _coat_rack(at: Vector3) -> void:
	_cylinder("RackPole", at + Vector3(0, .9, 0), .025, 1.8, "3a3d3e", "CoatRack")
	_cylinder("RackBase", at + Vector3(0, .02, 0), .22, .04, "3a3d3e", "CoatRack")
	# Coletes refletivos do turno pendurados.
	_box("HiVisVest", at + Vector3(-.12, 1.35, 0), Vector3(.06, .62, .42), "d7a23a", "CoatRack", "cloth")
	_box("VestStripe", at + Vector3(-.155, 1.3, 0), Vector3(.01, .04, .43), "e6e6dc")
	_box("HiVisVest", at + Vector3(.12, 1.35, 0), Vector3(.06, .62, .42), "c9d23d", "CoatRack", "cloth")

func _lighting() -> void:
	# Duas calhas fluorescentes motivadas, sem sombra; a sala inteira cabe nelas.
	for x in [-1.9, 1.9]:
		_box("FluorescentHousing", Vector3(x, WALL_H - .05, -.4), Vector3(1.3, .05, .14), "d5d6d0")
		_box("FluorescentTube", Vector3(x, WALL_H - .085, -.4), Vector3(1.2, .02, .08), "f2f5ff", "", "", 1.6)
		var light := OmniLight3D.new()
		light.name = "FluorescentLight"
		light.position = Vector3(x, WALL_H - .3, -.4)
		light.light_color = Color("eef2ff")
		light.light_energy = .95
		light.light_specular = .2
		light.omni_range = 6.5
		light.omni_attenuation = .8
		light.shadow_enabled = false
		add_child(light)
