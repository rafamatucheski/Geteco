@tool
extends RefCounted
## A-32b: signs follow the same enabled crossings as the road paint.
## Reference: SENATRAN, Manual Brasileiro de Sinalização, volume II (A-32b).
## No priority/speed signs are inferred from geometry: those need traffic rules.

const SIGN_FACE := preload("res://world/urban_detail/traffic_signs/pedestrian_crossing.png")
const POST_HEIGHT := 2.8
const FACE_CENTER := 2.63
const FACE_SIZE := .84
const MIN_SPACING := 14.0
const BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
## Desgaste por bairro (29/10): placa levemente torta, adesivos nas costas e no poste, ferrugem no
## pé (atlas do HarborStreetWear). GETECO_HARBOR_POLES=0 volta à placa reta e limpa.
const WEAR := preload("res://world/city_look/HarborStreetWear.gd")
var records: Array[Dictionary] = []
var _meshes: Array[Mesh] = []
var _roads: Array[Dictionary] = []

func configure(roads: Array[Dictionary], crossing_layout: Array[Dictionary]) -> void:
	records.clear()
	_roads = roads
	var tunnel_cuts: Array[Rect2] = []
	for cut in load("res://world/urban_detail/CanalTunnel3D.gd").open_cuts(): tunnel_cuts.append(cut)
	for junction in crossing_layout:
		for entry in junction.get("entries", []):
			# .78m curb offset + .045m post radius + >=1.2m clear passage.
			if not entry.get("enabled", false) or float(entry.get("sidewalk", 0)) < 2.1:
				continue
			var outward: Vector2 = entry.direction
			var side := outward.orthogonal()
			var crossing: Vector2 = entry.position
			var at := crossing + outward * (float(entry.depth) * .5 + 4.5)
			at += side * (float(entry.width) * .5 + .78)
			if BRIDGE.owns_surface_point(at): continue
			var over_opening := false
			for cut in tunnel_cuts:
				if cut.grow(.45).has_point(at): over_opening = true; break
			if over_opening: continue
			if not _clear_of_roads(at): continue
			var crowded := false
			for existing in records:
				if at.distance_to(existing.position) < MIN_SPACING:
					crowded = true
					break
			if crowded: continue
			records.append({"position": at, "direction": outward, "crossing_key": entry.key, "code": "A-32b", "district": WEAR.district_at(_roads, at)})
	_prepare_meshes()

func _clear_of_roads(at: Vector2) -> bool:
	for road in _roads:
		var points = road.get("points", PackedVector2Array())
		for i in range(points.size() - 1):
			var a := _flat(points[i])
			var b := _flat(points[i + 1])
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < float(road.get("width", 7.5)) * .5 + .3:
				return false
	return true

func _flat(point: Variant) -> Vector2:
	if point is Vector3: return Vector2(point.x, point.z)
	return point

func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var selected: Array[Dictionary] = []
	for record in records:
		if rect.has_point(record.position): selected.append(record)
	if selected.is_empty(): return
	var owner := Node3D.new()
	owner.name = "HarborTrafficSigns"
	parent.add_child(owner)
	# Base de cada placa no chão; as peças ficam no espaço dela, então a placa torta (bairro de
	# porto/Cobra) inclina inteira na base. Sem inclinação é exatamente a montagem anterior.
	var bases: Array[Transform3D] = []
	for record in selected:
		var d: Vector2 = record.direction
		var at: Vector2 = record.position
		var upright := Transform3D(Basis(Vector3(d.y, 0, -d.x), Vector3.UP, Vector3(d.x, 0, d.y)), Vector3(at.x, 0, at.y))
		bases.append(WEAR.lean(upright, str(record.get("district", "")), "a32b|%d|%d" % [roundi(at.x * 10.0), roundi(at.y * 10.0)]))
	var parts: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, POST_HEIGHT * .5, 0)),
		Transform3D(Basis(Vector3.BACK, PI * .25), Vector3(0, FACE_CENTER, 0)), Transform3D(Basis.IDENTITY, Vector3(0, FACE_CENTER, .025))]
	# Three shared batches per chunk, no frame callbacks or extra light sources.
	var batches: Array[MultiMesh] = []
	for part in _meshes.size():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _meshes[part]
		multi.instance_count = selected.size()
		for i in selected.size():
			multi.set_instance_transform(i, bases[i] * parts[part])
		var visual := MultiMeshInstance3D.new()
		visual.name = ["GalvanizedPosts", "MetalSignBacks", "PedestrianWarningFaces"][part]
		visual.multimesh = multi
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		owner.add_child(visual)
		batches.append(multi)
	var worn: Array = []
	# Índice de cada placa no lote de desgaste (-1 = placa limpa), para os adesivos tombarem junto.
	var worn_index: Array[int] = []
	if WEAR.available():
		for i in selected.size():
			var at: Vector2 = selected[i].position
			worn_index.append(-1)
			if WEAR.roll("a32b|wear|%d|%d" % [roundi(at.x * 10.0), roundi(at.y * 10.0)]) < float(WEAR.WEAR_CHANCE.get(str(selected[i].get("district", "")), 0.0)):
				worn_index[i] = worn.size()
				worn.append(bases[i])
	var wear_batch: MultiMesh = null
	if not worn.is_empty():
		var wear_visual := WEAR.batch("SignWear", WEAR.sign_mesh(), worn)
		owner.add_child(wear_visual)
		wear_batch = wear_visual.multimesh
	var solids := StaticBody3D.new()
	solids.name = "SignpostSolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	owner.add_child(solids)
	var shape := CylinderShape3D.new()
	shape.height = POST_HEIGHT
	shape.radius = .045
	var colliders: Array[CollisionShape3D] = []
	for i in selected.size():
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = bases[i] * parts[0]
		solids.add_child(collider)
		colliders.append(collider)
	if Engine.is_editor_hint(): return
	_register_fragile(owner, bases, parts, batches, wear_batch, worn_index, colliders)

