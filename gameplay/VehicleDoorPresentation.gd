extends Node3D
## Portas do motorista de um veículo de passeio, caminhão ou van. Fica pendurado no
## `visual` do Vehicle e só é criado quando alguém entra ou sai (o trânsito continua com as
## malhas compartilhadas). Apresentação apenas: quem manda no espaço livre e na admissão
## continua sendo o Driving.
##
## A folha é recortada do próprio casco (VehicleDoorBuilder), então fechada é idêntica ao
## carro original e aberta deixa um vão real. Cada lado tem dobradiça na frente do vão,
## cartão interno, batentes, maçaneta e o poço escuro atrás; a lataria ganha frestas.
## O cupê esportivo tem o recorte manual próprio (VehicleCoupeDoors).

const BUILDER := preload("res://gameplay/VehicleDoorBuilder.gd")
const SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")

var vehicle: CharacterBody3D
var hinges: Dictionary = {}
var motions: Dictionary = {}
var coupe_ready := false
## Vão da porta no espaço do modelo (tabela) e o que dele deriva em espaço do veículo.
var spec: Dictionary = {}
var layouts: Dictionary = {}
var angle := 1.05
var seat_z := 0.0
var ready_for_boarding := false
var _liners: Dictionary = {}


static var _card: StandardMaterial3D
static var _liner_material: StandardMaterial3D

var _job: RefCounted

## `deferred`: só prepara o recorte (calculado aos poucos por `advance`, sem pico de quadro).
## O cupê tem recorte manual próprio e sempre termina aqui mesmo.
func configure(owner_vehicle: CharacterBody3D, deferred := false) -> void:
	vehicle = owner_vehicle
	name = "DriverDoorPresentation"
	spec = SPECS.row(vehicle.archetype).duplicate()
	if spec.is_empty():
		spec = SPECS.fallback(vehicle.half_length, vehicle.body_height)
		spec.fallback = true
	var kind: String = vehicle.boarding_class()
	angle = float(SPECS.OPEN_ANGLE.get(kind, 1.05))
	if vehicle.archetype == "sport_coupe":
		var coupe_doors = preload("res://gameplay/VehicleCoupeDoors.gd").new()
		add_child(coupe_doors)
		if coupe_doors.configure(vehicle):
			hinges = coupe_doors.hinges
			coupe_ready = true
			angle = 1.05
			_layout(float(spec.get("x", .90)))
			return
		coupe_doors.queue_free()
	_job = BUILDER.begin(vehicle.visual, spec, float(spec.get("x", -1.0)))  # x da tabela evita a varredura de medição
	if not deferred: finish_now()

## Prepara mais um pedaço da porta dentro do orçamento (µs). Devolve true quando está pronta.
func advance(budget_usec: int) -> bool:
	if ready_for_boarding: return true
	if _job == null: return false
	if BUILDER.step(_job, budget_usec): _finish()
	return ready_for_boarding

## Termina agora o que faltar (quem precisa da porta neste quadro: embarque, animação).
func finish_now() -> void:
	if ready_for_boarding or _job == null: return
	BUILDER.step(_job, 1 << 40)
	_finish()

func _finish() -> void:
	var result = _job.result
	_job = null
	result.apply()
	var skin: float = result.skin
	if skin <= 0.0:
		# Nenhuma lataria lateral no vão medido: a folha sai vazia e só as peças de acabamento
		# aparecem. O aviso é para quem cadastrar um modelo novo na tabela.
		skin = maxf(vehicle.half_width / maxf(vehicle.visual.scale.x, .01) - .17, .5)
		push_warning("Porta sem lataria no vão medido: " + vehicle.archetype)
	for side in [-1, 1]: _build_side(side, result, skin)
	_static_details(skin)
	_layout(skin)

## Deriva tudo o que o embarque precisa (ponto de espera, portão, ponto de agarrar) e
## converte para coordenadas do veículo, que é onde Vehicle e Boarding trabalham.
func _layout(skin: float) -> void:
	for side in [-1, 1]:
		var local: Dictionary = SPECS.layout(spec, side, skin, angle, vehicle.half_width / maxf(vehicle.visual.scale.x, .01))
		var scaled := {}
		for key in local:
			scaled[key] = vehicle.visual.transform * local[key] if local[key] is Vector3 else local[key]
		layouts[side] = scaled
	# Banco no meio do vão (um palmo à frente do centro: o quadril fica sobre o assento).
	seat_z = ((float(spec.zf) + float(spec.zr)) * .5 - .06) * vehicle.visual.scale.z
	ready_for_boarding = true

