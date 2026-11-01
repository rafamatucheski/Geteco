extends RefCounted
## Passo 1 (noite: luminárias autoradas, janelas acesas, manchas de luz) e passo 2 (postes novos
## de calçada) do acabamento do trecho, separados do CityChunkDressing em 01/11 (Onda 1).
## Roda na thread principal, uma vez por trecho no streaming, como antes.
## Tudo estático, como o dono. `g` é o script do CityChunkDressing (preload cíclico, o mesmo que
## SidewalkFill/StreetJunk já fazem): o que continua no dono (_roll, _pick, _add, _push, _in_chunk,
## _context, constantes de calçada e de poste, _lamp_meshes) é lido por `g.`; o dono mantém cada
## função antiga como delegação de uma linha com a mesma assinatura, então testes e
## SidewalkFill/StreetJunk/HarborUtilityLines que chamam pelo dono não mudam.

const g := preload("res://world/city_look/CityChunkDressing.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const KIT := preload("res://world/city_look/CityPropKit.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const PLACEMENTS := preload("res://world/editing/WorldPlacements.gd")
const UTILITY := preload("res://world/city_look/HarborUtilityLines.gd")
const WEAR := preload("res://world/city_look/HarborStreetWear.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")

static func _night_pass(chunk: Node3D, context: Dictionary) -> void:
	var lamp_roots := {}
	var pools := PackedVector3Array()
	var pool_sizes := PackedFloat32Array()
	var pool_heights := PackedFloat32Array()
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_inside_tree(): continue
		var lamp_height := _lamp_height(mesh)
		if lamp_height > 0.0:
			mesh.material_override = MATERIALS.lamp_head()
			var head := mesh.global_position
			pools.append(Vector3(head.x, head.y - lamp_height + 0.06, head.z))
			pool_sizes.append(clampf(lamp_height * 2.3, 6.0, 11.0))
			pool_heights.append(lamp_height)
			context.lamps.append(Vector2(head.x, head.z))
			var root := _lamp_root(mesh)
			if root != null and not lamp_roots.has(root): lamp_roots[root] = pools.size() - 1
			continue
		_treat_window(mesh)
	if not pools.is_empty():
		for index in pools.size(): pools[index] = chunk.to_local(pools[index])
		var pool_instance := _light_pools(pools, pool_sizes, pool_heights)
		chunk.add_child(pool_instance)
		# Poste que o carro derruba apaga a própria mancha de luz.
		for root in lamp_roots:
			FRAGILE.register_node("lamp", root, chunk, {"multimesh": pool_instance.multimesh, "index": lamp_roots[root]})


## Postes novos nas calçadas: haste+braço e cabeça em duas MultiMesh (a
## cabeça usa o material emissivo compartilhado que CityLook acende à noite),
## mais mancha de luz no chão como nos postes autorados. Nenhuma Light3D: o
## custo é o de cinco MultiMesh por chunk, incluindo gaiola/difusor do acabamento
## inspirado na arte do porto. O carro derruba o poste (FragileProps
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
			var s := fposmod(-travelled, g.LAMP_SPACING)
			step = int(round((travelled + s) / g.LAMP_SPACING))
			while s < length:
				var side := 1.0 if step % 2 == 0 else -1.0
				step += 1
				var outward: Vector2 = normal * side
				var point := a + tangent * s + outward * (width * 0.5 + 0.45)
				s += g.LAMP_SPACING
				if not g._in_chunk(context, point): continue
				# Margem cobre o poste do semáforo (setback ≈ 0.68·largura + 2,3 m, com o
				# braço de 3,3 m): com 2 m o poste de luz nascia colado no semáforo.
				if g._near_junction(context, point, 7.0) or g._near_lamp(context, point, g.LAMP_CLEARANCE): continue
				if g._road_clearance(context, point) < 0.2 or g._inside_building(context, point, 0.5): continue
				if WORLD_CONNECTION.reserves_approach_for_driving(point): continue
				if g._workshop_driving(point): continue
				if point.distance_to(g.SEWER_ACCESS) < g.SEWER_CLEARANCE: continue
				context.lamps.append(point)
				var yaw := atan2(-outward.x, -outward.y)
				transforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.012, point.y)))
			travelled += length
	if transforms.is_empty(): return
	transforms = PLACEMENTS.edit_lamps(context.region, chunk, transforms)
	if transforms.is_empty(): return
	var to_local := chunk.global_transform.affine_inverse()
	# Bairro de cada poste (rua mais próxima): tinta do lote e chance de adesivo/cartaz.
	var districts: Array[String] = []
	var tally := {}
	for placement in transforms:
		var district := WEAR.district_at(context.roads, Vector2(placement.origin.x, placement.origin.z))
		districts.append(district)
		tally[district] = int(tally.get(district, 0)) + 1
	var chunk_district := ""
	for district in tally:
		if chunk_district.is_empty() or int(tally[district]) > int(tally[chunk_district]): chunk_district = district
	var paint: Material = UTILITY.lamp_material(chunk_district) if UTILITY.enabled else MATERIALS.flat(Color("4a5054"), 0.6)
	var poles := _lamp_multimesh("pole", transforms.size())
	var heads := _lamp_multimesh("head", transforms.size())
	var lantern_frames := _lamp_multimesh("lantern_frame", transforms.size())
	var lantern_glass := _lamp_multimesh("lantern_glass", transforms.size())
	var pools := PackedVector3Array()
	var pool_sizes := PackedFloat32Array()
	var pool_heights := PackedFloat32Array()
	for index in transforms.size():
		var local := to_local * transforms[index]
		poles.set_instance_transform(index, local)
		heads.set_instance_transform(index, local)
		lantern_frames.set_instance_transform(index, local)
		lantern_glass.set_instance_transform(index, local)
		var head := local * Vector3(0, g.LAMP_HEIGHT, g.LAMP_ARM)
		pools.append(Vector3(head.x, local.origin.y + 0.05, head.z))
		pool_sizes.append(clampf(g.LAMP_HEIGHT * 2.3, 6.0, 11.0))
		pool_heights.append(g.LAMP_HEIGHT)
	var pole_instance := MultiMeshInstance3D.new()
	pole_instance.name = "CityLook_sidewalk_lamp"
	pole_instance.multimesh = poles
	pole_instance.material_override = paint
	chunk.add_child(pole_instance)
	var head_instance := MultiMeshInstance3D.new()
	head_instance.name = "CityLook_sidewalk_lamp_head"
	head_instance.multimesh = heads
	head_instance.material_override = MATERIALS.lamp_head()
	head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(head_instance)
	# Um pequeno difusor engaiolado fica abaixo da cobertura existente. Ao contrário
	# da face inferior plana, o vidro quente aparece na câmera elevada do jogo, como
	# na arte de abertura do porto/garagem, sem mais postes, poças de luz ou luzes reais.
	var frame_instance := MultiMeshInstance3D.new()
	frame_instance.name = "CityLook_street_lantern_frames"
	frame_instance.multimesh = lantern_frames
	frame_instance.material_override = paint
	frame_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(frame_instance)
	var glass_instance := MultiMeshInstance3D.new()
	glass_instance.name = "CityLook_street_lantern_diffusers"
	glass_instance.multimesh = lantern_glass
	# Material compartilhado de hora do dia: o vidro novo segue a mesma transição
	# gradual e a paleta branco-quente, sem um laço de atualização extra.
	glass_instance.material_override = MATERIALS.lamp_head()
	glass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(glass_instance)
	var pool_instance := _light_pools(pools, pool_sizes, pool_heights)
	pool_instance.name = "CitySidewalkLampPools"
	chunk.add_child(pool_instance)
	# Adesivo, lambe-lambe e pichação (atlas) em parte dos postes, conforme o bairro. A cópia gira
	# um pouco em volta da haste para não repetir o mesmo lado; vai como peça extra do poste.
	var wear_parts := {}
	if WEAR.available() and KIT.blender_props_enabled:
		var wear_transforms: Array = []
		var wear_owner: Array[int] = []
		for index in transforms.size():
			var key := "lamp|%d|%d" % [roundi(transforms[index].origin.x * 10.0), roundi(transforms[index].origin.z * 10.0)]
			if WEAR.roll(key) >= float(WEAR.WEAR_CHANCE.get(districts[index], 0.0)): continue
			var local := poles.get_instance_transform(index)
			wear_transforms.append(local * Transform3D(Basis(Vector3.UP, (WEAR.roll(key + "yaw") - .5) * 1.2), Vector3(0, (WEAR.roll(key + "y") - .5) * .24, 0)))
			wear_owner.append(index)
		if not wear_transforms.is_empty():
			var wear := WEAR.batch("CityLook_lamp_wear", WEAR.lamp_mesh(), wear_transforms)
			chunk.add_child(wear)
			for slot in wear_owner.size():
				var lamp_index := wear_owner[slot]
				wear_parts[lamp_index] = {"multimesh": wear.multimesh, "index": slot, "offset": poles.get_instance_transform(lamp_index).affine_inverse() * wear_transforms[slot]}
	for index in transforms.size():
		var base := poles.get_instance_transform(index)
		var extra: Array = [{"multimesh": heads, "index": index, "offset": Transform3D.IDENTITY},
			{"multimesh": lantern_frames, "index": index, "offset": Transform3D.IDENTITY},
			{"multimesh": lantern_glass, "index": index, "offset": Transform3D.IDENTITY}]
		if wear_parts.has(index): extra.append(wear_parts[index])
		# register_instance não recebe a mancha; o registro direto é o mesmo
		# formato, com "pool" como register_node usa para apagar a luz.
		FRAGILE._register({"kind": "lamp", "multimesh": poles, "index": index,
			"visual": weakref(pole_instance),
			"extra": extra,
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
	if g._lamp_meshes.has(part): return g._lamp_meshes[part]
	# Poste do Blender: a lente fica no mesmo lugar (a mancha de luz sai das constantes).
	if KIT.blender_props_enabled and part in ["pole", "head"]:
		g._lamp_meshes[part] = KIT.blender_mesh("sidewalk_lamp", "LampPole" if part == "pole" else "LampHead")
		return g._lamp_meshes[part]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if part == "pole":
		_lamp_box(tool, Vector3(0, 0.2, 0), Vector3(0.34, 0.4, 0.34))
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT * 0.5, 0), Vector3(0.13, g.LAMP_HEIGHT, 0.13))
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT - 0.05, g.LAMP_ARM * 0.5), Vector3(0.09, 0.09, g.LAMP_ARM))
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT + 0.03, g.LAMP_ARM + 0.02), Vector3(0.36, 0.1, 0.62))
	elif part == "head":
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT - 0.04, g.LAMP_ARM + 0.02), Vector3(0.3, 0.05, 0.54))
	elif part == "lantern_frame":
		# A cabeça em caixa existente é a cobertura de chuva. Uma grade discreta de
		# quatro hastes e uma bandeja inferior dão ao ponto de luz uma forma de porto industrial.
		var center_z := g.LAMP_ARM + .02
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT - .48, center_z), Vector3(.38, .055, .44))
		for x in [-.16, .16]:
			for z in [-.19, .19]:
				_lamp_box(tool, Vector3(x, g.LAMP_HEIGHT - .265, center_z + z), Vector3(.035, .43, .035))
		# A virola da base e os dois anéis do fuste são detalhes de metal aterrados, nunca
		# luzes decorativas. Eles preservam a silhueta/área existente.
		_lamp_box(tool, Vector3(0, .52, 0), Vector3(.19, .045, .19))
		_lamp_box(tool, Vector3(0, 1.06, 0), Vector3(.14, .05, .14))
		if UTILITY.enabled:
			# Detalhe de perto (29/10): chumbadores com porca na placa da base, portinhola de
			# inspeção na base do lado da calçada (-Z), relé fotoelétrico em cima da luminária e
			# a abraçadeira do braço. Mesma malha e material da gaiola: nenhum draw call novo.
			for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				_lamp_box(tool, Vector3(corner.x * .131, .075, corner.y * .131), Vector3(.034, .03, .034))
				_lamp_box(tool, Vector3(corner.x * .131, .098, corner.y * .131), Vector3(.012, .02, .012))
			_lamp_box(tool, Vector3(0, .25, -.158), Vector3(.1, .2, .014))
			_lamp_box(tool, Vector3(0, .25, -.166), Vector3(.018, .02, .006))
			_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT + .16, g.LAMP_ARM - .22), Vector3(.07, .05, .07))
			_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT + .2, g.LAMP_ARM - .22), Vector3(.05, .03, .05))
			_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT - .46, 0), Vector3(.13, .07, .13))
	elif part == "lantern_glass":
		_lamp_box(tool, Vector3(0, g.LAMP_HEIGHT - .26, g.LAMP_ARM + .02), Vector3(.25, .37, .29))
	tool.generate_normals()
	var mesh := tool.commit()
	g._lamp_meshes[part] = mesh
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
## chão. Postes da ponte ficam de fora (várias luminárias no mesmo nó; tombar um
## derrubaria a ponte inteira). Os da Cobra tinham o mesmo problema até 29/10;
## agora cada um tem raiz própria "HarborLampCobra_n" (HarborAreaDressing3D._lamp).
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
	elif material is StandardMaterial3D and (bool(mesh.get_meta("city_window", false)) or bool(material.get_meta("city_window", false)) or String(mesh.name).begins_with("WindowGlass")):
		# Casas autoradas e hospital usam vidro opaco, com material próprio.
		# Reconhecer o vidro explicitamente preserva caixilhos, portas e paredes.
		kind = "window"
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
		mesh.material_override = MATERIALS.shop_glass() if roll < g.SHOP_LIT_RATIO else material
		return
	if roll < g.WINDOW_LIT_RATIO:
		# ~1 em 7 acesas é TV: azul trêmulo à noite (CityLook anima).
		if roll < g.WINDOW_LIT_RATIO * 0.14: mesh.material_override = MATERIALS.window_tv()
		else: mesh.material_override = MATERIALS.window_lit(int(roll * 1000.0) % MATERIALS.WINDOW_TONES.size())
	else:
		# Apagada continua vidro, mas opaco (vidro transparente sobre caixa
		# escura custa uma passada transparente sem ganho visual). Variantes de
		# cortina/persiana tiram a cara de fileira idêntica de dia.
		var variant := int(_position_roll(mesh.global_position + Vector3(7.1, 0, 3.3)) * 10.0)
		mesh.material_override = MATERIALS.window_unlit(variant) if variant < MATERIALS.UNLIT_VARIANTS else MATERIALS.window_glass_dark()


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
	return g._roll("%d,%d,%d" % [roundi(point.x * 4.0), roundi(point.y * 4.0), roundi(point.z * 4.0)])


static func _light_pools(points: PackedVector3Array, sizes: PackedFloat32Array, heights: PackedFloat32Array = PackedFloat32Array()) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = g._flat_quad()
	multimesh.instance_count = points.size()
	for index in points.size():
		var basis := Basis.IDENTITY.scaled(Vector3(sizes[index], 1.0, sizes[index]))
		multimesh.set_instance_transform(index, Transform3D(basis, points[index]))
		multimesh.set_instance_custom_data(index,Color(heights[index] if index<heights.size() else sizes[index]/2.3,0,0,0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "CityLightPools"
	instance.multimesh = multimesh
	instance.material_override = MATERIALS.light_pool()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Os reflexos molhados aumentam a área horizontal existente em no máximo 30%.
	instance.extra_cull_margin = 2.0
	instance.visible = MATERIALS.night > 0.01
	instance.add_to_group(g.NIGHT_GROUP)
	return instance
