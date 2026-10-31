extends Node3D
## Decoração de dia de corrida em volta do circuito: fita da pista entre as estacas, fardos
## de feno na área de escape das curvas mais fechadas, uma pequena arquibancada com torcedores
## sentados na reta final, faixas de patrocinadores e o painel de controle da corrida.
## A geometria estática é agrupada por material e todo sólido divide um corpo.
## O posicionamento lê as funções de superfície da própria pista, nunca um palpite plano.
const SPECTATOR := preload("res://activities/motocross/MotocrossSpectator.gd")
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
## Lado de dentro da reta final, entre duas árvores de sombra (>= 4 m livres
## das pontas da arquibancada), virada para o sul: a câmera do jogo vê assentos, torcedores
## e o painel em vez da parede de trás. Mantém em sincronia com a área pisoteada
## em MotocrossLandscape.gdshaderinc e o retângulo CLEAR da grama.
const BLEACHER_CENTER := Vector2(-206.1,-66.2)
const BALE_SIZE := Vector3(1.0,.5,.55)
const TAPE_HEIGHT := .72
var course: Node3D
var bleacher: Node3D
var fans: Array[Node3D] = []
var bale_transforms: Array[Transform3D] = []
## Por que posições candidatas de fardo foram puladas; lido por testes e revisões.
var bale_skips := {"bounds":0,"course":0,"reserved":0,"slope":0}
var apex_count := 0
var banner_count := 0
var board_title: Label3D
var board_detail: Label3D
var _solids: StaticBody3D
var _materials := {}
var _surfaces := {}
var _reserved: Array[Vector3] = []

func _ready() -> void:
	name = "MotocrossTrackside"
	_solids = StaticBody3D.new()
	_solids.name = "TracksideSolids"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)
	var scenery: Node3D = course.get_node_or_null("MotocrossScenery")
	if scenery != null:
		for point in scenery.tree_points: _reserved.append(Vector3(point.x,2.2,point.z))
		_reserved.append(Vector3(scenery.tower_position.x,3.5,scenery.tower_position.z))
	_steps = [_tape,_bleacher,_board,_banners,_hay_bales,_flush]
	set_process(true)

var _steps: Array[Callable] = []
var complete := false

## Fita, arquibancada (5 torcedores), placar, faixas e fardos em quadros separados; o
## `_flush` (malhas em lote) por último. `finish_build` conclui na hora (testes).
func _process(_delta: float) -> void:
	if _steps.is_empty(): return
	(_steps.pop_front() as Callable).call()
	if _steps.is_empty():
		complete = true
		set_process(false)

func finish_build() -> void:
	while not _steps.is_empty(): (_steps.pop_front() as Callable).call()
	complete = true

func set_board(title: String, detail: String) -> void:
	if is_instance_valid(board_title) and board_title.text != title: board_title.text = title
	if is_instance_valid(board_detail) and board_detail.text != detail: board_detail.text = detail

func _material(color: Color, cull_disabled := false) -> StandardMaterial3D:
	var key := color.to_html()+("2" if cull_disabled else "")
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .88
		if cull_disabled: material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]

func _surface(material: Material) -> SurfaceTool:
	if not _surfaces.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material)
		_surfaces[material] = builder
	return _surfaces[material]

func _box(where: Transform3D, size: Vector3, material: Material, solid := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.get_mesh_arrays())
	_surface(material).append_from(source,0,where)
	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.transform = where
		_solids.add_child(shape)

func _quad(a: Vector3, b: Vector3, height: float, material: Material) -> void:
	# Faixa vertical, dupla face pelo material; fita e tecido de faixa.
	var surface := _surface(material)
	var normal := (b-a).cross(Vector3.UP).normalized()
	var up := Vector3.UP*height
	for vertex in [a,b,b+up,a,b+up,a+up]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)

func _flush() -> void:
	for material in _surfaces:
		var builder: SurfaceTool = _surfaces[material]
		var visual := MeshInstance3D.new()
		visual.mesh = builder.commit()
		visual.material_override = material
		add_child(visual)
	_surfaces.clear()

