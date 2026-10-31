extends RefCounted
## Chão povoado do deserto (arte de carregamento desert_highway.png): moitas de sálvia, arbustos secos,
## pedras, cascalho e tufos de capim. Cinco malhas e um material compartilhados; cada trecho vira no
## máximo cinco MultiMesh; o corredor da arrancada usa lotes de 48 m para recortar
## a vegetação fora da câmera. Sem colisão nativa, luz ou callback por quadro.
## A disposição é fatiada por orçamento de tempo (HOW-TO-DEVELOP, regra 1): o trecho de 96 m tem
## ~4 mil peças e as alturas/reservas custam dezenas de ms se feitas num quadro só.
## GETECO_DESERT_GROUND_COVER=0 desliga a camada (A/B no mesmo export).
const G := preload("res://world/desert/expansion/DesertEcologyGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Célula de disposição em metros, alinhada ao mundo: trechos vizinhos sorteiam as mesmas peças.
const SUB := 8.0
const KINDS := ["sage", "brittle", "stone", "gravel", "tuft"]
const CONTACT_KINDS := ["desert_shrub", "desert_shrub", "desert_stone", "desert_gravel", "desert_grass"]
## Distância da câmera (não do jogador): a ortográfica fica a ~36 m do chão e o canto da tela
## ultrawide a ~72 m. O cascalho some antes das moitas, que são o que dá a leitura de longe.
const VISIBILITY := [115.0, 115.0, 105.0, 85.0, 90.0]
## Só o corredor retido da câmera da arrancada precisa de fade espacial. Um limite duro
## num lote inteiro de 96 m revelava buracos retangulares na corrida vista de lado.
const DRAG_CORRIDOR := Rect2(-916,-920,1248,192)
const DRAG_BATCH_SIZE := 48.0
static var _meshes: Array[ArrayMesh] = []
static var _mesh_bounds: Array[AABB] = []
static var _material: StandardMaterial3D
static var _drag_materials: Array[StandardMaterial3D] = []
static var _enabled := -1

class Build:
	var cells: Array[Vector2i] = []
	var next := 0
	## Um membro por tipo: PackedFloat32Array dentro de Array é cópia por valor e cada append
	## recopiaria o buffer inteiro.
	var sage := PackedFloat32Array()
	var brittle := PackedFloat32Array()
	var stone := PackedFloat32Array()
	var gravel := PackedFloat32Array()
	var tuft := PackedFloat32Array()
	var preview: Array = [[], [], [], [], []]
	var preview_enabled := false
	var committed := false
	## O gerador ainda visita o retângulo original de 96 m uma vez. Mandar a fileira
	## pronta para um buffer menor preserva o RNG e as lascas que cruzam uma borda interna.
	var parts: Array[Build] = []
	var part_origin := Vector2.ZERO
	var part_columns := 0
	var next_part := 0
	var bounds: Array[AABB] = [AABB(),AABB(),AABB(),AABB(),AABB()]
	var has_bounds: Array[bool] = [false,false,false,false,false]
	## [tipo, índice] das peças grandes que o carro acerta (moitas e pedras); o resto é chão.
	var solid: Array[Vector2i] = []
	var visuals: Array = []
	var next_contact := 0
	## Altura da célula atual: com o chão plano (fora do relevo, da mina e do cânion, quase todo o
	## deserto) os 4 cantos bastam e cada peça interpola, em vez de chamar a altura do trecho por peça.
	var height: Callable
	var cell_origin := Vector2.ZERO
	var corners := PackedFloat32Array([0, 0, 0, 0])
	var flat := false

	func prepare_cell(origin: Vector2) -> void:
		cell_origin = origin
		for i in 4: corners[i] = float(height.call(origin + Vector2(float(i & 1), float(i >> 1)) * SUB))
		var center := float(height.call(origin + Vector2.ONE * SUB * .5))
		var low := minf(minf(corners[0], corners[1]), minf(corners[2], corners[3]))
		var high := maxf(maxf(corners[0], corners[1]), maxf(corners[2], corners[3]))
		flat = high - low < .03 and absf(center - (corners[0] + corners[1] + corners[2] + corners[3]) * .25) < .01

	func height_at(p: Vector2) -> float:
		if not flat: return float(height.call(p))
		var t := ((p - cell_origin) / SUB).clamp(Vector2.ZERO, Vector2.ONE)
		return lerpf(lerpf(corners[0], corners[1], t.x), lerpf(corners[2], corners[3], t.x), t.y)

	func push(kind: int, values: PackedFloat32Array) -> void:
		match kind:
			0: sage.append_array(values)
			1: brittle.append_array(values)
			2: stone.append_array(values)
			3: gravel.append_array(values)
			_: tuft.append_array(values)

	func buffer(kind: int) -> PackedFloat32Array:
		return [sage, brittle, stone, gravel, tuft][kind]

	func release() -> void:
		sage = PackedFloat32Array(); brittle = PackedFloat32Array(); stone = PackedFloat32Array()
		gravel = PackedFloat32Array(); tuft = PackedFloat32Array()
		preview.clear()
		solid.clear()
		parts.clear()
		visuals.clear()

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_DESERT_GROUND_COVER") == "0" else 1
	return _enabled == 1

static func begin(rect: Rect2) -> Build:
	var state := Build.new()
	var area := rect.intersection(LAYOUT.BOUNDS)
	if not enabled() or not area.has_area():
		state.committed = true
		return state
	for z in range(floori(area.position.y / SUB), ceili(area.end.y / SUB)):
		for x in range(floori(area.position.x / SUB), ceili(area.end.x / SUB)): state.cells.append(Vector2i(x, z))
	if DRAG_CORRIDOR.intersects(rect):
		_prepare()
		state.part_origin=rect.position
		state.part_columns=ceili(rect.size.x/DRAG_BATCH_SIZE)
		for i in state.part_columns*ceili(rect.size.y/DRAG_BATCH_SIZE): state.parts.append(Build.new())
	return state

## Devolve true quando o trecho terminou. `budget_usec` é por chamada; INF completa de uma vez
## (trecho ocupado pelo jogador antes de admitir atores).
static func step(chunk: Node3D, rect: Rect2, state: Build, height: Callable, clear: Callable, budget_usec: float) -> bool:
	if state.committed: return true
	var began := Time.get_ticks_usec()
	var trace := STALL_WORK.begin()
	state.height = height
	state.preview_enabled = Engine.get_meta("geteco_live_preview_build", false)
	var worked := false
	while state.next < state.cells.size():
		_cell(state, rect, state.cells[state.next], clear)
		state.next += 1
		worked=true
		if Time.get_ticks_usec() - began >= budget_usec: break
	if state.next >= state.cells.size():
		if state.parts.is_empty():
			state.committed = _commit(chunk, state, rect, "", budget_usec, began)
		else:
			# Não transforma quatro uploads/registros num pico final maior.
			# Chamadas finitas confirmam uma parte de 48 m por vez até o mesmo orçamento acabar.
			while state.next_part<state.parts.size():
				if worked and Time.get_ticks_usec()-began>=budget_usec: break
				if not _commit(chunk,state.parts[state.next_part],rect,"_%d"%state.next_part,budget_usec,began): break
				state.next_part+=1
				worked=true
			if state.next_part==state.parts.size():
				state.release()
				state.committed=true
	STALL_WORK.finish_slow("stream.desert.dress.ground_cover", trace, 2000)
	return state.committed

static func _cell(state: Build, rect: Rect2, cell: Vector2i, clear: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(cell.x * 92821 + cell.y * 68917 + 4401)
	var origin := Vector2(cell) * SUB
	var center := origin + Vector2.ONE * SUB * .5
	# Uma consulta de reserva por célula; só a célula que encosta em estrada, prédio ou relevo
	# íngreme paga a consulta por peça.
	var open := bool(clear.call(center, SUB * .71))
	state.prepare_cell(origin)
	var patch := _patch(center)
	# Moitas: o que mais aparece na arte. Densidade em manchas para não virar tapete uniforme.
	for i in int(round(lerpf(2.0, 9.0, patch) + rng.randf_range(-.8, .8))):
		var p := origin + Vector2(rng.randf(), rng.randf()) * SUB
		var kind := 0 if rng.randf() < .68 else 1
		var size := rng.randf_range(.55, 1.45)
		if _keep(rect, p, open, clear, .7 * size): _add(state, kind, p, size, rng, _tint(rng, .82, 1.12))
	for i in rng.randi_range(1, 5):
		var p := origin + Vector2(rng.randf(), rng.randf()) * SUB
		var size := rng.randf_range(.18, .62) if rng.randf() < .85 else rng.randf_range(.7, 1.0)
		if _keep(rect, p, open, clear, .5 * size): _add(state, 2, p, size, rng, _tint(rng, .78, 1.15), true)
	for i in rng.randi_range(2, 6):
		var p := origin + Vector2(rng.randf(), rng.randf()) * SUB
		if _keep(rect, p, open, clear, .3): _add(state, 4, p, rng.randf_range(.7, 1.35), rng, _tint(rng, .85, 1.1))
	# Cascalho em manchas: uma consulta por mancha, lascas sem consulta própria.
	for cluster in rng.randi_range(2, 4):
		var p := origin + Vector2(rng.randf(), rng.randf()) * SUB
		if not open and not bool(clear.call(p, 1.4)): continue
		for chip in rng.randi_range(8, 16):
			var at := p + Vector2(rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3))
			if rect.has_point(at): _add(state, 3, at, rng.randf_range(.08, .22), rng, _tint(rng, .55, 1.2), true)

static func _keep(rect: Rect2, p: Vector2, open: bool, clear: Callable, radius: float) -> bool:
	return rect.has_point(p) and (open or bool(clear.call(p, radius)))

static func _patch(p: Vector2) -> float:
	var n := sin(p.x * .021 + p.y * .013) * .5 + sin(p.x * .007 - p.y * .019 + 1.7) * .35 + sin(p.x * .053 + p.y * .047) * .15
	return clampf(.5 + n * .55, 0.0, 1.0)

static func _tint(rng: RandomNumberGenerator, low: float, high: float) -> Color:
	var shade := rng.randf_range(low, high)
	return Color(shade, shade * rng.randf_range(.97, 1.02), shade * rng.randf_range(.94, 1.0), 1.0)

static func _add(state: Build, kind: int, p: Vector2, size: float, rng: RandomNumberGenerator, color: Color, tumble := false) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if tumble: basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-.35, .35))
	var squash := Vector3(rng.randf_range(.85, 1.15), rng.randf_range(.75, 1.1), rng.randf_range(.85, 1.15)) if tumble else Vector3(1, rng.randf_range(.85, 1.15), 1)
	basis = basis.scaled(squash * size)
	# Peças sólidas afundam um pouco para não flutuar em chão inclinado.
	var origin := Vector3(p.x, state.height_at(p) - (.25 * size if tumble else .04), p.y)
	var target := state
	if not state.parts.is_empty():
		var local := p-state.part_origin
		var part := floori(local.y/DRAG_BATCH_SIZE)*state.part_columns+floori(local.x/DRAG_BATCH_SIZE)
		target=state.parts[part]
		# Limita a geometria original durante a geração já orçada.
		# O upload não precisa pedir de forma síncrona ao renderer que descubra o AABB.
		var instance_bounds: AABB=Transform3D(basis,origin)*_mesh_bounds[kind]
		target.bounds[kind]=target.bounds[kind].merge(instance_bounds) if target.has_bounds[kind] else instance_bounds
		target.has_bounds[kind]=true
	target.solid.append(Vector2i(kind, target.buffer(kind).size() / 16))
	target.push(kind, PackedFloat32Array([basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, basis.y.y, basis.z.y, origin.y, basis.x.z, basis.y.z, basis.z.z, origin.z, color.r, color.g, color.b, 1.0]))
	if state.preview_enabled: target.preview[kind].append(Transform3D(basis, origin))

