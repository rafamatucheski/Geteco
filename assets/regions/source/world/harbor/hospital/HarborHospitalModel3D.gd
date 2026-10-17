extends Node3D
## Bay Medical: masonry wards, glazed reception and recessed ambulance vestibule.
const PPM := 18.0
const FLOOR_RATIO := 0.76822128
var door_leaves: Array[Node3D] = []
var public_leaves: Array[Node3D] = []
var door_amount := 0.0
var public_walkup_enabled := false
var open_amount := 0.0
var materials: Dictionary = {}
const OVERHEAD_LAYER := 2
## Ala oeste pintada (frente BAY MEDICAL, fundos, lateral e telhado são imagens do
## PaintedFacadeKit). Pegada em px do modelo: x -130..30, y -115..115, parede de 5,0 m.
const PAINTED_STYLE := "clinica-oeste-v2"
const WEST_CENTER_PX := Vector2(-50.0, 0.0)
const WEST_SIZE_PX := Vector2(160.0, 230.0)
const WEST_HEIGHT := 5.0
## Descida dos equipamentos de telhado: a laje antiga ficava em 5,265 m e a pintada
## em 5,0 m, então o que apoiava na antiga flutuaria 0,25 m sobre a pintada.
const PAINTED_ROOF_DROP := 0.25
## Nó do kit pintado (null com GETECO_PAINTED_CLINIC=0, GETECO_PAINTED_FACADES=0 ou
## fora da fábrica urbana).
var painted_west: Node3D

func overhead(mesh: MeshInstance3D) -> MeshInstance3D:
	mesh.layers = OVERHEAD_LAYER
	return mesh

func floor_point(point: Vector2, height := 0.0) -> Vector3:
	return Vector3(point.x / PPM, height, point.y / (PPM * FLOOR_RATIO))

func material(color: Color, glass := false) -> StandardMaterial3D:
	var key := str(color) + str(glass)
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 0.99: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.24 if glass else 0.78
	mat.metallic = 0.22 if glass else 0.0
	if glass: mat.set_meta("city_window", true)
	materials[key] = mat
	return mat

func box(point: Vector2, size: Vector2, bottom: float, height: float, color: Color, parent: Node3D = self, glass := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x / PPM, height, size.y / (PPM * FLOOR_RATIO))
	node.mesh = mesh
	node.material_override = material(color, glass)
	node.position = floor_point(point, bottom + height * 0.5)
	parent.add_child(node)
	return node

## Interruptor da ala oeste pintada: respeita o do kit (GETECO_PAINTED_FACADES) e tem o seu
## (GETECO_PAINTED_CLINIC=0 volta às caixas antigas para A/B). Só na versão com a entrada
## pública por onde o jogador passa (a da fábrica urbana).
func painted_west_enabled() -> bool:
	# Ligado por padrão a pedido do usuário (16/10), sem a rodada final de verificação completa.
	return public_walkup_enabled and PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_CLINIC") != "0"

## Caixa que continua existindo só pela colisão (e pelo `interior_solid_id`): o visual
## fica escondido porque a ala oeste pintada ocupa o mesmo lugar. A colisão derivada
## (UrbanBuildingFactory.finalize_building) lê o AABB da malha, não a visibilidade.
func _collision_only(node: MeshInstance3D, painted: bool) -> MeshInstance3D:
	if painted: node.visible = false
	return node

func _build_painted_west() -> void:
	var size := Vector3(WEST_SIZE_PX.x / PPM, WEST_HEIGHT, WEST_SIZE_PX.y / (PPM * FLOOR_RATIO))
	var kit_parent := Node3D.new()
	kit_parent.name = "PaintedWestWing"
	kit_parent.position = floor_point(WEST_CENTER_PX)
	add_child(kit_parent)
	# Sem colisão do kit (as caixas escondidas já a fazem) e sem porta pintada: a entrada
	# é a porta deslizante 3D (`public_leaves`).
	painted_west = PaintedFacadeKit.build(kit_parent, PAINTED_STYLE, size, null, NAN, {"snow": false})
	# O vão pintado é sem folha e o kit põe um corredor escuro atrás dele; aqui a entrada
	# real é a porta 3D, e o corredor seria um beco falso. No lugar, o recuo de 1,37 m da
	# entrada (o da antiga caixa de ala) ganha um forro claro.
	for corridor in painted_west.find_children("Corridor", "MeshInstance3D", true, false):
		corridor.get_parent().remove_child(corridor)
		corridor.free()
	_add_entry_liner(kit_parent)
	# finalize_building cria colisão trimesh para toda malha larga com y < 2,8 m; a das
	# laterais pintadas (paredes planas na mesma face das caixas escondidas) seria só
	# redundante. Um corpo vazio faz a rotina pular a malha (corpo sem forma, inerte).
	var sides := painted_west.get_node_or_null("Sides")
	if sides != null:
		var marker := StaticBody3D.new()
		marker.name = "NoDerivedCollision"
		marker.collision_layer = 0
		marker.collision_mask = 0
		sides.add_child(marker)