## Posições reservadas guardam o raio em y. `trunk_limit` deixa objetos baixos
## (faixas) passarem sob uma copa: entradas pequenas (árvores, faixas) então só
## precisam dessa folga a partir do centro.
func _clear_of_reserved(point: Vector3, radius: float, trunk_limit := -1.0) -> bool:
	for other in _reserved:
		var limit: float = trunk_limit if trunk_limit > 0.0 and other.y <= 2.2 else radius+other.y
		if Vector2(point.x-other.x,point.z-other.z).length() < limit: return false
	return true

func _tape() -> void:
	# Straight runs between stakes, sagging slightly, alternating red and white.
	var colors := [_material(Color("e9e3d2"),true),_material(Color("c9412a"),true)]
	for row in course.stake_tops:
		for index in row.size():
			var a: Vector3 = row[index]+Vector3.UP*TAPE_HEIGHT
			var b: Vector3 = row[(index+1)%row.size()]+Vector3.UP*TAPE_HEIGHT
			var span := a.distance_to(b)
			if span < .3 or span > 12.0: continue
			var pieces := maxi(2,ceili(span/.75))
			for piece in pieces:
				var t0 := float(piece)/float(pieces)
				var t1 := float(piece+1)/float(pieces)
				var sag := .035*span/10.0
				_quad(a.lerp(b,t0)-Vector3.UP*sin(t0*PI)*sag,a.lerp(b,t1)-Vector3.UP*sin(t1*PI)*sag,.07,colors[piece%2])

func _terrain_frame(center: Vector2, along: Vector3, size: Vector2) -> Dictionary:
	# Quatro cantos da pegada na superfície da pedreira; o plano por eles é
	# o apoio. Devolve {} quando o chão sob o objeto é irregular demais.
	var across := along.cross(Vector3.UP).normalized()
	var corners: Array[Vector3] = []
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector3 = Vector3(center.x,0,center.y)+along*corner.x*size.x*.5+across*corner.y*size.y*.5
		p.y = course.surface_height(Vector2(p.x,p.z))
		corners.append(p)
	var lowest := INF
	var highest := -INF
	for p in corners:
		lowest = minf(lowest,p.y)
		highest = maxf(highest,p.y)
	var up := (corners[2]-corners[0]).cross(corners[1]-corners[3]).normalized()
	if up.y < 0: up = -up
	return {"corners":corners,"low":lowest,"high":highest,"up":up,"along":along,"across":across}

func _hay_bales() -> void:
	var hay := _material(Color("c4a25a"))
	var twine := _material(Color("7b5b2c"))
	var n: int = course.points.size()-1
	var apexes: Array[int] = []
	for index in n:
		var turn: float = course.turn_at(index)
		if absf(turn) < .25: continue
		if absf(course.turn_at(index-1)) > absf(turn) or absf(course.turn_at(index+1)) > absf(turn): continue
		var separate := true
		for other in apexes:
			if absf(other-index) < 16 or absf(other-index) > n-16: separate = false
		if separate: apexes.append(index)
	apex_count = apexes.size()
	for apex in apexes:
		var outside := signf(course.turn_at(apex))
		# Uma parede de aparência contínua: um fardo por ponto bakeado (~1.5 m na rota,
		# mais largo no raio externo) ao longo da curva.
		for k in range(apex-6,apex+7):
			var distance := float(posmod(k,n))/float(n)*float(course.length)
			var road: Transform3D = course.pose(distance)
			var along := -road.basis.z
			var at: Vector3 = course.sample(distance)+road.basis.x*outside*(course.HALF_WIDTH+3.9)
			var spot := Vector2(at.x,at.z)
			if not course.BOUNDS.grow(-2.5).has_point(spot):
				bale_skips.bounds += 1; continue
			# Outro trecho do circuito pode passar perto desta área de escape.
			if float(course.nearest(at).lateral) < course.HALF_WIDTH+3.3:
				bale_skips.course += 1; continue
			if not _clear_of_reserved(at,.9):
				bale_skips.reserved += 1; continue
			var frame := _terrain_frame(spot,along,Vector2(BALE_SIZE.x,BALE_SIZE.z))
			if float(frame.high)-float(frame.low) > .28:
				bale_skips.slope += 1; continue
			var up: Vector3 = frame.up
			var x := (along-up*along.dot(up)).normalized()
			var local_basis := Basis(x,up,x.cross(up))
			var mean := Vector3.ZERO
			for corner in frame.corners: mean += corner/4.0
			# Um assento de 3 cm no solo para nenhuma borda do fardo ficar pendurada na encosta.
			var where := Transform3D(local_basis,mean+up*(BALE_SIZE.y*.5-.03))
			bale_transforms.append(where)
			_box(where,BALE_SIZE,hay,true)
			for band in [-.26,.26]:
				_box(where*Transform3D(Basis.IDENTITY,Vector3(band,0,0)),Vector3(.035,BALE_SIZE.y+.01,BALE_SIZE.z+.01),twine)