static func _commit(chunk: Node3D, state: Build, rect: Rect2, suffix := "", budget_usec := INF, began := 0) -> bool:
	if state.visuals.is_empty(): _upload(chunk, state, rect, suffix)
	var fragile := preload("res://gameplay/street_physics/FragileProps3D.gd")
	while state.next_contact < state.solid.size():
		var entry := state.solid[state.next_contact]
		var node: MultiMeshInstance3D = state.visuals[entry.x]
		if node != null:
			var pose := node.multimesh.get_instance_transform(entry.y)
			var bounds: AABB = Transform3D(pose.basis, Vector3.ZERO) * _mesh_bounds[entry.x]
			var radius := maxf(bounds.size.x, bounds.size.z) * .5
			fragile.register_instance(CONTACT_KINDS[entry.x], node.multimesh, entry.y, chunk, [], [], node, radius)
		state.next_contact += 1
		# Dense gravel remains indexed without a multi-thousand-item commit spike.
		if state.next_contact % 32 == 0 and Time.get_ticks_usec() - began >= budget_usec: return false
	state.release()
	return true

static func _upload(chunk: Node3D, state: Build, rect: Rect2, suffix: String) -> void:
	_prepare()
	var visuals: Array = [null, null, null, null, null]
	for kind in KINDS.size():
		var buffer := state.buffer(kind)
		if buffer.is_empty(): continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _meshes[kind]
		batch.instance_count = buffer.size() / 16
		batch.buffer = buffer
		if state.has_bounds[kind]: batch.custom_aabb=state.bounds[kind]
		var node := MultiMeshInstance3D.new()
		node.name = "DesertGroundCover%s_%s" % [suffix,KINDS[kind]]
		node.multimesh = batch
		node.material_override = _material
		# Sem sombra: com as moitas projetando, o p50 de GPU subiu ~1,4 ms na rota66 do release de 17/10
		# (o passe direcional desenha os trechos além da tela). O pé escuro da malha assenta a moita.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = VISIBILITY[kind]
		if DRAG_CORRIDOR.intersects(rect): configure_drag_visibility(node,kind)
		# Só mobiliário de chão não interativo; pedras e arbustos quebráveis mantêm o alcance autorado.
		if KINDS[kind] in ["gravel","tuft"] and not DRAG_CORRIDOR.intersects(rect):
			preload("res://runtime/GraphicsOptions.gd").tag_detail(node)
		if Engine.get_meta("geteco_live_preview_build", false):
			node.set_meta("preview_instance_transforms", state.preview[kind])
			var colors: Array = []
			for i in batch.instance_count: colors.append(Color(buffer[i * 16 + 12], buffer[i * 16 + 13], buffer[i * 16 + 14], 1.0))
			node.set_meta("preview_instance_colors", colors)
		chunk.add_child(node)
		visuals[kind] = node
	state.visuals = visuals

