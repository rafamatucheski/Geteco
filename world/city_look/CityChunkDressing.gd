extends RefCounted
## Acabamento visual "cidade de jogo" aplicado a cada chunk de Harbor depois
## que o NativeRegion termina de montá-lo.
##
## Roda uma única vez por chunk (no streaming, não por quadro) e só acrescenta
## adereços ou troca material de malhas já existentes: não move prédio, não
## mexe em colisão da fonte V1 e não depende de nenhuma arte ser reescrita.
## Quem quiser desligar tudo remove a chamada em NativeRegion._build_chunk.
##
## Tudo que é repetido (hidrante, lixeira, mancha de óleo, ar-condicionado)
## sai em MultiMesh por tipo e por chunk. Os adereços são só visuais, sem
## colisão: não entram no caminho de pedestres/tráfego nem mudam a física que
## os testes de fidelidade conferem.

const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")
const BRANDS := preload("res://world/city_look/CityBrands.gd")
const LIFE := preload("res://world/city_look/BuildingLife.gd")
const STAIRS := preload("res://world/city_look/WalkableStairs.gd")
const ROOFS := preload("res://world/city_look/RoofSurfaces.gd")
const POLICE := preload("res://world/city_look/PoliceStationDressing.gd")
const NIGHT_GROUP := &"city_look_night"
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const FRAGILE_KINDS := ["signal_pole", "stop_sign", "hydrant", "trash_can", "news_box", "mailbox", "phone_booth"]

# Fração de janelas acesas à noite. Residência acende menos que vitrine.
const WINDOW_LIT_RATIO := 0.38
const SHOP_LIT_RATIO := 0.85
# Largura da calçada gerada por HarborRoadGeometry3D (42 px de cada lado).
const SIDEWALK := 42.0 / 16.0
const SEWER_ACCESS := Vector2(1182.0, 2114.0) / 16.0
const SEWER_CLEARANCE := 2.0
const FURNITURE_SPACING := 7.0
# Postes de calçada gerados (2026-09-25: jogador achou a cidade escura demais;
# só havia luz onde a arte autorada trazia um poste). Alterna os lados a cada
# LAMP_SPACING, então cada calçada tem um poste a cada 2×LAMP_SPACING e as
# manchas de luz (~11 m) se emendam em zigue-zague pela rua.
const LAMP_SPACING := 18.0
const LAMP_HEIGHT := 5.4
const LAMP_ARM := 1.3
# Poste autorado ou gerado mais perto que isso já ilumina o trecho.
const LAMP_CLEARANCE := 9.0
static var _lamp_meshes: Dictionary = {}
const DECAL_Y := 0.034
const SHADOW_CASTERS := ["water_tank", "cooling_tower", "signal_pole", "dumpster", "phone_booth", "billboard_frame", "ac_unit", "fe_platform", "fe_stair", "fe_stair_m", "window_ac", "laundry",
	# Mobília de calçada: sem sombra, lixeira/hidrante/jornaleiro pareciam soltos,
	# flutuando sobre a calçada (relato do jogador em 2026-09-24).
	"trash_can", "news_box", "mailbox", "hydrant", "stop_sign", "bench_seat", "planter", "bollard", "trash_bags"]


static func build_chunk(region: Node3D, chunk: Node3D, rect: Rect2) -> void:
	var context := _context(region, rect)
	var batches := {}
	_night_pass(chunk, context)
	_sidewalk_lamps(chunk, context)
	STAIRS.build_chunk(chunk)
	_texture_walls(chunk)
	_face_ground_up(chunk)
	_junction_signage(context, batches, chunk)
	_sidewalk_furniture(context, batches)
	_building_surroundings(context, batches)
	_road_wear(context, batches)
	_rooftops(chunk, context, batches)
	_flush(chunk, batches)


# ---------------------------------------------------------------------------
# Contexto: só as vias/prédios que tocam o chunk, para os testes de colisão
# visual (não pôr lixeira no asfalto nem dentro de prédio) ficarem baratos.

static func _context(region: Node3D, rect: Rect2) -> Dictionary:
	var grown := rect.grow(16.0)
	var roads: Array = []
	var junctions: Array = []
	var geometry = region.get("harbor_road_geometry")
	if geometry != null:
		for road in geometry._roads:
			var points: PackedVector2Array = road.points
			var bounds := Rect2(points[0], Vector2.ZERO)
			for point in points: bounds = bounds.expand(point)
			if bounds.grow(float(road.width)).intersects(grown): roads.append(road)
		for junction in geometry._junctions:
			if grown.has_point(junction.position): junctions.append(junction)
	var buildings: Array = []
	for building in region.get("buildings"):
		var center := Vector2(building.position.x, building.position.z)
		var footprint := Rect2(center - building.size * 0.5, building.size)
		if footprint.grow(4.0).intersects(grown): buildings.append({"rect": footprint, "data": building})
	return {"region": region, "rect": rect, "roads": roads, "junctions": junctions, "buildings": buildings, "geometry": geometry, "lamps": []}


static func _in_chunk(context: Dictionary, point: Vector2) -> bool:
	return (context.rect as Rect2).has_point(point)


## Distância até o eixo da via mais próxima menos a meia largura: <0 é asfalto,
## 0..SIDEWALK é calçada.
static func _road_clearance(context: Dictionary, point: Vector2) -> float:
	var best := INF
	for road in context.roads:
		var points: PackedVector2Array = road.points
		for index in points.size() - 1:
			var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
			best = minf(best, point.distance_to(closest) - float(road.width) * 0.5)
	return best


static func _inside_building(context: Dictionary, point: Vector2, margin := 0.3) -> bool:
	for building in context.buildings:
		if (building.rect as Rect2).grow(margin).has_point(point): return true
	return false


static func _near_junction(context: Dictionary, point: Vector2, extra := 5.0) -> bool:
	for junction in context.junctions:
		var widest := 0.0
		for index in junction.roads: widest = maxf(widest, float(context.geometry._roads[int(index)].width))
		if point.distance_to(junction.position) < widest * 0.68 + extra: return true
	return false


static func _near_lamp(context: Dictionary, point: Vector2, radius := 1.6) -> bool:
	for lamp in context.lamps:
		if point.distance_to(lamp) < radius: return true
	return false


static func _roll(key: String) -> float:
	return float(key.hash() % 10007) / 10007.0


static func _add(batches: Dictionary, kind: String, point: Vector3, forward: Vector2, scale := 1.0) -> void:
	# forward: direção (x,z) para onde a frente (+Z local) do adereço aponta.
	var yaw := atan2(forward.x, forward.y)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(Transform3D(basis, point))