func _bleacher() -> void:
	# Arquibancada de madeira fechada de frente para o grid de largada, do outro lado da reta final. Três
	# degraus mais uma passarela na frente; cada bloco entra 20 cm no solo
	# abaixo do ponto mais baixo da pegada, para a arquibancada nunca ficar pendurada na encosta.
	var route: Dictionary = course.nearest(Vector3(BLEACHER_CENTER.x,0,BLEACHER_CENTER.y))
	var toward: Vector3 = Vector3(route.point.x-BLEACHER_CENTER.x,0,route.point.z-BLEACHER_CENTER.y).normalized()
	var local_basis := Basis(Vector3.UP,atan2(-toward.x,-toward.z))
	var width := 8.0
	var highest := -INF
	var lowest := INF
	for x in [-.5,-.25,0.0,.25,.5]:
		for z in [-1.6,0.0,1.2]:
			var p := Vector3(BLEACHER_CENTER.x,0,BLEACHER_CENTER.y)+local_basis*Vector3(x*width,0,z)
			var h: float = course.surface_height(Vector2(p.x,p.z))
			highest = maxf(highest,h)
			lowest = minf(lowest,h)
	bleacher = Node3D.new()
	bleacher.name = "StartBleacher"
	bleacher.transform = Transform3D(local_basis,Vector3(BLEACHER_CENTER.x,highest+.12,BLEACHER_CENTER.y))
	add_child(bleacher)
	_reserved.append(Vector3(BLEACHER_CENTER.x,5.2,BLEACHER_CENTER.y))
	var riser := _material(Color("5f4632"))
	var plank := _material(Color("a17a4f"))
	var steel := _material(Color("59625f"))
	var bottom := lowest-bleacher.position.y-.2
	var at := func(p: Vector3) -> Transform3D: return bleacher.transform*Transform3D(Basis.IDENTITY,p)
	# Passarela (topo 0) e depois degraus k com piso z em [-1.2+.8k, -.4+.8k], topo .45(k+1).
	_box(at.call(Vector3(0,bottom*.5,-1.4)),Vector3(width,-bottom,.4),riser,true)
	for tier in 3:
		var front := -1.2+float(tier)*.8
		var top := float(tier+1)*.45
		_box(at.call(Vector3(0,(bottom+top)*.5,front+.4)),Vector3(width,top-bottom,.8),riser,true)
		# Tábua de banco na frente de cada degrau; os pés apoiam no degrau de baixo.
		_box(at.call(Vector3(0,top+.015,front+.19)),Vector3(width-.1,.05,.36),plank)
	for x in [-3.95,-1.3,1.3,3.95]: _box(at.call(Vector3(x,1.35+.45,1.16)),Vector3(.07,.9,.07),steel)
	_box(at.call(Vector3(0,2.24,1.16)),Vector3(width,.06,.06),steel)
	_box(at.call(Vector3(0,1.35+.45,1.16)),Vector3(width,.9,.04),steel,true)
	var seats := [Vector3(-2.6,0,0),Vector3(1.9,0,0),Vector3(-.7,0,1),Vector3(3.0,0,1),Vector3(.4,0,2)]
	var shirts := [Color("3f78a8"),Color("d9a33a"),Color("b8483a"),Color("4d8a5d"),Color("e9e5d8")]
	for index in seats.size():
		var seat: Vector3 = seats[index]
		var tier := int(seat.z)
		var fan := SPECTATOR.new()
		fan.name = "BleacherFan%d"%index
		fan.configure({"identity":20+index,"jersey":shirts[index],"seated":true,"seat_height":.49,"deck":bleacher,"still":true,
			"bounds":Rect2(-width*.5,-1.6,width,2.8),"flee_radius":2.0})
		# O chão é o degrau (ou a passarela) da frente; a pélvis fica na tábua.
		fan.position = Vector3(seat.x,float(tier)*.45,-1.2+float(tier)*.8+.2)
		bleacher.add_child(fan)
		fans.append(fan)

