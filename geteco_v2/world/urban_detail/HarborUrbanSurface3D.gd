extends RefCounted
class_name HarborUrbanSurface3D

## Source-authored Harbor lot and access paving projected into native 3D.
## Rectangles, tints and material kinds come from HarborDistrict,
## HarborEastDistrict and HarborNorthDistrict. No new lots are introduced.

const SCALE := 1.0 / 16.0
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")

var _surfaces: Array[Dictionary] = []
var _visible_surfaces: Array[Dictionary] = []
var _materials: Dictionary = {}
var _access_points := PackedVector2Array()

## Footprints where a hand-placed raised slab elsewhere (HarborRouteDetail3D) used to sit
## on top of this flat lot fill, producing a visible double sidewalk. That slab was removed
## in favor of just showing this flat paving directly, so this list is intentionally empty
## again; kept as the hook to use if a future zone ever needs a real raised platform (a curb
## step, not a full-width slab, is the right tool for a driveway cut instead).
const _RAISED_APRON_HOLES: Array[Rect2] = []


func configure() -> void:
	_surfaces.clear()
	_access_points.clear()
	_add_westgate()
	_add_east()
	_add_north()
	_compose_visible_surfaces()


## V1 paints later rectangles over earlier ones. In 3D those faces must not
## coexist at the same depth: retain only the exposed pieces of each finish.
## Compose once, before streaming; keep original world UVs and floor height.
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
			_visible_surfaces.append({"rect":piece,"kind":_surfaces[i].kind,"color":_surfaces[i].color})


func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var grouped: Dictionary = {}
	for source in _visible_surfaces:
		var clipped := (source.rect as Rect2).intersection(rect)
		if not clipped.has_area(): continue
		var key := "%s|%s" % [source.kind, (source.color as Color).to_html()]
		if not grouped.has(key):
			grouped[key] = {"kind": source.kind, "color": source.color, "rects": []}
		grouped[key].rects.append(clipped)
	for key in grouped:
		_add_group(parent, grouped[key])


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
	for piece in _carved(source_rect):
		_surfaces.append({"rect":Rect2(piece.position*SCALE,piece.size*SCALE),"kind":kind,"color":color})


## Splits source_rect around any raised-apron hole it overlaps, so the flat
## lot fill never draws under a purpose-built raised slab placed elsewhere.
func _carved(source_rect: Rect2) -> Array[Rect2]:
	var pieces: Array[Rect2] = [source_rect]
	var openings: Array[Rect2] = _RAISED_APRON_HOLES.duplicate()
	openings.append(CATALOG.HARBOR_SEWER_OPENING)
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


func _add_group(parent: Node3D, group: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for rect_value in group.rects:
		var rect := rect_value as Rect2
		var points := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for index in [0,2,1,0,3,2]:
			var point: Vector2 = points[index]
			vertices.append(Vector3(point.x,0.006,point.y))
			normals.append(Vector3.UP)
			uvs.append(point/16.0)
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material(String(group.kind),group.color))
	var instance := MeshInstance3D.new()
	instance.name="HarborSurface_%s"%String(group.kind)
	instance.mesh=mesh
	parent.add_child(instance)


func _material(kind: String, color: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [kind,color.to_html()]
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.albedo_texture=GROUND.texture(kind)
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness=.92
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_materials[key]=material
	return material