static func _flush(chunk: Node3D, batches: Dictionary) -> void:
	var built := {}
	for kind in batches:
		var transforms: Array = batches[kind]
		if transforms.is_empty(): continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var material: Material
		var shadows := true
		if kind.begins_with("decal:"):
			var spec: Dictionary = _decal_spec(kind.trim_prefix("decal:"))
			multimesh.mesh = _flat_quad()
			material = spec.material
			shadows = false
		elif kind == "signal_amber":
			multimesh.use_colors = true
			multimesh.mesh = _lens_mesh()
			material = MATERIALS.signal_lens()
			shadows = false
		elif kind.begins_with("roofmat:"):
			multimesh.mesh = _flat_quad()
			material = ROOFS.material(kind.trim_prefix("roofmat:").to_int())
			shadows = false
		elif kind == "wall_ao":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			multimesh.mesh = quad
			material = MATERIALS.wall_ao()
			shadows = false
		elif kind == "beacon_lens":
			multimesh.mesh = _lens_mesh()
			material = MATERIALS.beacon()
			shadows = false
		elif kind.begins_with("graffiti:"):
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			multimesh.mesh = quad
			material = LIFE.graffiti_material(kind.trim_prefix("graffiti:").to_int())
			shadows = false
		else:
			multimesh.mesh = KIT.mesh(kind)
			material = KIT.material()
			# Peça de telhado pequena (antena, respiro, antena parabólica) segue sem
			# sombra: dobrava as primitivas na passada de sombra sem aparecer nesta câmera.
			shadows = kind in SHADOW_CASTERS
		multimesh.instance_count = transforms.size()
		for index in transforms.size():
			multimesh.set_instance_transform(index, chunk.global_transform.affine_inverse() * transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "CityLook_" + kind.replace(":", "_")
		instance.multimesh = multimesh
		instance.material_override = material
		if not shadows: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(instance)
		built[kind] = multimesh
		if kind == "signal_amber":
			var lenses: Array = chunk.get_meta("signal_lenses", [])
			for index in mini(lenses.size(), multimesh.instance_count):
				JUNCTIONS.register_lens(multimesh, index, lenses[index][0], lenses[index][1])
			chunk.remove_meta("signal_lenses")
	_register_fragile(chunk, batches, built)


## Mobília e semáforo viram quebráveis (StreetPhysics). A lente do semáforo é
## outra MultiMesh; vai junto como peça irmã, com o mesmo índice de criação.
static func _register_fragile(chunk: Node3D, batches: Dictionary, built: Dictionary) -> void:
	for kind in FRAGILE_KINDS:
		if not built.has(kind): continue
		var multimesh: MultiMesh = built[kind]
		for index in multimesh.instance_count:
			var extra := []
			if kind == "signal_pole" and built.has("signal_amber") and index < built.signal_amber.instance_count:
				var pole := multimesh.get_instance_transform(index)
				var lens: Transform3D = built.signal_amber.get_instance_transform(index)
				extra.append({"multimesh": built.signal_amber, "index": index, "offset": pole.affine_inverse() * lens})
			FRAGILE.register_instance(kind, multimesh, index, chunk, extra)


# ---------------------------------------------------------------------------
# 1. Noite: postes com cabeça emissiva + mancha de luz, janelas acesas.

static func _night_pass(chunk: Node3D, context: Dictionary) -> void:
	var lamp_roots := {}
	var pools := PackedVector3Array()
	var pool_sizes := PackedFloat32Array()
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_inside_tree(): continue
		var lamp_height := _lamp_height(mesh)
		if lamp_height > 0.0:
			mesh.material_override = MATERIALS.lamp_head()
			var head := mesh.global_position
			pools.append(Vector3(head.x, head.y - lamp_height + 0.06, head.z))
			pool_sizes.append(clampf(lamp_height * 2.3, 6.0, 11.0))
			context.lamps.append(Vector2(head.x, head.z))
			var root := _lamp_root(mesh)
			if root != null and not lamp_roots.has(root): lamp_roots[root] = pools.size() - 1
			continue
		_treat_window(mesh)
	if not pools.is_empty():
		for index in pools.size(): pools[index] = chunk.to_local(pools[index])
		var pool_instance := _light_pools(pools, pool_sizes)
		chunk.add_child(pool_instance)
		# Poste que o carro derruba apaga a própria mancha de luz.
		for root in lamp_roots:
			FRAGILE.register_node("lamp", root, chunk, {"multimesh": pool_instance.multimesh, "index": lamp_roots[root]})


## Postes novos nas calçadas: haste+braço e cabeça em duas MultiMesh (a
## cabeça usa o material emissivo compartilhado que CityLook acende à noite),
## mais mancha de luz no chão como nos postes autorados. Nenhuma Light3D: o
## custo é o de três MultiMesh por chunk. O carro derruba o poste (FragileProps
## tipo "lamp") e a mancha daquele poste apaga.
static func _sidewalk_lamps(chunk: Node3D, context: Dictionary) -> void:
	var transforms: Array[Transform3D] = []
	for road in context.roads:
		var points: PackedVector2Array = road.points
		var width: float = road.width
		var travelled := 0.0
		var step := 0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var tangent := (b - a) / length
			var normal := Vector2(tangent.y, -tangent.x)
			var s := fposmod(-travelled, LAMP_SPACING)
			step = int(round((travelled + s) / LAMP_SPACING))
			while s < length:
				var side := 1.0 if step % 2 == 0 else -1.0
				step += 1
				var outward: Vector2 = normal * side
				var point := a + tangent * s + outward * (width * 0.5 + 0.45)
				s += LAMP_SPACING
				if not _in_chunk(context, point): continue
				if _near_junction(context, point, 2.0) or _near_lamp(context, point, LAMP_CLEARANCE): continue
				if _road_clearance(context, point) < 0.2 or _inside_building(context, point, 0.5): continue
				if WORLD_CONNECTION.reserves_approach_for_driving(point): continue
				if point.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: continue
				context.lamps.append(point)
				var yaw := atan2(-outward.x, -outward.y)
				transforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.012, point.y)))
			travelled += length
	if transforms.is_empty(): return
	var to_local := chunk.global_transform.affine_inverse()
	var poles := _lamp_multimesh("pole", transforms.size())
	var heads := _lamp_multimesh("head", transforms.size())
	var pools := PackedVector3Array()
	var pool_sizes := PackedFloat32Array()
	for index in transforms.size():
		var local := to_local * transforms[index]
		poles.set_instance_transform(index, local)
		heads.set_instance_transform(index, local)
		var head := local * Vector3(0, LAMP_HEIGHT, LAMP_ARM)
		pools.append(Vector3(head.x, local.origin.y + 0.05, head.z))
		pool_sizes.append(clampf(LAMP_HEIGHT * 2.3, 6.0, 11.0))
	var pole_instance := MultiMeshInstance3D.new()
	pole_instance.name = "CityLook_sidewalk_lamp"
	pole_instance.multimesh = poles
	pole_instance.material_override = MATERIALS.flat(Color("4a5054"), 0.6)
	chunk.add_child(pole_instance)
	var head_instance := MultiMeshInstance3D.new()
	head_instance.name = "CityLook_sidewalk_lamp_head"
	head_instance.multimesh = heads
	head_instance.material_override = MATERIALS.lamp_head()
	head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(head_instance)
	var pool_instance := _light_pools(pools, pool_sizes)
	pool_instance.name = "CitySidewalkLampPools"
	chunk.add_child(pool_instance)
	for index in transforms.size():
		var base := poles.get_instance_transform(index)
		# register_instance não recebe a mancha; o registro direto é o mesmo
		# formato, com "pool" como register_node usa para apagar a luz.
		FRAGILE._register({"kind": "lamp", "multimesh": poles, "index": index,
			"extra": [{"multimesh": heads, "index": index, "offset": Transform3D.IDENTITY}],
			"pool": {"multimesh": pool_instance.multimesh, "index": index},
			"chunk": weakref(chunk), "base": base, "point": transforms[index].origin, "state": "standing"})