## Forro do recuo atrás da folha deslizante: fundo, laterais, teto e piso do vão pintado
## (x -32..30 px, 2,1 m de altura, do plano da fachada até a parede de fundo em y=96 px).
func _add_entry_liner(parent: Node3D) -> void:
	var liner := MeshInstance3D.new()
	liner.name = "EntryLiner"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(62.0 / PPM, 2.1, 19.0 / (PPM * FLOOR_RATIO))
	liner.mesh = mesh
	var liner_material := StandardMaterial3D.new()
	liner_material.albedo_color = Color("c9cdc3")
	liner_material.roughness = 0.85
	# Só as faces de dentro: de fora se vê o fundo do recuo pelo vão, nunca o forro por fora.
	liner_material.cull_mode = BaseMaterial3D.CULL_FRONT
	liner.material_override = liner_material
	liner.position = floor_point(Vector2(-1.0, 105.5), 1.05) - parent.position
	liner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(liner)

func _ready() -> void:
	var painted := painted_west_enabled()
	var roof_drop := PAINTED_ROOF_DROP if painted else 0.0
	var ivory := Color("dddcd0")
	var teal := Color("337f80")
	var charcoal := Color("35444a")
	var glazing := Color("639da6")
	# The east recess leaves a real, level corridor through the building footprint.
	if public_walkup_enabled:
		# Preserve the ward footprint, with a standing vestibule behind the
		# public sliding leaves. Ambulance geometry is independent to the east.
		_collision_only(box(Vector2(-50, -9.5), Vector2(160, 211), 0, 5.0, ivory), painted)
		var west_jamb := _collision_only(box(Vector2(-81, 105.5), Vector2(98, 19), 0, 5.0, ivory), painted)
		west_jamb.set_meta("interior_solid_id", "hospital_public_west_jamb")
		_collision_only(box(Vector2(-1, 105.5), Vector2(62, 19), 2.1, 2.9, ivory), painted)
	else:
		box(Vector2(-50, 0), Vector2(160, 230), 0, 5.0, ivory)
	box(Vector2(80, -67.5), Vector2(100, 95), 0, 4.0, ivory)
	box(Vector2(67.5, -7), Vector2(75, 26), 0, 4.0, ivory)
	box(Vector2(67.5, 94.5), Vector2(75, 41), 0, 3.1, ivory)
	_apron(Vector2(80, 40), Vector2(100, 68), .09)
	# Partition the lower apron around the 9 cm forecourt above. Preserve the
	# perimeter/access levels without leaving one opaque slab under another.
	_apron(Vector2(121, -6.5), Vector2(34, 25), .07)
	_apron(Vector2(121, 95.5), Vector2(34, 43), .07)
	_apron(Vector2(134, 40), Vector2(8, 68), .07)
	for x in range(54, 132, 13):
		box(Vector2(x, 40), Vector2(0.7, 50), 0.09, 0.008, Color("a5afb0"))
	# Clean parapets and inset roof surfaces retain a readable silhouette.
	# Parapeito e laje do telhado da ala oeste: o telhado pintado e a cornija do kit tomam o lugar.
	if not painted:
		box(Vector2(-50, 0), Vector2(164, 234), 5.0, 0.23, Color("eeeade"))
		box(Vector2(-50, 0), Vector2(151, 221), 5.24, 0.025, Color("78878b"))
	box(Vector2(80, -54.5), Vector2(103, 124), 4.0, 0.20, Color("eeeade"))
	box(Vector2(80, -54.5), Vector2(93, 114), 4.2, 0.03, Color("718387"))
	var service_roof := overhead(box(Vector2(67.5, 94.5), Vector2(78, 42), 3.1, 0.17, Color("eeeade")))
	service_roof.name = "AdmissionWingRoof"
	# Repeated, recessed windows with raised fins on the street frontage.
	# Janelas da frente da ala oeste: a frente pintada já as traz.
	for x in ([] if painted else [-110.0, -76.0, -42.0, -8.0, 26.0]):
		for level in [1.4, 3.3]:
			if level < 2.0 and x > -30.0: continue # Public doorway occupies this facade band.
			var window_height := 1.0 if level > 3.0 else 1.15
			box(Vector2(x, 115.4), Vector2(24, 1.4), level, window_height, charcoal)
			box(Vector2(x, 116.3), Vector2(21, 0.8), level+0.09, window_height-0.19, glazing, self, true)
			box(Vector2(x, 117.2), Vector2(1.0, 1.6), level+0.08, window_height-0.17, Color("d9e5de"))
	for y in [-99.0, -69.0, -39.0]:
		box(Vector2(130.5, y), Vector2(1.2, 23), 1.3, 1.85, charcoal)
		box(Vector2(131.2, y), Vector2(0.6, 20), 1.4, 1.65, glazing, self, true)
		box(Vector2(133, y-13), Vector2(5, 1.2), 0.4, 3.4, Color("c7cfca"))
	if not painted: box(Vector2(-40, 116.5), Vector2(179, 2), 2.9, 0.14, teal)
	if public_walkup_enabled:
		if not painted: box(Vector2(-81, 116.5), Vector2(97, 2), 0.1, 0.35, Color("6c8182"))
		box(Vector2(41, 116.5), Vector2(17, 2), 0.1, 0.35, Color("6c8182"))
	else:
		box(Vector2(-40, 116.5), Vector2(179, 2), 0.1, 0.35, Color("6c8182"))
	# Public reception: native glazing around the existing playable south door.
	if not public_walkup_enabled:
		box(Vector2(0, 116), Vector2(68, 3), 0, 1.9, charcoal)
	# The dark recess is revealed when the leaves slide. A second full-width
	# fixed glass panel here made the entrance appear closed while opening.
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		add_child(leaf)
		leaf.position = floor_point(Vector2(side*15, 120))
		box(Vector2.ZERO, Vector2(29, 1.5), 0.08, 1.73, charcoal, leaf)
		box(Vector2(0, 1), Vector2(26, 0.6), 0.16, 1.55, glazing, leaf, true)
		box(Vector2(side*-10, 2), Vector2(1, 1), 0.67, 0.42, Color("dee5dc"), leaf)
		public_leaves.append(leaf)
		if public_walkup_enabled: _add_public_leaf_collision(leaf)
	box(Vector2(0, 126), Vector2(81, 23), 2.05, 0.15, teal)
	for x in [-37.0, 37.0]: box(Vector2(x, 134), Vector2(2, 2), 0, 2.05, Color("d7dfdb"))
	# Ambulance canopy: cantilevered, so no column can trap the crew or stretcher.
	var canopy := overhead(box(Vector2(126, 40), Vector2(108, 64), 2.8, 0.06, Color(0.58,0.78,0.77,0.48), self, true))
	canopy.name = "EmergencyGlassCanopy"
	for x in [73.0, 109.0, 145.0, 179.0]:
		overhead(box(Vector2(x, 40), Vector2(2, 64), 2.8, 0.16, Color("e3e6dc")))
	overhead(box(Vector2(126, 7), Vector2(109, 2), 2.76, 0.29, teal))
	overhead(box(Vector2(181, 40), Vector2(2, 65), 2.76, 0.29, teal))
	overhead(box(Vector2(126, 73), Vector2(109, 2), 2.76, 0.29, teal))
	for y in [18.0, 62.0]:
		overhead(box(Vector2(115, y), Vector2(72, 1.3), 2.72, 0.03, Color("fff0c9")))
	# Sliding leaves are recessed 28 px from the facade, under the canopy.
	for y in [15.0, 65.0]: box(Vector2(102, y), Vector2(3, 3), 0, 2.65, charcoal)
	box(Vector2(102, 40), Vector2(3, 53), 2.55, 0.1, charcoal)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		add_child(leaf)
		leaf.position = floor_point(Vector2(102, 40 + side*12))
		box(Vector2.ZERO, Vector2(1.5, 23), 0.06, 2.48, charcoal, leaf)
		box(Vector2(0.9, 0), Vector2(0.7, 20), 0.18, 2.24, Color("5b8a90"), leaf, true)
		box(Vector2(1.5, 0), Vector2(0.8, 20), 1.1, 0.13, Color("c9ded8"), leaf)
		door_leaves.append(leaf)
	# A lit vestibule and interior passage remain visible between the doors.
	box(Vector2(36, 40), Vector2(2, 68), 0, 2.75, Color("acc2bf"))
	box(Vector2(62, 7), Vector2(52, 2), 0, 2.7, Color("e0e4d9"))
	box(Vector2(62, 73), Vector2(52, 2), 0, 2.7, Color("e0e4d9"))
	# Rooftop plant, louvres and a restrained medical cross. Com o telhado pintado (5,0 m,
	# não a laje antiga de 5,265 m) o equipamento desce junto para não flutuar; as juntas
	# finas da laje antiga somem, o telhado pintado já tem as suas.
	for x in [-88.0, -53.0]:
		box(Vector2(x, -72), Vector2(25, 34), 5.25 - roof_drop, 0.7, Color("b7c1be"))
		for line in 5: box(Vector2(x, -85+line*6), Vector2(20, 1.4), 5.96 - roof_drop, 0.02, charcoal)
	for y in [-40.0, 65.0]:
		box(Vector2(-85, y), Vector2(35, 24), 5.27 - roof_drop, 0.30, charcoal)
		box(Vector2(-85, y), Vector2(31, 20), 5.58 - roof_drop, 0.04, glazing, self, true)
		box(Vector2(-85, y), Vector2(1.2, 20), 5.64 - roof_drop, 0.03, Color("d2ddd6"))
	if not painted:
		for y in range(-105, 111, 27):
			box(Vector2(-50, y), Vector2(147, 0.5), 5.27, 0.008, Color("6d8083"))
	box(Vector2(-4, -11), Vector2(44, 44), 5.27 - roof_drop, 0.04, teal)
	box(Vector2(-4, -11), Vector2(9, 30), 5.32 - roof_drop, 0.03, Color("f0eddf"))
	box(Vector2(-4, -11), Vector2(30, 9), 5.32 - roof_drop, 0.03, Color("f0eddf"))
	# A frente pintada já traz BAY MEDICAL e a cruz: sem letreiro nem placa 3D.
	if not painted:
		var title := Label3D.new()
		title.name = "HospitalName"
		title.text = "BAY MEDICAL"
		title.font_size = 64
		title.pixel_size = 0.006
		title.position = floor_point(Vector2(-43, 117.7), 4.75)
		title.modulate = Color("285d61")
		title.outline_size = 0
		var nameplate := box(Vector2(-43, 117.35), Vector2(76, 0.5), 4.4, 0.6, Color("eeeade"))
		nameplate.name = "HospitalNameplate"
		add_child(title)
	# Side cross marks emergency admission without adding explanatory signage.
	box(Vector2(108, -7), Vector2(2, 19), 2.7, 0.10, Color("e4ede5"))
	box(Vector2(108, -7), Vector2(2, 5), 2.3, 0.92, Color("e4ede5"))
	if painted: _build_painted_west()