static func configure_drag_visibility(node: MultiMeshInstance3D, kind: int) -> void:
	# O dither por pixel do StandardMaterial funciona com Mobile; o fade de HLOD do
	# GeometryInstance não. Transforms/cores das instâncias e índices quebráveis ficam intactos.
	node.material_override=_drag_material(kind)
	var bounds: AABB=node.multimesh.custom_aabb
	if not bounds.has_volume(): bounds=node.get_aabb()
	var radius: float=bounds.size.length()*.5
	# O culling usa o centro do lote. O vértice mais próximo já está totalmente apagado
	# antes deste limite, então retângulos do tamanho do streaming não aparecem de repente.
	node.visibility_range_end=float(VISIBILITY[kind])+15.0+radius+2.0

static func _drag_material(kind: int) -> StandardMaterial3D:
	_prepare()
	if _drag_materials.is_empty():
		for distance: float in VISIBILITY:
			var material:=_material.duplicate() as StandardMaterial3D
			material.distance_fade_mode=BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			material.distance_fade_max_distance=distance-25.0
			material.distance_fade_min_distance=distance+15.0
			_drag_materials.append(material)
	return _drag_materials[kind]

static func material() -> StandardMaterial3D:
	_prepare()
	return _material

static func meshes() -> Array[ArrayMesh]:
	_prepare()
	return _meshes