static func _lamp_multimesh(part: String, count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _lamp_mesh(part)
	multimesh.instance_count = count
	return multimesh


## Poste de rua moderno: base, haste, braço para o lado da via (+Z local) e
## luminária achatada. Malhas compartilhadas por todos os chunks.
static func _lamp_mesh(part: String) -> ArrayMesh:
	if _lamp_meshes.has(part): return _lamp_meshes[part]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if part == "pole":
		_lamp_box(tool, Vector3(0, 0.2, 0), Vector3(0.34, 0.4, 0.34))
		_lamp_box(tool, Vector3(0, LAMP_HEIGHT * 0.5, 0), Vector3(0.13, LAMP_HEIGHT, 0.13))
		_lamp_box(tool, Vector3(0, LAMP_HEIGHT - 0.05, LAMP_ARM * 0.5), Vector3(0.09, 0.09, LAMP_ARM))
		_lamp_box(tool, Vector3(0, LAMP_HEIGHT + 0.03, LAMP_ARM + 0.02), Vector3(0.36, 0.1, 0.62))
	else:
		_lamp_box(tool, Vector3(0, LAMP_HEIGHT - 0.04, LAMP_ARM + 0.02), Vector3(0.3, 0.05, 0.54))
	tool.generate_normals()
	var mesh := tool.commit()
	_lamp_meshes[part] = mesh
	return mesh


static func _lamp_box(tool: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	]
	for face in faces:
		var q: Array[Vector3] = []
		for corner in face: q.append(center + corner * h)
		for i in [0, 2, 1, 0, 3, 2]: tool.add_vertex(q[i])


## Altura aproximada da cabeça do poste acima do chão, ou 0 se a malha não é
## uma luminária. Os nomes vêm de HarborProp3D, HarborAreaDressing3D,
## HarborBridge3D e HarborRouteProps.create_streetlight.
static func _lamp_height(mesh: MeshInstance3D) -> float:
	var label := String(mesh.name)
	if label.contains("LampHead"): return 2.9
	if label in ["Bulb", "Lens"] or label.begins_with("Globe_"):
		var root := mesh.get_parent() as Node3D
		if root != null and String(root.name).begins_with("StreetLight"):
			return maxf(2.5, mesh.global_position.y - root.global_position.y)
	return 0.0


## Raiz que gira quando o poste tomba: o nó do poste inteiro, com origem no
## chão. Postes da Cobra e da ponte ficam de fora (várias luminárias no mesmo
## nó; tombar um derrubaria o bairro inteiro).
static func _lamp_root(head: MeshInstance3D) -> Node3D:
	var parent := head.get_parent() as Node3D
	if parent == null: return null
	var label := String(parent.name)
	if label.begins_with("HarborLamp") or label.begins_with("StreetLight"): return parent
	return null


static func _treat_window(mesh: MeshInstance3D) -> void:
	var material := mesh.material_override
	if material == null: return
	var kind := ""
	if material == UrbanMaterials.glass_window() or material == UrbanMaterials.glass_window_lit(true) or material == UrbanMaterials.glass_window_lit(false):
		kind = "window"
	elif material == UrbanMaterials.glass_display() or material == UrbanMaterials.glass_warm_interior():
		kind = "shop"
	elif material is StandardMaterial3D and String(mesh.name).contains("Glass") and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		kind = "window"
	if kind.is_empty(): return
	# Claraboia (vidro deitado) não acende: de cima leria como laje amarela.
	var aabb := mesh.global_transform * mesh.get_aabb()
	if aabb.size.y < minf(aabb.size.x, aabb.size.z) * 0.5: return
	# Janela de verdade tem ~1 m de altura ou mais; faixa baixa e comprida é
	# lanternim/dente de serra no telhado e virava tubo de luz à noite.
	if aabb.size.y < 0.9 and maxf(aabb.size.x, aabb.size.z) > 2.5: return
	if aabb.size.y < 0.6 and aabb.size.y < maxf(aabb.size.x, aabb.size.z) * 0.25: return
	# Vidro inclinado (dente de serra de galpão): a face fina aponta para
	# cima, não para a rua. Fica como está.
	var local_size := mesh.get_aabb().size
	var thin_axis := 0
	if local_size.y < local_size[thin_axis]: thin_axis = 1
	if local_size.z < local_size[thin_axis]: thin_axis = 2
	if absf(mesh.global_basis[thin_axis].normalized().y) > 0.35: return
	var roll := _position_roll(mesh.global_position)
	_pull_out(mesh)
	if kind == "shop":
		mesh.material_override = MATERIALS.shop_glass() if roll < SHOP_LIT_RATIO else material
		return
	if roll < WINDOW_LIT_RATIO:
		# ~1 em 7 acesas é TV: azul trêmulo à noite (CityLook anima).
		if roll < WINDOW_LIT_RATIO * 0.14: mesh.material_override = MATERIALS.window_tv()
		else: mesh.material_override = MATERIALS.window_lit(int(roll * 1000.0) % MATERIALS.WINDOW_TONES.size())
	else:
		# Apagada continua vidro, mas opaco (vidro transparente sobre caixa
		# escura custa uma passada transparente sem ganho visual). Variantes de
		# cortina/persiana tiram a cara de fileira idêntica de dia.
		var variant := int(_position_roll(mesh.global_position + Vector3(7.1, 0, 3.3)) * 10.0)
		mesh.material_override = MATERIALS.window_unlit(variant) if variant < MATERIALS.UNLIT_VARIANTS else MATERIALS.flat(Color(0.20, 0.29, 0.34), 0.18)


## O arquétipo põe o vidro (2 cm) dentro da caixa do caixilho (8 cm): as faces
## ficam no mesmo plano e piscam (z-fighting), muito visível na janela acesa.
## Empurra o vidro 4 cm para fora, pelo eixo fino, no sentido oposto ao centro
## do prédio.
static func _pull_out(mesh: MeshInstance3D) -> void:
	var building := mesh.get_parent()
	while building != null and not building is UrbanBuildingBase: building = building.get_parent()
	if building == null: return
	var size := mesh.get_aabb().size
	var axis := 0
	if size.y < size[axis]: axis = 1
	if size.z < size[axis]: axis = 2
	var normal: Vector3 = mesh.global_basis[axis].normalized()
	if normal.dot(mesh.global_position - (building as Node3D).global_position) < 0.0: normal = -normal
	mesh.global_position += normal * 0.04


## Sorteio determinístico por posição: a mesma janela acende sempre, em
## qualquer carregamento do chunk. hash() de Vector3i tem bits baixos pouco
## variados entre vizinhos; via string o módulo distribui de verdade.
static func _position_roll(point: Vector3) -> float:
	return _roll("%d,%d,%d" % [roundi(point.x * 4.0), roundi(point.y * 4.0), roundi(point.z * 4.0)])


static func _light_pools(points: PackedVector3Array, sizes: PackedFloat32Array) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _flat_quad()
	multimesh.instance_count = points.size()
	for index in points.size():
		var basis := Basis.IDENTITY.scaled(Vector3(sizes[index], 1.0, sizes[index]))
		multimesh.set_instance_transform(index, Transform3D(basis, points[index]))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CityLightPools"
	instance.multimesh = multimesh
	instance.material_override = MATERIALS.light_pool()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = MATERIALS.night > 0.01
	instance.add_to_group(NIGHT_GROUP)
	return instance


static func _flat_quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	return quad


static func _lens_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.2
	sphere.radial_segments = 10
	sphere.rings = 5
	return sphere


# ---------------------------------------------------------------------------
# 2. Cruzamentos: semáforo onde há faixa de pedestre, placa de PARE nos
# cruzamentos que a V1 deixou sem sinalização.
#
# O semáforo é de verdade: cada poste registra o cruzamento e a faixa de parada em
# TrafficJunctions, que alterna as fases e que o trânsito respeita. A lente mostra
# a cor da aproximação que ela encara (antes piscava amarelo porque o trânsito
# ignorava sinal).

static func _junction_signage(context: Dictionary, batches: Dictionary, chunk: Node3D) -> void:
	var geometry = context.geometry
	if geometry == null: return
	for junction in context.junctions:
		var center: Vector2 = junction.position
		if not _in_chunk(context, center): continue
		var arms: Array = geometry._crossing_arms(junction)
		if arms.size() < 3: continue
		var widest := 0.0
		for index in junction.roads: widest = maxf(widest, float(geometry._roads[int(index)].width))
		var setback := maxf(1.5, widest * 0.68 + 0.875 - 0.5) + 1.9
		var signalized: bool = not geometry._is_unsignalized(center)
		for arm in arms:
			var d: Vector2 = arm.direction
			var width: float = arm.width
			# Lado direito de quem chega ao cruzamento (mão inglesa não existe
			# em Harbor): mesma convenção de NativeTrafficRoutes._lane_offset.
			var right := Vector2(d.y, -d.x)
			var base := center + d * setback + right * (width * 0.5 + 0.9)
			if _road_clearance(context, base) < 0.2 or _inside_building(context, base): continue
			var point := Vector3(base.x, 0.02, base.y)
			if signalized:
				# Poste: local +X = right, +Z = d (placa e sinal voltados para
				# quem chega).
				var basis := Basis(Vector3(right.x, 0, right.y), Vector3.UP, Vector3(d.x, 0, d.y))
				if not batches.has("signal_pole"): batches["signal_pole"] = []
				batches["signal_pole"].append(Transform3D(basis, point))
				var lens := point + basis * Vector3(-3.3, 4.55, 0.2)
				if not batches.has("signal_amber"): batches["signal_amber"] = []
				batches["signal_amber"].append(Transform3D(Basis.IDENTITY, lens))
				var center3 := Vector3(center.x, 0.0, center.y)
				JUNCTIONS.register_signal(center3, setback - 1.2)
				var lenses: Array = chunk.get_meta("signal_lenses", [])
				lenses.append([center3, Vector3(-d.x, 0.0, -d.y)])
				chunk.set_meta("signal_lenses", lenses)
			else:
				_add(batches, "stop_sign", point, d)


# ---------------------------------------------------------------------------
# Calçada: hidrante, lixeira, jornaleiro, caixa de correio, orelhão, banco.

const FURNITURE := [
	["hydrant", 0.13], ["trash_can", 0.14], ["news_box", 0.07], ["mailbox", 0.05],
	["phone_booth", 0.03], ["bench_seat", 0.04], ["trash_bags", 0.05], ["planter", 0.03],
]


static func _sidewalk_furniture(context: Dictionary, batches: Dictionary) -> void:
	for road in context.roads:
		var points: PackedVector2Array = road.points
		var width: float = road.width
		var travelled := 0.0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var tangent := (b - a) / length
			var normal := Vector2(tangent.y, -tangent.x)
			var s := fposmod(-travelled, FURNITURE_SPACING)
			while s < length:
				for side in [-1.0, 1.0]:
					var key := "%s|%d|%d|%d" % [road.id, index, int(s * 10.0), int(side)]
					var jitter := (_roll(key + "j") - 0.5) * 2.4
					var along := a + tangent * clampf(s + jitter, 0.0, length)
					var outward: Vector2 = normal * side
					var point := along + outward * (width * 0.5 + 0.55)
					if not _in_chunk(context, point): continue
					var kind := _pick(FURNITURE, _roll(key))
					if kind.is_empty(): continue
					if _near_junction(context, point) or _near_lamp(context, point): continue
					if _road_clearance(context, point) < 0.25 or _inside_building(context, point, 0.6): continue
					# Orelhão e banco ficam mais para dentro, encostados no lado
					# do prédio, para não invadir o meio-fio.
					if kind in ["phone_booth", "bench_seat", "planter"]:
						point = along + outward * (width * 0.5 + SIDEWALK - 0.7)
						if _inside_building(context, point, 0.5): continue
					# Both divided lanes share a structural bridge deck. Their inner
					# "sidewalks" are the driving median, not a place for furniture.
					if WORLD_CONNECTION.reserves_approach_for_driving(point): continue
					if point.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: continue
					_add(batches, kind, Vector3(point.x, 0.012, point.y), -outward)
				s += FURNITURE_SPACING
			travelled += length


static func _pick(table: Array, roll: float) -> String:
	var acc := 0.0
	for entry in table:
		acc += float(entry[1])
		if roll < acc: return entry[0]
	return ""


# ---------------------------------------------------------------------------
# 3. Entorno dos prédios: sombra de contato (AO falsa) e caçamba/lixo no
# beco lateral. A câmera olha para o norte, então só lateral e frente sul
# aparecem; caçamba no fundo ficaria escondida pelo próprio prédio.

static func _building_surroundings(context: Dictionary, batches: Dictionary) -> void:
	for entry in context.buildings:
		var footprint: Rect2 = entry.rect
		var data: Dictionary = entry.data
		var center := footprint.get_center()
		if not _in_chunk(context, center): continue
		# Sombra de contato em duas camadas: halo largo e suave + faixa estreita
		# e escura colada na parede (é ela que "assenta" o prédio no chão).
		var margin := 1.8
		var ao_size := footprint.size + Vector2.ONE * margin * 2.0
		var basis := Basis.IDENTITY.scaled(Vector3(ao_size.x, 1, ao_size.y))
		_push(batches, "decal:contact", Transform3D(basis, Vector3(center.x, DECAL_Y, center.y)))
		var tight := footprint.size + Vector2.ONE * 0.9
		_push(batches, "decal:contact_tight", Transform3D(Basis.IDENTITY.scaled(Vector3(tight.x, 1, tight.y)), Vector3(center.x, DECAL_Y + 0.001, center.y)))
		# Oclusão na base da fachada sul (a única que a câmera vê): gradiente
		# escuro de 1,3 m subindo do chão.
		var face := Vector3(center.x, 0.65, footprint.end.y + 0.018)
		_push(batches, "wall_ao", Transform3D(Basis.IDENTITY.scaled(Vector3(footprint.size.x + 0.04, 1.3, 1)), face))
		var id := str(data.get("id", ""))
		if str(data.get("kind", "")) in ["cobra_house"]: continue
		for side in [-1.0, 1.0]:
			var key := id + "|alley|" + str(side)
			if _roll(key) > 0.42: continue
			var z := center.y + (_roll(key + "z") - 0.6) * footprint.size.y * 0.6
			var point := Vector2(center.x + side * (footprint.size.x * 0.5 + 1.05), z)
			if _inside_building(context, point, 0.9) or _road_clearance(context, point) < SIDEWALK + 0.4: continue
			if point.distance_to(SEWER_ACCESS) < SEWER_CLEARANCE: continue
			_add(batches, "dumpster", Vector3(point.x, 0.012, point.y), Vector2(-side, 0), 1.0)
			var bags := point + Vector2(0, 1.5)
			if _roll(key + "bags") < 0.6 and bags.distance_to(SEWER_ACCESS) >= SEWER_CLEARANCE and not _inside_building(context, bags, 0.4):
				_add(batches, "trash_bags", Vector3(bags.x, 0.012, bags.y), Vector2(-side, 0.3))
			_push(batches, "decal:grime", Transform3D(Basis.IDENTITY.scaled(Vector3(3.2, 1, 3.6)), Vector3(point.x, DECAL_Y + 0.001, point.y + 0.4)))


static func _push(batches: Dictionary, kind: String, transform: Transform3D) -> void:
	if not batches.has(kind): batches[kind] = []
	batches[kind].append(transform)


# ---------------------------------------------------------------------------
# 3. Desgaste do asfalto: manchas de óleo no meio da faixa, remendos, tampas
# de bueiro e bocas de lobo junto ao meio-fio.

static func _road_wear(context: Dictionary, batches: Dictionary) -> void:
	# The police sewer owns a dedicated interactive hatch at this exact spot.
	# Keep generic road lids clear so they cannot overlap the authored access.
	for road in context.roads:
		var points: PackedVector2Array = road.points
		var width: float = road.width
		var travelled := 0.0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var tangent := (b - a) / length
			var normal := Vector2(tangent.y, -tangent.x)
			var yaw := atan2(tangent.x, tangent.y)
			var s := fposmod(-travelled, 3.0)
			while s < length:
				var key := "%s|w|%d|%d" % [road.id, index, int(s * 10.0)]
				var roll := _roll(key)
				var along := a + tangent * s
				var lane := (1.0 if _roll(key + "l") < 0.5 else -1.0) * width * 0.25
				if roll < 0.22:
					# Óleo pinga no meio da faixa, onde o carro para.
					var p := along + normal * (lane + (_roll(key + "o") - 0.5) * 0.6)
					if _in_chunk(context, p) and not _near_junction(context, p, 1.0):
						var size := 0.7 + _roll(key + "s") * 1.1
						_push(batches, "decal:oil", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, 1, size * 1.5)), Vector3(p.x, DECAL_Y, p.y)))
				elif roll < 0.29:
					var p := along + normal * (_roll(key + "p") - 0.5) * width * 0.6
					if _in_chunk(context, p) and not _near_junction(context, p, 0.0):
						var w := 1.6 + _roll(key + "pw") * 2.4
						var h := 1.2 + _roll(key + "ph") * 3.0
						_push(batches, "decal:patch", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, 1, h)), Vector3(p.x, DECAL_Y - 0.002, p.y)))
				elif roll < 0.34:
					var p := along + normal * (_roll(key + "c") - 0.5) * width * 0.7
					if _in_chunk(context, p):
						var size := 2.5 + _roll(key + "cs") * 3.5
						_push(batches, "decal:crack", Transform3D(Basis(Vector3.UP, yaw + _roll(key + "cr") * TAU).scaled(Vector3(size, 1, size)), Vector3(p.x, DECAL_Y + 0.001, p.y)))
				elif roll < 0.355:
					var p := along + normal * lane * 0.2
					if _in_chunk(context, p) and not _near_junction(context, p, 0.0) and p.distance_to(SEWER_ACCESS) > 1.35:
						_add(batches, "manhole", Vector3(p.x, 0.028, p.y), tangent)
				elif roll < 0.38:
					var side := 1.0 if _roll(key + "d") < 0.5 else -1.0
					var p := along + normal * side * (width * 0.5 - 0.25)
					if _in_chunk(context, p) and not _near_junction(context, p, 0.0):
						_add(batches, "drain", Vector3(p.x, 0.028, p.y), tangent)
				elif roll < 0.46:
					# Sujeira/chiclete na calçada.
					var side := 1.0 if _roll(key + "g") < 0.5 else -1.0
					var p := along + normal * side * (width * 0.5 + 0.4 + _roll(key + "gd") * (SIDEWALK - 0.8))
					if _in_chunk(context, p) and not _inside_building(context, p, 0.0):
						var size := 0.5 + _roll(key + "gs") * 1.2
						_push(batches, "decal:grime", Transform3D(Basis.IDENTITY.scaled(Vector3(size, 1, size)), Vector3(p.x, DECAL_Y, p.y)))
				s += 3.0
			travelled += length