func _build_side(side: int, result, skin: float) -> void:
	var s := float(side)
	var hinge_position := Vector3(s * (skin - .03), 0.0, float(spec.zf))
	var hinge := Node3D.new()
	hinge.name = "DriverDoorL" if side < 0 else "DriverDoorR"
	hinge.position = hinge_position
	add_child(hinge)
	hinges[side] = hinge
	var card := _card_material()
	var outer: Array = BUILDER.to_mesh(result.leaf[side], hinge_position, card)
	var paint: Material = _dominant_paint(result.leaf[side])
	if (outer[0] as ArrayMesh).get_surface_count() > 0:
		_attach(hinge, outer[0], outer[1], "Skin")
	var inner: Array = BUILDER.to_mesh(result.inner[side], hinge_position, card)
	if (inner[0] as ArrayMesh).get_surface_count() > 0:
		_attach(hinge, inner[0], inner[1], "Card")
	if paint != null: _edge_strips(hinge, side, skin, hinge_position, paint)
	_leaf_details(hinge, side, skin, hinge_position)
	var liner := _liner(side, skin)
	liner.visible = false
	add_child(liner)
	_liners[side] = liner

func _attach(hinge: Node3D, mesh: ArrayMesh, keys: Array, label: String) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Mesmo formato que a lataria usa: dano (queimado/estilhaçado) lê por superfície.
	part.set_meta("door_surface_material_keys", keys)
	hinge.add_child(part)