func _apron(point: Vector2, size: Vector2, height: float) -> void:
	var floor_mesh := box(point,size,0,height,Color("b4babc"))
	floor_mesh.name = "HospitalApron"
	# Thin floors are excluded by the general facade collider heuristic.
	# Their own collision keeps feet/tyres on the visible 7/9 cm access level.
	floor_mesh.create_trimesh_collision()
	for body in floor_mesh.get_children():
		if body is StaticBody3D:
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("pedestrian_step",true)
			body.set_meta("pedestrian_step_top",height*.5)

func set_door_amount(amount: float) -> void:
	door_amount = amount
	for index in door_leaves.size():
		var side := -1.0 if index == 0 else 1.0
		door_leaves[index].position = floor_point(Vector2(102, 40 + side*(12+23*amount)))

func set_public_door_amount(amount: float) -> void:
	for index in public_leaves.size():
		var side := -1.0 if index == 0 else 1.0
		public_leaves[index].position = floor_point(Vector2(side*(15+24*amount),120))

func set_open_amount(amount: float) -> void:
	if not public_walkup_enabled: return
	open_amount = clampf(amount, 0.0, 1.0)
	set_public_door_amount(open_amount)

func _add_public_leaf_collision(leaf: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "PublicDoorSolid"
	body.set_meta("interior_solid_id", "hospital_public_door")
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(29.0 / PPM, 1.81, .12)
	collision.shape = shape
	collision.position.y = .905
	body.add_child(collision)
	leaf.add_child(body)