static func _decal_spec(kind: String) -> Dictionary:
	match kind:
		"contact":
			return {"material": MATERIALS.ground_decal("contact", _soft_rect_texture(), Color(0.02, 0.03, 0.04, 0.62))}
		"contact_tight":
			return {"material": MATERIALS.ground_decal("contact_tight", _soft_rect_texture(0.55), Color(0.01, 0.015, 0.02, 0.55))}
		"oil":
			return {"material": MATERIALS.ground_decal("oil", MATERIALS.alpha_blob("oil", 0.15), Color(0.02, 0.02, 0.025, 0.42))}
		"patch":
			return {"material": MATERIALS.ground_decal("patch", _soft_rect_texture(0.18), Color(0.05, 0.06, 0.07, 0.38))}
		"crack":
			return {"material": MATERIALS.ground_decal("crack", _crack_texture(), Color(0.03, 0.03, 0.035, 0.75))}
		"grime":
			return {"material": MATERIALS.ground_decal("grime", MATERIALS.alpha_blob("grime", 0.0), Color(0.12, 0.10, 0.07, 0.3))}
		"roof_tar":
			return {"material": MATERIALS.ground_decal("roof_tar", _soft_rect_texture(0.08), Color(0.06, 0.06, 0.07, 0.45))}
	if kind.begins_with("roof_"):
		var index := kind.trim_prefix("roof_").to_int()
		return {"material": MATERIALS.ground_decal(kind, _soft_rect_texture(0.03), ROOF_TINTS[index])}
	return {"material": MATERIALS.flat(Color.MAGENTA)}