static func _prepare() -> void:
	if _material != null: return
	# Mesmos sinalizadores do material da flora da expansão: o shader já existe; o pré-aquecimento
	# (prewarm_draw) cobre a variante de MultiMesh com cor por instância.
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	_material.metallic_specular = 0.0
	_meshes = [_sage(), _brittle(), _stone(), _gravel(), _tuft()]
	for kind in _meshes.size():
		var mesh := _meshes[kind]
		_mesh_bounds.append(mesh.get_aabb())
		# Os estilhaços compartilhados são preparados com as cinco malhas fonte, nunca fraturados/lidos
		# de volta da GPU para cada pedrinha atingida durante o jogo.
		var source := MeshInstance3D.new()
		source.mesh = mesh
		source.material_override = _material
		var fragments: Array[Mesh] = []
		for shard in preload("res://gameplay/street_physics/PropFracture3D.gd").split(source, 0):
			fragments.append(shard.mesh)
			shard.free()
		mesh.set_meta("street_fracture_meshes", fragments)
		source.free()

static func _sage() -> ArrayMesh:
	# Moita arredondada cinza-oliva: um domo e cinco bolos baixos em volta, com galhos no pé.
	var data := G.buffer()
	# Cinza-oliva escuro e apagado da arte; o verde vivo da primeira versão lia como couve-flor.
	var colors := [Color("5c5c4a"), Color("4d4e40"), Color("6a6853"), Color("575646")]
	# ~215 triângulos: com ~700 moitas por trecho, a contagem de vértices pesa mais que o detalhe.
	G.ellipsoid(data, Transform3D(Basis(), Vector3(0, .30, 0)), Vector3(.40, .30, .38), colors[0], 6, 3)
	for i in 5:
		var angle := float(i) * TAU / 5.0 + .4
		var at := Vector3(cos(angle) * .32, .19 + float(i % 2) * .07, sin(angle) * .30)
		# Bolos de baixo mais escuros: fazem o papel da sombra que a camada não projeta.
		G.ellipsoid(data, Transform3D(Basis(), at), Vector3(.27, .21, .25) * (1.0 - float(i % 3) * .1), colors[(i + 1) % 4].darkened(.12 if i % 2 == 0 else 0.0), 6, 3)
	# Galhos secos furando a copa: tiram o contorno de bolo e dão a textura riscada da arte.
	for i in 6:
		var angle := float(i) * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		G.branch(data, Vector3(0, .12, 0), radial * (.5 + float(i % 3) * .07) + Vector3.UP * (.42 + float(i % 4) * .06), .014, .003, Color("6b5a44"), 3)
	return G.mesh(data)