## Playtest 30/10 ("as placas de sinalização não são derrubadas"): a A-32b do Harbor era só
## MultiMesh com um cilindro no SignpostSolids e nunca entrou no FragileProps3D; o poste de 9 cm
## parava o carro como parede a qualquer velocidade. Mesmo arranjo da placa da serra
## (MountainTrafficSigns._register_fragile): um lote-pivô invisível na base de cada placa é a
## instância principal, poste, chapa, face e desgaste vão como peças irmãs, e o colisor da placa vai
## ao registro (o tombo desliga só o dela). Nenhum nó novo por placa.
static func _register_fragile(owner: Node3D, bases: Array[Transform3D], parts: Array[Transform3D], batches: Array[MultiMesh], wear_batch: MultiMesh, worn_index: Array[int], colliders: Array[CollisionShape3D]) -> void:
	if bases.is_empty(): return
	# O registro precisa da posição global; trecho montado fora da árvore registra ao entrar.
	if not owner.is_inside_tree():
		owner.tree_entered.connect(_register_fragile.bind(owner, bases, parts, batches, wear_batch, worn_index, colliders), CONNECT_ONE_SHOT)
		return
	var fragile := preload("res://gameplay/street_physics/FragileProps3D.gd")
	var pivots := fragile.pivot_batch(bases)
	for i in bases.size():
		var extra := []
		for part in batches.size():
			extra.append({"multimesh": batches[part], "index": i, "offset": parts[part]})
		# O lote de desgaste já está no espaço da base da placa: deslocamento nulo.
		if wear_batch != null and i < worn_index.size() and worn_index[i] >= 0:
			extra.append({"multimesh": wear_batch, "index": worn_index[i], "offset": Transform3D.IDENTITY})
		fragile.register_instance("road_sign", pivots, i, owner, extra, [colliders[i]])

func _prepare_meshes() -> void:
	if not _meshes.is_empty(): return
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("87918f")
	metal.metallic = .65
	metal.roughness = .67
	if WEAR.enabled:
		# Galvanizado com relevo e rugosidade de metal (as mesmas opções do CityLookMaterials.flat:
		# shader já compilado). Liso, o poste e as costas da placa liam como plástico cinza.
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(metal, "metal", 1.2, .45)
		metal.albedo_color = Color(minf(.53 * metal.albedo_color.r, 1.0), minf(.57 * metal.albedo_color.g, 1.0), minf(.56 * metal.albedo_color.b, 1.0))
		metal.roughness = .85
	var post := CylinderMesh.new()
	post.top_radius = .035
	post.bottom_radius = .035
	post.height = POST_HEIGHT
	post.radial_segments = 8
	post.rings = 1
	post.material = metal
	var back := BoxMesh.new()
	back.size = Vector3(FACE_SIZE / sqrt(2.0), FACE_SIZE / sqrt(2.0), .035)
	back.material = metal
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = SIGN_FACE
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	paint.alpha_scissor_threshold = .5
	paint.roughness = .72
	var face := QuadMesh.new()
	face.size = Vector2.ONE * FACE_SIZE
	face.material = paint
	_meshes.assign([post, back, face])