static var _textures := {}


## Retângulo de borda suave: sombra de contato (prédio) e remendo de asfalto.
## edge = fração da meia largura usada para o degradê.
static func _soft_rect_texture(edge := 0.42) -> ImageTexture:
	var key := "rect_%.2f" % edge
	if _textures.has(key): return _textures[key]
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := absf((x + 0.5) / size * 2.0 - 1.0)
			var v := absf((y + 0.5) / size * 2.0 - 1.0)
			var d := maxf(u, v)
			var alpha := 1.0 - smoothstep(1.0 - edge, 1.0, d)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Rachaduras: três passeios aleatórios a partir do centro (determinístico).
static func _crack_texture() -> ImageTexture:
	if _textures.has("crack"): return _textures["crack"]
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90221
	for branch in 5:
		var p := Vector2(size * 0.5, size * 0.5)
		var heading := rng.randf() * TAU
		for step in 70:
			heading += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(heading), sin(heading)) * 0.9
			if p.x < 1 or p.y < 1 or p.x > size - 2 or p.y > size - 2: break
			var fade := 1.0 - step / 70.0
			image.set_pixelv(Vector2i(p), Color(1, 1, 1, fade))
			if step < 30: image.set_pixelv(Vector2i(p) + Vector2i(1, 0), Color(1, 1, 1, fade * 0.6))
	var texture := ImageTexture.create_from_image(image)
	_textures["crack"] = texture
	return texture


