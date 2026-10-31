extends RefCounted
## Shared, mipmapped production finishes. All new detail stays inside authored solid volumes.
const G := preload("res://world/desert/DesertGeometry.gd")
const SHOP := preload("res://world/places/ShopInteriorMaterials.gd")
const URBAN := preload("res://assets/urban_detail/UrbanMaterials.gd")
const PORT := preload("res://world/regions/PortYardMaterials3D.gd")
static var _cache: Dictionary={}

static func material(kind: String) -> StandardMaterial3D:
	if _cache.has(kind): return _cache[kind]
	var result: StandardMaterial3D
	match kind:
		"stucco": result=URBAN.textured_wall(Color("d1bfa1"),.93)
		"paving":
			result=SHOP.material("stone",Color("bfb49c")).duplicate() as StandardMaterial3D
			result.uv1_scale=Vector3.ONE*.5
			result.uv1_world_triplanar=true
			result.roughness=.78
		"concrete":
			result=PORT.concrete().duplicate() as StandardMaterial3D
			# Mantém as lajes gastas do porto, aquecidas para um piso seco de garagem; nunca altera o material compartilhado.
			result.albedo_color=Color(1.55,1.50,1.36)
			result.uv1_scale=Vector3.ONE/6.0
			var pixels := result.albedo_texture.get_image()
			if not pixels.has_mipmaps(): pixels.generate_mipmaps()
			result.albedo_texture=ImageTexture.create_from_image(pixels)
		"wood": result=SHOP.material("wood",Color("98774f"))
		"dark_wood": result=SHOP.material("wood",Color("725638"))
		"cloth": result=SHOP.material("cloth",Color("7c805e"))
		"rug": result=SHOP.material("cloth",Color("795b43"))
		"steel":
			result=StandardMaterial3D.new()
			result.albedo_color=Color("535c56")
			result.metallic=.48
			result.roughness=.57
		_:
			result=StandardMaterial3D.new()
	result.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[kind]=result
	return result

static func apply(room: Node3D, bank: bool) -> void:
	for child in room.get_children():
		if not child is MeshInstance3D: continue
		var id := str(child.name)
		if id=="Terrazzo": child.material_override=material("paving")
		elif id=="ConcreteFloor": child.material_override=material("concrete")
		elif "Wall" in id: child.material_override=material("stucco")
		elif id in ["TellerCounter","CounterTop","DepositDesk","TuningDesk"]: child.material_override=material("wood")
		elif id=="CeilingBeam": child.material_override=material("dark_wood")
		elif id.begins_with("PartsCrate"): child.material_override=material("wood")
		elif id=="Rug": child.material_override=material("rug")
		elif id.begins_with("ClerkChair") or id=="DeskChair": _finish_seat(room,child,false)
		elif id.begins_with("WaitingBench"): _finish_seat(room,child,true)
		elif id.begins_with("RoofTruss") or id.begins_with("PartsShelf"): child.material_override=material("steel")
	if bank:
		for i in 3:
			var at := Vector3(-1.5+float(i)*3.4,1.23,-2.6)
			_piece(room,"DocumentTray",at+Vector3(.85,.04,0),Vector3(.38,.075,.28),material("dark_wood"))
			G.box(room,"Forms",at+Vector3(.85,.085,0),Vector3(.29,.015,.21),Color("d8ceb6"))
			G.box(room,"TellerKeyboard",at+Vector3(0,.02,.22),Vector3(.45,.035,.16),Color("525951"))
		# Os acessórios de bancada ficam sobre móveis existentes, longe das rotas de moradores e clientes.
		G.box(room,"Ledger",Vector3(6.25,1.28,1.2),Vector3(.34,.07,.46),Color("65715b"))
	else:
		for i in 6:
			G.box(room,"WorkbenchDrawer",Vector3(-11.1+float(i%3)*1.4,.35+float(floori(i/3.0))*.46,-4.79),Vector3(1.2,.37,.035),Color("626c58"))
			G.box(room,"DrawerPull",Vector3(-11.1+float(i%3)*1.4,.36+float(floori(i/3.0))*.46,-4.765),Vector3(.3,.035,.025),Color("abb0a0"))
		# Ferramentas pequenas e conhecidas mantêm a escala humana sem entulhar a baia de passagem.
		for i in 4:
			var at := Vector3(-10.6+float(i)*.45,1.32,-5.4)
			_piece(room,"SocketTool",at,Vector3(.055,.045,.28),material("steel"))
		G.box(room,"TuningKeyboard",Vector3(8.4,1.33,.38),Vector3(.65,.05,.2),Color("454c46"))
		G.box(room,"PartsNotebook",Vector3(9.3,1.34,.05),Vector3(.36,.075,.48),Color("7a6048"))

static func _piece(room: Node3D, id: String, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := G.box(room,id,at,size,Color.WHITE)
	node.material_override=mat
	return node

static func _finish_seat(room: Node3D, solid: MeshInstance3D, bench: bool) -> void:
	# Retém exatamente o envelope do colisor marcado, trocando o bloco sólido visível por móveis.
	solid.hide()
	var dimensions: Vector3=solid.mesh.size
	var center: Vector3=solid.position
	var bottom := center.y-dimensions.y*.5
	var seat_y := bottom+dimensions.y*.47
	_piece(room,"SeatCushion",Vector3(center.x,seat_y,center.z),Vector3(dimensions.x,.12,dimensions.z-.02),material("wood" if bench else "cloth"))
	_piece(room,"SeatBack",Vector3(center.x,bottom+dimensions.y*.76,center.z-dimensions.z*.5+.07),Vector3(dimensions.x,dimensions.y*.48,.12),material("wood" if bench else "cloth"))
	for side in [-1.0,1.0]:
		for depth in [-1.0,1.0]:
			_piece(room,"SeatLeg",Vector3(center.x+side*(dimensions.x*.5-.09),bottom+(seat_y-bottom)*.5,center.z+depth*(dimensions.z*.5-.09)),Vector3(.065,seat_y-bottom,.065),material("steel"))