func _banners() -> void:
	# Lado de dentro da reta final, de frente para o grid, a arquibancada e a câmera.
	var cloths := [Color("c8512b"),Color("2f5d7c"),Color("e0b53f")]
	var inks := [Color("f4efe2"),Color("f4efe2"),Color("2a2419")]
	var titles := ["VÉRTICE MX","BARRO FINO","VÉRTICE MX"]
	var index := 0
	# Anda para trás a partir da linha de chegada para as faixas acompanharem a reta final.
	var distance := float(course.length)-2.0
	while distance > float(course.length)-70.0 and index < titles.size():
		distance -= 2.0
		var road: Transform3D = course.pose(distance)
		var at: Vector3 = course.sample(distance)+road.basis.x*(course.HALF_WIDTH+4.1)
		# O tecido de 1.5 m passa sob as copas; só a linha dos troncos importa.
		if float(course.nearest(at).lateral) < course.HALF_WIDTH+3.4 or not _clear_of_reserved(at,1.9,2.7): continue
		var along := road.basis.z
		var poles: Array[Vector3] = []
		for side in [-1.6,1.6]:
			var pole: Vector3 = at+along*side
			pole.y = course.surface_height(Vector2(pole.x,pole.z))
			poles.append(pole)
			_box(Transform3D(road.basis,pole+Vector3.UP*.72),Vector3(.07,1.6,.07),_material(Color("3b4240")),true)
		var cloth := _material(cloths[index],true)
		var base := minf(poles[0].y,poles[1].y)+.55
		_quad(Vector3(poles[0].x,base,poles[0].z),Vector3(poles[1].x,base,poles[1].z),.85,cloth)
		var label := Label3D.new()
		label.text = titles[index]
		label.font = FONT
		label.font_size = 56
		label.pixel_size = .0105
		label.double_sided = false
		label.modulate = inks[index]
		label.outline_size = 0
		label.transform = Transform3D(Basis(Vector3.UP,atan2(-road.basis.x.x,-road.basis.x.z)),Vector3(at.x,base+.43,at.z)-road.basis.x*.03)
		add_child(label)
		banner_count += 1
		index += 1
		_reserved.append(Vector3(at.x,1.8,at.z))
		distance -= 3.0

func _board() -> void:
	# Painel de controle da corrida em dois postes atrás do degrau mais alto, de frente para a
	# pista como os torcedores: nada fica entre ele e a câmera do jogo.
	var local_basis := bleacher.global_basis
	var steel := _material(Color("3a403e"))
	for side in [-1.9,1.9]:
		var foot: Vector3 = bleacher.transform*Vector3(side,0,1.36)
		foot.y = course.surface_height(Vector2(foot.x,foot.z))
		var top: float = bleacher.position.y+4.2
		_box(Transform3D(local_basis,Vector3(foot.x,(foot.y-.1+top)*.5,foot.z)),Vector3(.16,top-foot.y+.1,.16),steel,true)
		_box(Transform3D(local_basis,foot+Vector3.UP*.05),Vector3(.45,.14,.45),_material(Color("8e8b80")))
	var center: Vector3 = bleacher.transform*Vector3(0,3.3,1.3)
	_box(Transform3D(local_basis,center),Vector3(4.3,1.7,.18),_material(Color("1c2224")),true)
	_box(Transform3D(local_basis,center+Vector3.UP*.92),Vector3(4.5,.12,.3),_material(Color("b75b28")))
	board_title = Label3D.new()
	board_detail = Label3D.new()
	for label in [board_title,board_detail]:
		label.font = FONT
		label.double_sided = false
		label.outline_size = 0
		# O Label3D é lido pelo lado +Z; a arquibancada fica de frente para o próprio -Z.
		label.transform = Transform3D(local_basis*Basis(Vector3.UP,PI),center-local_basis.z*.1)
		add_child(label)
	board_title.font_size = 88
	board_title.pixel_size = .0078
	board_title.modulate = Color("ffc34f")
	board_title.position += Vector3.UP*.35
	board_detail.font_size = 64
	board_detail.pixel_size = .0072
	board_detail.modulate = Color("e9e5d8")
	board_detail.position -= Vector3.UP*.35
	board_title.text = "VÉRTICE MX"
	board_detail.text = ""