# ---------------------------------------------------------------------------
# 4. Telhados: variação de cor da laje, ar-condicionado, respiros, antenas,
# parabólicas, alçapões e outdoors virados para a câmera.

const ROOF_TINTS := [
	Color(0.10, 0.10, 0.11, 0.35), Color(0.45, 0.30, 0.24, 0.28), Color(0.62, 0.62, 0.58, 0.30),
	Color(0.26, 0.33, 0.29, 0.30), Color(0.20, 0.22, 0.28, 0.32), Color(0.55, 0.47, 0.36, 0.26),
]
const ROOF_PROPS := [["ac_unit", 0.2], ["vent", 0.14], ["roof_hatch", 0.06], ["antenna", 0.06], ["dish", 0.07], ["pipe_run", 0.06], ["roof_shed", 0.06], ["roof_garden", 0.06], ["roof_chairs", 0.04], ["water_tank", 0.06], ["skylight", 0.07], ["solar_row", 0.05], ["cooling_tower", 0.04]]


static func _rooftops(chunk: Node3D, context: Dictionary, batches: Dictionary) -> void:
	_other_roofs(chunk, batches)
	var billboards := 0
	for node in chunk.find_children("*", "Node3D", true, false):
		if not node is UrbanBuildingBase: continue
		var building: UrbanBuildingBase = node
		var key := building.building_id
		# A laje real (maior caixa horizontal mais alta do prédio) manda na
		# altura e no tamanho: altura nominal de UrbanBuildingBase não bate
		# com arquétipo que monta platibanda/penthouse próprio, e o tom de laje
		# ficava flutuando sobre a rua.
		var slabs := _roof_slabs(building)
		if slabs.is_empty(): continue
		var main_roof: AABB = slabs[0]
		var main_occupied := []
		for slab_index in slabs.size():
			var roof: AABB = slabs[slab_index]
			var unit_key := key if slab_index == 0 else "%s|u%d" % [key, slab_index]
			var roof_y := roof.end.y + 0.012
			var roof_center := Vector2(roof.get_center().x, roof.get_center().z)
			var size := Vector2(roof.size.x, roof.size.z)
			if size.x < 2.8 or size.y < 2.8: continue
			var xform := building.global_transform
			var occupied := _roof_obstacles(building, roof_y)
			# Delegacia antes dos adereços genéricos: heliponto e torre pedem espaço.
			if key == "Police" and slab_index == 0: POLICE.decorate(chunk, building, roof_y, roof_center, size, occupied, batches)
			# Acabamento da laje: textura de verdade (manta, brita, placas, zinco...)
			# por tipo de prédio, sem tocar no material compartilhado da fábrica.
			var surface := ROOFS.pick(building.building_kind, _roll(unit_key + "tint"))
			var inset := size - Vector2.ONE * 0.7
			_push(batches, "roofmat:%d" % surface, xform * Transform3D(Basis.IDENTITY.scaled(Vector3(inset.x, 1, inset.y)), Vector3(roof_center.x, roof_y, roof_center.y)))
			for patch in 2:
				if _roll(unit_key + "tar%d" % patch) < 0.5: continue
				var px := (_roll(unit_key + "tx%d" % patch) - 0.5) * (size.x - 2.5)
				var pz := (_roll(unit_key + "tz%d" % patch) - 0.5) * (size.y - 2.5)
				var ps := Vector3(1.5 + _roll(unit_key + "tw%d" % patch) * 3.0, 1, 1.2 + _roll(unit_key + "th%d" % patch) * 2.5)
				_push(batches, "decal:roof_tar", xform * Transform3D(Basis.IDENTITY.scaled(ps), Vector3(roof_center.x + px, roof_y + 0.004, roof_center.y + pz)))
			# Laje é o que mais aparece nesta câmera: mais ocupação que o comum.
			var wanted := clampi(int(size.x * size.y / 18.0), 2, 10)
			var placed := 0
			for attempt in wanted * 4:
				if placed >= wanted: break
				var akey := unit_key + "|roof|" + str(attempt)
				var kind := _pick(ROOF_PROPS, _roll(akey) * 1.0)
				if kind.is_empty(): continue
				var radius := 0.9 if kind in ["ac_unit", "roof_hatch"] else 0.5
				if kind == "pipe_run": radius = 2.2
				if kind in ["roof_shed", "roof_garden"]: radius = 1.6
				if kind == "roof_chairs": radius = 0.9
				if kind in ["water_tank", "cooling_tower"]: radius = 1.4
				if kind == "solar_row": radius = 2.1
				if kind == "skylight": radius = 1.0
				# Laje estreita (unidade de casa geminada): peça que não cabe fica de fora.
				if size.x < radius * 2.0 + 0.8 or size.y < radius * 2.0 + 0.8: continue
				var local := roof_center + Vector2((_roll(akey + "x") - 0.5) * (size.x - 2.0 * radius - 0.6), (_roll(akey + "z") - 0.5) * (size.y - 2.0 * radius - 0.6))
				var blocked := false
				for other in occupied:
					if local.distance_to(other.point) < radius + other.radius: blocked = true; break
				if blocked: continue
				occupied.append({"point": local, "radius": radius})
				var yaw := floorf(_roll(akey + "r") * 4.0) * PI * 0.5
				_push(batches, kind, xform * Transform3D(Basis(Vector3.UP, yaw), Vector3(local.x, roof_y, local.y)))
				placed += 1
			if slab_index == 0: main_occupied = occupied
		var roof_y := main_roof.end.y + 0.012
		var roof_center := Vector2(main_roof.get_center().x, main_roof.get_center().z)
		var size := Vector2(main_roof.size.x, main_roof.size.z)
		var occupied := main_occupied
		var has_billboard := false
		# These accessible storefronts identify themselves by their proper names;
		# a random fuel-brand slogan above Union misidentifies the clothing shop.
		if key not in ["NorthFrontage3", "NorthFrontage4"] and billboards < 2 and size.x >= 7.5 and roof_y >= 4.4 and _roll(key + "billboard") < 0.34:
			has_billboard = _place_billboard(chunk, building, roof_y, roof_center, size, occupied, batches)
			if has_billboard: billboards += 1
		# Fachada e telhado "vivos" (escada de incêndio, ar-condicionado, varal...).
		LIFE.decorate(chunk, building, roof_y, roof_center, size, occupied, batches, has_billboard)


