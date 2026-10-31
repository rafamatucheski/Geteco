@tool
extends RefCounted
class_name HarborUrbanSurface3D

## Partição do calçamento externo do Harbor, com canteiros plantados embutidos.
## Mantém os retângulos fonte estáveis para IDs do editor e reservas de acesso;
## reconstrói a união visível deles com acabamentos compartilhados adequados a cada quadra.

const SCALE := 1.0 / 16.0
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const PAVING := preload("res://world/urban_detail/HarborPaving.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const CATALOG :=preload("res://world/places/PlaceCatalog.gd")
const GARDEN_EDGE := 0.18

var _surfaces: Array[Dictionary] = []
var _visible_surfaces: Array[Dictionary] = []
var _materials: Dictionary = {}
var _access_points := PackedVector2Array()

## Áreas onde uma laje elevada posta à mão em outro lugar (HarborRouteDetail3D) ficava
## em cima deste preenchimento plano de lote, produzindo uma calçada dupla visível. Essa laje foi removida
## em favor de mostrar este calçamento plano diretamente, então esta lista está vazia de propósito
## de novo; fica como o gancho a usar se uma zona futura precisar de uma plataforma elevada real (um degrau
## de meio-fio, não uma laje de largura total, é a ferramenta certa para um rebaixo de garagem).
const _RAISED_APRON_HOLES: Array[Rect2] = []


func configure(compose_visible := true) -> void:
	_surfaces.clear()
	_access_points.clear()
	_add_westgate()
	_add_east()
	_add_north()
	# Quem chama o catálogo só lê os retângulos autorados. Compor a união visível
	# aqui repetia a mesclagem cara a cada validação de calçamento.
	if compose_visible: _compose_visible_surfaces()


## A V1 pinta retângulos posteriores sobre os anteriores. Em 3D essas faces não podem
## coexistir na mesma profundidade: mantém só as partes expostas de cada acabamento.
## Compõe uma vez, antes do streaming; mantém os UVs originais do mundo e a altura do piso.
func _compose_visible_surfaces() -> void:
	_visible_surfaces.clear()
	for i in _surfaces.size():
		var pieces: Array[Rect2] = [_surfaces[i].rect]
		for j in range(i+1,_surfaces.size()):
			var next: Array[Rect2] = []
			for piece in pieces:
				var overlap := piece.intersection(_surfaces[j].rect)
				if not overlap.has_area():
					next.append(piece)
					continue
				if overlap.position.y > piece.position.y:
					next.append(Rect2(piece.position.x,piece.position.y,piece.size.x,overlap.position.y-piece.position.y))
				if overlap.end.y < piece.end.y:
					next.append(Rect2(piece.position.x,overlap.end.y,piece.size.x,piece.end.y-overlap.end.y))
				if overlap.position.x > piece.position.x:
					next.append(Rect2(piece.position.x,overlap.position.y,overlap.position.x-piece.position.x,overlap.size.y))
				if overlap.end.x < piece.end.x:
					next.append(Rect2(overlap.end.x,overlap.position.y,piece.end.x-overlap.end.x,overlap.size.y))
			pieces=next
			if pieces.is_empty(): break
		for piece in pieces:
			var kind := String(_surfaces[i].kind)
			if kind == "grass":
				# O arremate pertence ao perímetro original do jardim, nunca a
				# peças arbitrárias introduzidas por ruas, caminhos de acesso ou streaming.
				var inner := (_surfaces[i].rect as Rect2).grow(-GARDEN_EDGE)
				var lawn := piece.intersection(inner)
				if lawn.has_area():
					_visible_surfaces.append({"rect":lawn,"kind":"grass","color":Color("566848"),"garden":_surfaces[i].get("boundary",_surfaces[i].rect),"neighbour":_surfaces[i].get("neighbour","concrete")})
				for border in _rect_difference(piece,inner):
					_visible_surfaces.append({"rect":border,"kind":"edging","color":PAVING.EDGE_COLOR,"garden":_surfaces[i].get("boundary",_surfaces[i].rect),"neighbour":_surfaces[i].get("neighbour","concrete")})
			else:
				# Aposenta os tons de manchas autorados, mantendo funcionais as recolorações novas
				# deliberadas do editor. Edições salvas antigas com o tom fonte migram.
				var family := String(_surfaces[i].get("finish", "concrete"))
				var finish: Color = PAVING.FINISH_COLORS[family] if _surfaces[i].color == _surfaces[i].get("authored_color",_surfaces[i].color) else _surfaces[i].color
				_visible_surfaces.append({"rect":piece,"kind":family,"color":finish,"court":_surfaces[i].get("boundary",_surfaces[i].rect) if family != "concrete" else Rect2(),"neighbour":_surfaces[i].get("neighbour","concrete")})
	_merge_neighbours()


func _rect_difference(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap := rect.intersection(cut)
	if not overlap.has_area(): return [rect]
	var result: Array[Rect2] = []
	if overlap.position.y > rect.position.y: result.append(Rect2(rect.position,Vector2(rect.size.x,overlap.position.y-rect.position.y)))
	if overlap.end.y < rect.end.y: result.append(Rect2(rect.position.x,overlap.end.y,rect.size.x,rect.end.y-overlap.end.y))
	if overlap.position.x > rect.position.x: result.append(Rect2(rect.position.x,overlap.position.y,overlap.position.x-rect.position.x,overlap.size.y))
	if overlap.end.x < rect.end.x: result.append(Rect2(overlap.end.x,overlap.position.y,rect.end.x-overlap.end.x,overlap.size.y))
	return result


## Dissolve emendas obsoletas de acesso/lote antes de montar as malhas. Retângulos vizinhos
## só são mesclados quando a união é retangular, preservando todas as aberturas reais.
func _merge_neighbours() -> void:
	# Grupos de acabamento/quadra/jardim diferentes não podem se mesclar nem influenciar um ao outro.
	# Mantém a mesma regra do primeiro par dentro de cada grupo, sem reiniciar varreduras de
	# todo retângulo sem relação nem deslocar o array inteiro depois de cada mesclagem.
	var groups := {}
	for i in _visible_surfaces.size():
		var source: Dictionary = _visible_surfaces[i]
		var key: Array = [source.kind,source.color,source.get("court",Rect2()),source.get("garden",Rect2())]
		if not groups.has(key): groups[key] = []
		groups[key].append(i)
	var alive := PackedByteArray()
	alive.resize(_visible_surfaces.size())
	alive.fill(1)
	for indices: Array in groups.values():
		var changed := true
		while changed:
			changed = false
			for position in indices.size():
				var i: int = indices[position]
				if not alive[i]: continue
				for next in range(position+1,indices.size()):
					var j: int = indices[next]
					if not alive[j]: continue
					var a: Rect2 = _visible_surfaces[i].rect
					var b: Rect2 = _visible_surfaces[j].rect
					var horizontal := is_equal_approx(a.position.y,b.position.y) and is_equal_approx(a.size.y,b.size.y) and (is_equal_approx(a.end.x,b.position.x) or is_equal_approx(b.end.x,a.position.x))
					var vertical := is_equal_approx(a.position.x,b.position.x) and is_equal_approx(a.size.x,b.size.x) and (is_equal_approx(a.end.y,b.position.y) or is_equal_approx(b.end.y,a.position.y))
					if not horizontal and not vertical: continue
					_visible_surfaces[i].rect = a.merge(b)
					alive[j] = 0
					changed = true
					break
				if changed: break
	var merged: Array[Dictionary] = []
	for i in _visible_surfaces.size():
		if alive[i]: merged.append(_visible_surfaces[i])
	_visible_surfaces = merged


## `cover`: contorno das ruas do chunk (HarborRoadGeometry3D.chunk_cover); o lote não fica por baixo da rua.
func build_chunk(parent: Node3D, rect: Rect2, cover: Array[PackedVector2Array] = []) -> Array[Rect2]:
	# O cover regional ja exclui a ponte; seus lotes antigos nao podem voltar
	# por baixo do asfalto. Ownership exato independe do diagnostico GROUND_STACK.
	var bridge_kit = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	var bridge_cuts: Array[PackedVector2Array] = []
	if bridge_kit.enabled():
		if rect.intersects(bridge_kit.east_bounds(),true): bridge_cuts.append(bridge_kit.east_footprint())
		if rect.intersects(Rect2(328.75,-374.25,36.55,126.0),true): bridge_cuts.append(bridge_kit.north_footprint())
	var exposed: Array[Rect2] = []
	var grouped: Dictionary = {}
	for source in _visible_surfaces:
		var clipped := (source.rect as Rect2).intersection(rect)
		if not clipped.has_area(): continue
		for part in _rounded_parts(source,clipped):
			if not bridge_cuts.is_empty():
				var polygons: Array[PackedVector2Array] = []
				polygons.assign(part.polygons)
				part.polygons = GROUND_CUT.subtract_exact(polygons,bridge_cuts)
			var key := "%s|%s" % [part.kind, (part.color as Color).to_html()]
			if not grouped.has(key):
				grouped[key] = {"kind":part.kind,"color":part.color,"polygons":[]}
			grouped[key].polygons.append_array(part.polygons)
		exposed.append(clipped)
	for key in grouped:
		_add_group(parent, grouped[key], cover)
	return exposed


## Arredonda o perímetro autorado no espaço do mundo, nunca o retângulo de streaming.
## O complemento exato substitui a antiga esquina viva por calçamento vizinho.
## Todas as partes dividem a altura original e ainda são cortadas pela cobertura de rua/prédio.
func _rounded_parts(source: Dictionary, clipped: Rect2) -> Array[Dictionary]:
	var subject: Array[PackedVector2Array] = [GROUND_CUT.rect_polygon(clipped)]
	var garden: Rect2 = source.get("garden",Rect2())
	var court: Rect2 = source.get("court",Rect2())
	var boundary := garden if garden.has_area() else court
	if not boundary.has_area() or boundary.get_area() > 5000.0 or minf(boundary.size.x,boundary.size.y) < 2.0:
		return [{"kind":source.kind,"color":source.color,"polygons":subject}]
	var radius := minf(2.2,minf(boundary.size.x,boundary.size.y)*.22)
	var outer := _round_outline(boundary,radius)
	var inside: Array[PackedVector2Array] = []
	inside.assign(Geometry2D.intersect_polygons(subject[0],outer))
	var result: Array[Dictionary] = []
	var remainder := GROUND_CUT.subtract_exact(subject,[outer])
	var neighbour := String(source.get("neighbour","concrete"))
	if garden.has_area():
		var inner := _round_outline(garden.grow(-GARDEN_EDGE),maxf(.05,radius-GARDEN_EDGE))
		var grass: Array[PackedVector2Array] = []
		for polygon in inside: grass.append_array(Geometry2D.intersect_polygons(polygon,inner))
		result.append({"kind":"grass","color":Color("566848"),"polygons":grass})
		result.append({"kind":"edging","color":PAVING.EDGE_COLOR,"polygons":GROUND_CUT.subtract_exact(inside,[inner])})
	else:
		result.append({"kind":source.kind,"color":source.color,"polygons":inside})
	result.append({"kind":neighbour,"color":PAVING.FINISH_COLORS[neighbour],"polygons":remainder})
	return result


func _round_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [rect.position+Vector2(radius,radius),Vector2(rect.end.x-radius,rect.position.y+radius),rect.end-Vector2(radius,radius),Vector2(rect.position.x+radius,rect.end.y-radius)]
	for corner in 4:
		for step in 7:
			var angle := PI+float(corner)*PI*.5+float(step)*PI/12.0
			points.append(centers[corner]+Vector2(cos(angle),sin(angle))*radius)
	return GROUND_CUT.counter_clockwise(points)


func source_access_points() -> PackedVector2Array:
	return _access_points.duplicate()


func _add_westgate() -> void:
	_add(Rect2(-100,-100,3300,2580), "stone", Color("8f8b7c"))
	for x in [510.0,1410.0,2310.0]:
		var width := 680.0 if x < 2000.0 else 580.0
		_add(Rect2(x,510,width,630), "concrete", Color("a69f8c"))
		_add(Rect2(x,1360,width,730), "concrete", Color("a69f8c"))
	_add(Rect2(1440,790,620,345), "stone", Color("b7ad96"))
	_add(Rect2(1440,1740,620,330), "concrete", Color("aaa9a1"))
	_add(Rect2(1440,1910,620,65), "concrete", Color("aaa9a1"))
	_add(Rect2(1515,1660,70,475), "concrete", Color("aaa9a1"))
	_add(Rect2(520,755,450,100), "stone", Color("b5ad9a"))
	_add(Rect2(545,770,220,70), "grass", Color("445d4b"))
	_add(Rect2(726,520,24,235), "concrete", Color("a8a18e"))
	_add(Rect2(766,855,404,105), "concrete", Color("5c605f"))
	_add(Rect2(516,1120,210,28), "brick", Color("a97155"))
	for access in _westgate_accesses():
		_add_access(access.rect, "concrete", Color("676e70") if access.vehicle else Color("aaa9a1"))


func _westgate_accesses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rect in [
		Rect2(620,1620,160,98),Rect2(640,1718,140,482),Rect2(899,1718,80,372),
		Rect2(2041,1690,84,270),Rect2(904,1990,70,100),Rect2(2450,850,310,400),
		Rect2(1930,1533,215,74),Rect2(1930,1418,215,74),Rect2(2375,2060,390,140),
	]: result.append({"rect":rect,"vehicle":true})
	for rect in [
		Rect2(985,2075,190,65),Rect2(1820,775,50,45),Rect2(1750,1645,100,120),
		Rect2(2365,1250,100,175),Rect2(590,1120,62,28),Rect2(815,1120,60,28),
		Rect2(1035,1120,60,28),Rect2(1520,1645,60,95),Rect2(730,860,26,270),
	]: result.append({"rect":rect,"vehicle":false})
	for x in [650.0,990.0,1550.0,1890.0,2460.0,2780.0]:
		result.append({"rect":Rect2(x-25,230,50,170),"vehicle":false})
	return result


func _add_east() -> void:
	_add(Rect2(4380,-100,2380,2700), "stone", Color("a19d8c"))
	for x in [4780.0,5680.0]:
		_add(Rect2(x,530,640,600), "stone", Color("b5ac95"))
		_add(Rect2(x,1380,640,710), "stone", Color("b5ac95"))
	_add(Rect2(4810,1655,600,150), "grass", Color("6c8067"))
	_add(Rect2(4810,1711,600,32), "stone", Color("c5bca3"))
	_add(Rect2(5695,1740,625,340), "grass", Color("819383"))
	_add(Rect2(4440,2335,2260,170), "stone", Color("d0c4a7"))
	for x in [4830.0,5760.0,6270.0]: _add(Rect2(x,2200,60,305), "stone", Color("d0c4a7"))
	for rect in [
		Rect2(4970,880,60,120),Rect2(5275,800,60,200),Rect2(5820,825,70,425),
		Rect2(4765,1250,40,420),Rect2(4905,2075,50,125),Rect2(5245,2075,50,125),
		Rect2(6070,1685,60,515),Rect2(5760,1620,60,580),
	]: _add_access(rect,"stone",Color("d0c4a7"))
	for x in [4900.0,5290.0,5840.0,6200.0]: _add_access(Rect2(x-25,235,50,165),"stone",Color("d0c4a7"))


func _add_north() -> void:
	_add(Rect2(4380,-2400,2380,2300), "concrete", Color("999789"))
	# IDs históricos de "gravel" ficam no catálogo do editor. O passeio construído da
	# estação norte recebe o acabamento do cais durante a composição.
	_add(Rect2(5700,-4470,600,2120), "gravel", Color("82887d"))
	for x in [5708.0,6250.0]: _add(Rect2(x,-4430,42,2030),"gravel",Color("b0ac96"))
	_add(Rect2(5980,-4050,40,1650), "grass", Color("7d8b74"))
	_add(Rect2(4785,-2320,620,160), "stone", Color("b4ac96"))
	_add(Rect2(6335,-2320,240,160), "stone", Color("b4ac96"))
	for x in [4775.0,5675.0]:
		_add(Rect2(x,-1875,650,650),"concrete",Color("ada38e"))
		_add(Rect2(x,-975,650,510),"concrete",Color("b2a68f"))
	for x in [4800.0,5720.0]:
		_add(Rect2(x,-1550,590,65),"stone",Color("c3b69e"))
		_add(Rect2(x,-707,590,30),"stone",Color("c3b69e"))
	for x in [4780.0,5690.0]:
		_add(Rect2(x,-235,650,120),"grass",Color("75836b"))
		_add(Rect2(x,-155,650,35),"stone",Color("c6bba2"))
		_add(Rect2(x+290,-350,45,235),"stone",Color("c6bba2"))
	for access in _north_accesses():
		_add_access(access.rect,"concrete",Color("737a77") if access.vehicle else Color("c8bca3"))


func _north_accesses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rect in [Rect2(4790,-1255,270,155),Rect2(5725,-1260,310,160)]:
		result.append({"rect":rect,"vehicle":true})
	for rect in [
		Rect2(4650,-1619,265,50),Rect2(5260,-1619,290,50),Rect2(5240,-1255,50,155),
		Rect2(5550,-1629,310,50),Rect2(6200,-1629,250,50),Rect2(6175,-1260,50,160),
		Rect2(4650,-769,265,50),Rect2(5260,-769,290,50),Rect2(4890,-505,50,155),
		Rect2(5235,-505,50,155),Rect2(5550,-769,325,50),Rect2(6220,-769,230,50),
		Rect2(5845,-505,60,155),Rect2(6195,-505,50,155),
	]: result.append({"rect":rect,"vehicle":false})
	for x in [4925.0,5290.0,6485.0]:
		var front_y := -2152.0 if x < 6000.0 else -2122.0
		result.append({"rect":Rect2(x-24,front_y,48,-2082-front_y),"vehicle":false})
	return result


func _add(source_rect: Rect2, kind: String, color: Color) -> void:
	var neighbour := "concrete"
	for previous in _surfaces:
		if previous.kind != "grass" and (previous.rect as Rect2).has_point(source_rect.get_center()*SCALE): neighbour = String(previous.get("finish","concrete"))
	for piece in _carved(source_rect):
		_surfaces.append({"rect":Rect2(piece.position*SCALE,piece.size*SCALE),"kind":kind,"color":color,"authored_color":color,"finish":_finish_for_lot(source_rect,kind),"boundary":Rect2(source_rect.position*SCALE,source_rect.size*SCALE),"neighbour":neighbour})


## Escolhe o uso do lote autorado ANTES de esculpi-lo ou fazer streaming. O grande
## fundo continua uma calçada neutra; quadras individuais substituem as faces dele.
func _finish_for_lot(source: Rect2, kind: String) -> String:
	var rect := Rect2(source.position*SCALE, source.size*SCALE)
	if rect.get_area() > 5000.0: return "concrete"
	var center := rect.get_center()
	if kind == "brick": return "brick"
	if center.x < 200.0:
		if center.x > 140.0 or Rect2(47,53,28,8).has_point(center): return "service"
		if center.y < 72.0 and center.x < 76.0: return "brick"
		if center.x > 85.0: return "limestone"
	elif center.x > 270.0:
		if center.y > 135.0 or center.y < -150.0: return "quay"
		if center.y > 75.0 and center.x < 345.0: return "brick"
		if center.y > 0.0: return "limestone"
		if center.y > -70.0: return "brick"
		return "service"
	return "concrete"


## Divide source_rect em volta de qualquer buraco de pátio elevado que ele sobreponha, para o
## preenchimento plano do lote nunca desenhar sob uma laje elevada feita sob medida posta em outro lugar.
func _carved(source_rect: Rect2) -> Array[Rect2]:
	var pieces: Array[Rect2] = [source_rect]
	var openings: Array[Rect2] = _RAISED_APRON_HOLES.duplicate()
	openings.append_array(CATALOG.sewer_openings())
	var skate_rect := preload("res://activities/skate/SkateParkLayout.gd").FOOTPRINT
	if preload("res://activities/skate/SkateParkLayout.gd").enabled(): openings.append(Rect2(skate_rect.position / SCALE, skate_rect.size / SCALE))
	for hole in openings:
		var next: Array[Rect2] = []
		for piece in pieces:
			var overlap := piece.intersection(hole)
			if not overlap.has_area():
				next.append(piece)
				continue
			if overlap.position.y > piece.position.y:
				next.append(Rect2(piece.position.x, piece.position.y, piece.size.x, overlap.position.y - piece.position.y))
			if overlap.end.y < piece.end.y:
				next.append(Rect2(piece.position.x, overlap.end.y, piece.size.x, piece.end.y - overlap.end.y))
			if overlap.position.x > piece.position.x:
				next.append(Rect2(piece.position.x, overlap.position.y, overlap.position.x - piece.position.x, overlap.size.y))
			if overlap.end.x < piece.end.x:
				next.append(Rect2(overlap.end.x, overlap.position.y, piece.end.x - overlap.end.x, overlap.size.y))
		pieces = next
	return pieces


func _add_access(source_rect: Rect2, kind: String, color: Color) -> void:
	_add(source_rect, kind, color)
	_access_points.append(source_rect.get_center() * SCALE)


func _add_group(parent: Node3D, group: Dictionary, cover: Array[PackedVector2Array] = []) -> void:
	var pieces: Array[PackedVector2Array] = []
	pieces.assign(group.polygons)
	var mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract(pieces, cover), 0.008, 4.0)
	if mesh == null: return
	mesh.surface_set_material(0,_material(String(group.kind),group.color))
	var instance := MeshInstance3D.new()
	instance.name="HarborSurface_%s"%String(group.kind)
	instance.mesh=mesh
	# Isto é um acabamento de chão, não uma laje elevada. Recebe sombras de objetos sem
	# projetar sombras subpixel na rua e no terreno embaixo.
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _material(kind: String, color: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [kind,color.to_html()]
	if _materials.has(key): return _materials[key]
	if kind in PAVING.FINISH_COLORS or kind in ["stone","edging"]:
		_materials[key] = PAVING.material(color,kind if kind in PAVING.FINISH_COLORS else "concrete")
		return _materials[key]
	if kind == "grass":
		_materials[key] = PAVING.lawn_material(color)
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	# O mapa normal fonte amplifica as derivadas do albedo em seis vezes. Uma escala de
	# dois fazia os gramados do Harbor parecerem tecido dobrado na câmera do jogo.
	GROUND.bind(material,kind,.22 if kind == "grass" else .35)
	# Triplanar em mundo: o mesh não tem tangentes e normal map precisa delas no UV plano.
	material.uv1_triplanar=true
	material.uv1_world_triplanar=true
	# Grama com tile menor: a 16 m o grão ficava borrado da câmera alta.
	material.uv1_scale=Vector3.ONE/(3.0 if kind=="grass" else 16.0)
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness=.92
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_materials[key]=material
	return material