static func _brittle() -> ArrayMesh:
	# Arbusto seco e espetado (palha), como os da beira da pista na arte.
	var data := G.buffer()
	for i in 7:
		var angle := float(i) * 2.399963
		var radial := Vector3(cos(angle), 0, sin(angle))
		var fork := radial * .22 + Vector3.UP * (.26 + float(i % 3) * .05)
		var tip := radial * .52 + Vector3.UP * (.48 + float(i % 4) * .06)
		G.branch(data, Vector3(0, -.02, 0), fork, .022, .011, Color("7d6849"), 3)
		G.branch(data, fork, tip, .011, .003, Color("9b845f"), 3)
		G.ellipsoid(data, Transform3D(Basis(), tip), Vector3(.10, .05, .08), Color("8a8458") if i % 2 else Color("9f9064"), 4, 2)
	return G.mesh(data)

static func _stone() -> ArrayMesh:
	# Bloco facetado de 1 m (escala por instância), mesma silhueta das pedras de DesertSurfaceRocks.
	var data := G.buffer()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var rings: Array[PackedVector3Array] = []
	for level in 4:
		var ring := PackedVector3Array()
		var y: float = [-.45, -.18, .2, .42][level]
		var radius: float = [.62, .5, .42, .2][level]
		for side in 7:
			var angle := float(side) * TAU / 7.0 + .13 * float(level)
			var r := radius * rng.randf_range(.8, 1.0)
			ring.append(Vector3(cos(angle) * r, y + rng.randf_range(-.03, .03), sin(angle) * r * .85))
		rings.append(ring)
	var base := Color("776a5b")
	for level in 3:
		var tone := base.lightened(float(level) * .05)
		for side in 7:
			var next := (side + 1) % 7
			G.triangle(data, rings[level][side], rings[level + 1][next], rings[level + 1][side], tone)
			G.triangle(data, rings[level][side], rings[level][next], rings[level + 1][next], tone)
	for side in 7: G.triangle(data, rings[3][side], rings[3][(side + 1) % 7], Vector3(0, .46, 0), base.lightened(.16))
	return G.mesh(data)