## O material de tinta da folha: o de maior área que não seja vidro. As tiras de acabamento
## usam o MESMO material, então a repintura do veículo chega nelas.
func _dominant_paint(groups: Dictionary) -> Material:
	var best: Material
	var best_size := 0
	for material in groups:
		if material == null: continue
		var group: Dictionary = groups[material]
		var key := str(group.key)
		if "glass" in key or "windshield" in key or key == "window": continue
		if (material is BaseMaterial3D) and (material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED: continue
		var size: int = (group.pos as PackedVector3Array).size()
		if size > best_size:
			best_size = size
			best = material
	return best

static func _card_material() -> StandardMaterial3D:
	if _card == null:
		_card = StandardMaterial3D.new()
		_card.albedo_color = Color("2a2e33")
		_card.roughness = .88
		_card.resource_name = "trim"
	return _card

static func _liner_dark() -> StandardMaterial3D:
	if _liner_material == null:
		_liner_material = StandardMaterial3D.new()
		_liner_material.albedo_color = Color("15181b")
		_liner_material.roughness = .95
	return _liner_material

func _edge_strips(hinge: Node3D, side: int, skin: float, hinge_position: Vector3, paint: Material) -> void:
	var s := float(side)
	var front: float = spec.zf
	var rear: float = spec.zr
	var length := rear - front
	var mid := (front + rear) * .5
	var sill: float = spec.sill
	var belt: float = spec.belt
	var depth := BUILDER.THICKNESS - .012
	var x := s * (skin - depth * .5 - .006)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	# Fecham a folha nas quatro bordas do painel de baixo: sem elas a porta aberta seria uma
	# casca de papel, com o vazio aparecendo entre a lataria e o cartão.
	KIT.box(tool, Vector3(x, sill + .02, mid) - hinge_position, Vector3(depth, .04, length - .012), Color.WHITE)
	KIT.box(tool, Vector3(x, (sill + belt) * .5, front + .02) - hinge_position, Vector3(depth, belt - sill, .04), Color.WHITE)
	KIT.box(tool, Vector3(x, (sill + belt) * .5, rear - .02) - hinge_position, Vector3(depth, belt - sill, .04), Color.WHITE)
	tool.generate_normals()
	var part := MeshInstance3D.new()
	part.name = "Edges"
	part.mesh = tool.commit()
	part.material_override = paint
	hinge.add_child(part)

func _leaf_details(hinge: Node3D, side: int, skin: float, hinge_position: Vector3) -> void:
	var s := float(side)
	var front: float = spec.zf
	var rear: float = spec.zr
	var length := rear - front
	var mid := (front + rear) * .5
	var sill: float = spec.sill
	var belt: float = spec.belt
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	# Lado de dentro (cartão): apoio de braço, puxador, comando do vidro e
	# grade do alto-falante. Só aparecem com a porta aberta.
	var arm := Color("34383d")
	var dark := Color("1b1d20")
	var metal := Color("aab0b6")
	KIT.box(tool, Vector3(s * (skin - .13), belt - .11, mid + .05) - hinge_position, Vector3(.11, .05, minf(.36, length * .45)), arm)
	KIT.box(tool, Vector3(s * (skin - .125), belt - .20, rear - .20) - hinge_position, Vector3(.07, .035, .20), metal)
	KIT.box(tool, Vector3(s * (skin - .11), belt - .06, front + .22) - hinge_position, Vector3(.06, .05, .05), dark)
	KIT.box(tool, Vector3(s * (skin - .105), sill + .17, mid) - hinge_position, Vector3(.03, .14, minf(.30, length * .4)), dark)
	# Lado de fora: rebaixo escuro e a maçaneta que sai da lataria, mais a fechadura.
	KIT.box(tool, Vector3(s * (skin + .004), belt - .11, rear - .22) - hinge_position, Vector3(.01, .065, .22), dark)
	KIT.box(tool, Vector3(s * (skin + .022), belt - .11, rear - .22) - hinge_position, Vector3(.04, .035, .17), Color("c9ced2"))
	KIT.box(tool, Vector3(s * (skin + .012), belt - .15, rear - .09) - hinge_position, Vector3(.02, .02, .02), dark)
	var part := MeshInstance3D.new()
	part.name = "Fittings"
	part.mesh = tool.commit()
	part.material_override = KIT.material()
	hinge.add_child(part)

## Frestas e batente do lado do casco: ficam sempre à mostra, como as juntas de uma porta.
func _static_details(skin: float) -> void:
	var front: float = spec.zf
	var rear: float = spec.zr
	var length := rear - front
	var mid := (front + rear) * .5
	var sill: float = spec.sill
	var belt: float = spec.belt
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var seam := Color("14171a")
	for side in [-1, 1]:
		var s := float(side)
		var x := s * (skin + .003)
		KIT.box(tool, Vector3(x, (sill + belt) * .5, front), Vector3(.008, belt - sill, .012), seam)
		KIT.box(tool, Vector3(x, (sill + belt) * .5, rear), Vector3(.008, belt - sill, .012), seam)
		KIT.box(tool, Vector3(x, sill, mid), Vector3(.008, .012, length), seam)
		KIT.box(tool, Vector3(x, belt, mid), Vector3(.008, .01, length), Color("2c3237"))
	var part := MeshInstance3D.new()
	part.name = "Seams"
	part.mesh = tool.commit()
	part.material_override = KIT.material()
	add_child(part)

## Poço da porta: fundo, frente, trás e soleira, todos escuros. Com o casco oco, sem isto o
## vão mostrava o cenário através do carro. Some quando a porta fecha.
func _liner(side: int, skin: float) -> Node3D:
	var s := float(side)
	var front: float = spec.zf
	var rear: float = spec.zr
	var length := rear - front
	var mid := (front + rear) * .5
	var sill: float = spec.sill
	var belt: float = spec.belt
	var depth := .26
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var wall := Color("16191c")
	KIT.box(tool, Vector3(s * (skin - depth), (sill + belt) * .5, mid), Vector3(.02, belt - sill, length), wall)
	KIT.box(tool, Vector3(s * (skin - depth * .5), (sill + belt) * .5, front + .015), Vector3(depth, belt - sill, .03), wall)
	KIT.box(tool, Vector3(s * (skin - depth * .5), (sill + belt) * .5, rear - .015), Vector3(depth, belt - sill, .03), wall)
	KIT.box(tool, Vector3(s * (skin - depth * .5), sill + .012, mid), Vector3(depth, .024, length), Color("6c7278"))
	var part := MeshInstance3D.new()
	part.name = "Liner"
	part.mesh = tool.commit()
	part.material_override = KIT.material()
	return part

func apply_paint(_color: Color) -> void:
	pass # Tinta compartilhada com a lataria: a repintura já chega à folha.

func set_open(side: int, opened: bool, duration := .28) -> void:
	finish_now()
	if not hinges.has(side): return
	var previous: Tween = motions.get(side)
	if is_instance_valid(previous): previous.kill()
	var hinge: Node3D = hinges[side]
	var liner: Node3D = _liners.get(side)
	if is_instance_valid(liner) and opened: liner.show()
	var target := float(side) * angle if opened else 0.0
	if duration <= 0.0:
		hinge.rotation.y = target
		if is_instance_valid(liner): liner.visible = opened
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(hinge, "rotation:y", target, duration)
	if is_instance_valid(liner) and not opened: tween.tween_callback(liner.hide)
	motions[side] = tween

func close_all(duration := .18) -> void:
	for side in hinges: set_open(side, false, duration)

## Ponto da folha aberta em coordenadas do mundo, para a mão do corpo acompanhar.
func leaf_point(side: int, local_from_hinge: Vector3) -> Vector3:
	var hinge: Node3D = hinges.get(side)
	return hinge.to_global(local_from_hinge) if is_instance_valid(hinge) else vehicle.global_position