## Lajes do prédio: a laje única do arquétipo ou, nas casas geminadas (cada
## unidade é um volume próprio, nenhum cobre 60% da planta), o topo de cada
## unidade. Sem isto os telhados dessas fileiras ficavam de cor chapada.
static func _roof_slabs(building: UrbanBuildingBase) -> Array:
	var single := _roof_box(building)
	if single.size != Vector3.ZERO: return [single]
	var result := []
	var inverse := building.global_transform.affine_inverse()
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh is BoxMesh: continue
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.x < 2.8 or box.size.z < 2.8 or box.size.y < 2.5 or box.position.y > 0.5: continue
		result.append(box)
	# A laje visível é a caixa mais alta sobre cada unidade (a fábrica põe uma
	# placa de cor por cima do volume); o acabamento vai acima dela.
	for index in result.size():
		var unit: AABB = result[index]
		for node in building.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box := inverse * (mesh.global_transform * mesh.get_aabb())
			if box.size.x < unit.size.x * 0.5 or box.size.z < unit.size.z * 0.5: continue
			if not unit.grow(0.3).has_point(box.get_center()) and not Rect2(unit.position.x - 0.3, unit.position.z - 0.3, unit.size.x + 0.6, unit.size.z + 0.6).has_point(Vector2(box.get_center().x, box.get_center().z)): continue
			if box.end.y > unit.end.y and box.end.y < unit.end.y + 0.6:
				unit.size.y = box.end.y - unit.position.y
		result[index] = unit
	result.sort_custom(func(a, b): return a.size.x * a.size.z > b.size.x * b.size.z)
	return result


## Maior caixa horizontal (>=60% da planta nos dois eixos) mais alta, em
## coordenadas locais do prédio. AABB vazio se o arquétipo não tem laje plana.
static func _roof_box(building: UrbanBuildingBase) -> AABB:
	var best := AABB()
	var inverse := building.global_transform.affine_inverse()
	var footprint: Vector2 = building.building_size
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.size.x < footprint.x * 0.6 or box.size.z < footprint.y * 0.6: continue
		if box.size.x > footprint.x * 1.3 or box.size.z > footprint.y * 1.3: continue
		if best.size == Vector3.ZERO or box.end.y > best.end.y: best = box
	return best


## Tudo que já está em cima da laje (caixa d'água, claraboia, chaminé) vira
## obstáculo em coordenadas locais do prédio, para o adereço novo não
## atravessar o existente.
static func _roof_obstacles(building: UrbanBuildingBase, roof_y: float) -> Array:
	var result := []
	var inverse := building.global_transform.affine_inverse()
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := inverse * (mesh.global_transform * mesh.get_aabb())
		if box.end.y < roof_y + 0.08 or box.position.y > roof_y + 6.0: continue
		if box.size.x > building.building_size.x * 0.8 and box.size.z > building.building_size.y * 0.8: continue
		if box.size.x > building.building_size.x * 0.9 or box.size.z > building.building_size.y * 0.9: continue
		var center := box.get_center()
		result.append({"point": Vector2(center.x, center.z), "radius": maxf(box.size.x, box.size.z) * 0.5 + 0.2})
	return result