static func _gravel() -> ArrayMesh:
	# Lasca achatada de seis faces em cima e seis embaixo; a cor vem da instância.
	var data := G.buffer()
	var top := Vector3(0, .5, 0)
	var bottom := Vector3(0, -.5, 0)
	var ring: Array[Vector3] = []
	for side in 6:
		var angle := float(side) * TAU / 6.0
		ring.append(Vector3(cos(angle) * (1.0 if side % 2 == 0 else .8), 0, sin(angle) * (1.0 if side % 2 == 0 else .8)))
	for side in 6:
		var a := ring[side]
		var b := ring[(side + 1) % 6]
		G.triangle(data, a, b, top, Color("6e6252"))
		G.triangle(data, b, a, bottom, Color("4f463b"))
	return G.mesh(data)

static func _tuft() -> ArrayMesh:
	# Tufo de capim seco: lâminas de dupla face, pé escuro e ponta clara (cor por vértice).
	var data := G.buffer()
	for blade in 11:
		var angle := float(blade) * 2.39996
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x) * .03
		var foot := radial * .06
		var tip := radial * (.16 + float(blade % 3) * .05) + Vector3.UP * (.28 + float(blade % 4) * .06)
		for face in 2:
			var a := foot - side if face == 0 else foot + side
			var b := foot + side if face == 0 else foot - side
			var normal := (b - a).cross(tip - a).normalized()
			data.vertices.append_array(PackedVector3Array([a, tip, b]))
			data.normals.append_array(PackedVector3Array([normal, normal, normal]))
			data.colors.append_array(PackedColorArray([Color("6f5e40"), Color("c2ab78"), Color("6f5e40")]))
	return G.mesh(data)

## Pré-aquecimento sob a cortina (receita de ForgePrewarm/WildlifePrewarm): desenha as cinco malhas em
## MultiMesh com o material retido, para a variante não compilar no primeiro trecho do deserto.
static var _prewarmed := false
static func prewarm_draw(host: Node3D, curtain: CanvasLayer) -> void:
	if _prewarmed or not enabled() or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args(): return
	var guards := preload("res://gameplay/emergency/EffectsPrewarm.gd")
	if not guards._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not guards._current_camera(host, camera): return
	_prepare()
	var began := Time.get_ticks_usec()
	var stage := Node3D.new()
	stage.name = "DesertGroundCoverPrewarm"
	host.add_child(stage)
	for kind in KINDS.size():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _meshes[kind]
		batch.instance_count = 2
		for i in 2:
			batch.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * .3), Vector3(float(kind) * .4 - .8, float(i) * .3, 0)))
			batch.set_instance_color(i, Color.WHITE)
		var node := MultiMeshInstance3D.new()
		node.multimesh = batch
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(node)
		# Aquece a variante de dither do corredor local da arrancada sob a mesma cortina.
		var drag_node:=MultiMeshInstance3D.new()
		drag_node.multimesh=batch
		drag_node.material_override=_drag_material(kind)
		drag_node.position.y=.7
		drag_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(drag_node)
	# Pele do saguaro (UV do cilindro, não triplanar): variante própria, aquecida junto.
	var saguaro := MeshInstance3D.new()
	saguaro.mesh = CylinderMesh.new()
	saguaro.scale = Vector3.ONE * .2
	saguaro.material_override = preload("res://world/desert/DesertArchitecture.gd").saguaro_skin(Color("647052"), 1.0)
	stage.add_child(saguaro)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(stage, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in 24:
		stage.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 6.0)
		await host.get_tree().process_frame
		if not guards._covered_loading(host, curtain) or not is_instance_valid(stage): break
		if draws[0] >= 3:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(stage): stage.free()
	_prewarmed = completed
	print("Chão do deserto preparado: ", JSON.stringify({"completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}))