## Outdoor no telhado encostado na borda sul, virado para a câmera (+Z
## global). É a única face que a câmera fixa vê de frente.
static func _place_billboard(chunk: Node3D, building: UrbanBuildingBase, roof_y: float, roof_center: Vector2, size: Vector2, occupied: Array, batches: Dictionary) -> bool:
	var inverse_basis := building.global_transform.basis.inverse()
	var south_local := inverse_basis * Vector3(0, 0, 1)
	var facing := Vector2(south_local.x, south_local.z).normalized()
	# Só eixos: prédios da V1 são alinhados à grade.
	var along_z := absf(facing.y) > absf(facing.x)
	var half_depth := (size.y if along_z else size.x) * 0.5
	var edge := roof_center + facing * (half_depth - 1.2)
	for other in occupied:
		if edge.distance_to(other.point) < other.radius + 3.0: return false
	var yaw := atan2(facing.x, facing.y)
	var local := Transform3D(Basis(Vector3.UP, yaw), Vector3(edge.x, roof_y, edge.y))
	var world := building.global_transform * local
	_push(batches, "billboard_frame", world)
	var brand: Dictionary = BRANDS.pick(building.building_id)
	chunk.add_child(BRANDS.billboard_panel(brand, chunk.global_transform.affine_inverse() * world))
	return true



## Prédios montados fora dos arquétipos (hospital, residências, fachadas
## autorais): só o acabamento da laje, sem adereços (não sabemos o que há lá).
static func _other_roofs(chunk: Node3D, batches: Dictionary) -> void:
	for child in chunk.get_children():
		if not child is Node3D or child is UrbanBuildingBase or child is MultiMeshInstance3D: continue
		if child.find_children("*", "MeshInstance3D", true, false).size() < 3: continue
		var roof := ROOFS.find_roof(child)
		if roof.size == Vector3.ZERO or roof.end.y < 2.5: continue
		var surface := ROOFS.pick("", _roll(String(child.name) + "tint"))
		var inset := Vector2(roof.size.x, roof.size.z) - Vector2.ONE * 0.6
		if inset.x < 3.0 or inset.y < 3.0: continue
		_push(batches, "roofmat:%d" % surface, child.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(inset.x, 1, inset.y)), Vector3(roof.get_center().x, roof.end.y + 0.012, roof.get_center().z)))



## Paredes grandes de cor chapada (lojas, galpões, delegacia, Cobra...) ganham
## a mesma textura de alvenaria/reboco/concreto dos brownstones. Só troca
## material_override de caixa grande sem textura e sem emissão: vidro, letreiro,
## toldo e acabamento pequeno ficam como estão.
static func _texture_walls(chunk: Node3D) -> void:
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		if material == null or material.albedo_texture != null or material.emission_enabled: continue
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.metallic > 0.2: continue
		if not mesh.mesh is BoxMesh: continue
		var box := mesh.global_transform * mesh.get_aabb()
		# Parede: alta e larga; laje/chão (baixo) e poste (fino) não entram.
		if box.size.y < 2.5 or maxf(box.size.x, box.size.z) < 3.0: continue
		if not _inside_building_node(mesh): continue
		mesh.material_override = UrbanMaterials.textured_wall(material.albedo_color, material.roughness)


static func _inside_building_node(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is UrbanBuildingBase: return true
		parent = parent.get_parent()
	return false



## O piso das quadras é gerado com triângulos em sentido anti-horário vistos
## de cima: a câmera vê o VERSO, e o Godot inverte a normal do verso. O chão
## das quadras apontava para baixo — zero de sol, zero de sombra (medido: a
## máscara de contribuição do sol era preta em todo o piso de lajota/grama), e
## os prédios pareciam colados. Refaz a malha com a ordem dos triângulos
## invertida (a face da frente passa a olhar para cima); a malha corrigida é
## compartilhada por instância de malha original.
static var _ground_meshes := {}

static func _face_ground_up(chunk: Node3D) -> void:
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.mesh is ArrayMesh: continue
		var box := mesh.global_transform * mesh.get_aabb()
		if box.size.y > 0.4 or box.end.y > 0.3 or maxf(box.size.x, box.size.z) < 3.0: continue
		if not _faces_down(mesh.mesh): continue
		var key := mesh.mesh.get_instance_id()
		if not _ground_meshes.has(key): _ground_meshes[key] = _flipped(mesh.mesh)
		# A malha original fica (escondida): a colisão do piso é gerada dela
		# depois deste passo e precisa continuar igual à que os testes de via
		# conferem. Só o desenho usa a cópia invertida.
		var visual := MeshInstance3D.new()
		visual.name = String(mesh.name) + "_Lit"
		visual.mesh = _ground_meshes[key]
		visual.material_override = mesh.material_override
		visual.cast_shadow = mesh.cast_shadow
		visual.layers = mesh.layers
		mesh.add_sibling(visual)
		visual.transform = mesh.transform
		mesh.visible = false


static func _flipped(source: ArrayMesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			var flipped := PackedInt32Array(indices)
			for i in range(0, flipped.size() - 2, 3):
				var t := flipped[i + 1]
				flipped[i + 1] = flipped[i + 2]
				flipped[i + 2] = t
			arrays[Mesh.ARRAY_INDEX] = flipped
		else:
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				var data = arrays[channel]
				if data == null or data.size() == 0: continue
				var stride: int = data.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var copy = data.duplicate()
				for tri in range(0, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() - 2, 3):
					for k in stride:
						copy[(tri + 1) * stride + k] = data[(tri + 2) * stride + k]
						copy[(tri + 2) * stride + k] = data[(tri + 1) * stride + k]
				arrays[channel] = copy
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals != null and normals.size() > 0:
			var up := PackedVector3Array()
			up.resize(normals.size())
			up.fill(Vector3.UP)
			arrays[Mesh.ARRAY_NORMAL] = up
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result


static func _faces_down(array_mesh: ArrayMesh) -> bool:
	var arrays := array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var up := 0.0
	var count := 0
	var step := 3
	var total: int = indices.size() if indices != null and indices.size() > 0 else vertices.size()
	for i in range(0, mini(total, 90), step):
		var a: Vector3; var b: Vector3; var c: Vector3
		if indices != null and indices.size() > 0:
			a = vertices[indices[i]]; b = vertices[indices[i + 1]]; c = vertices[indices[i + 2]]
		else:
			a = vertices[i]; b = vertices[i + 1]; c = vertices[i + 2]
		# Frente no Godot = horário visto de fora: normal geométrica (b-a)x(c-a)
		# aponta para TRÁS da face da frente.
		up += (b - a).cross(c - a).y
		count += 1
	return count > 0 and up > 0.0
