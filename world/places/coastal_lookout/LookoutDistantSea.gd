extends RefCounted
## Continuação só de panorama abaixo da água do Harbor em streaming. As fases de onda
## em coordenadas do mundo e a depressão da ponte batem com o mar existente, sem física.
const OCEAN = preload("res://world/regions/HarborOcean.gd")
const DESERT = preload("res://world/desert/DesertLayout.gd")
const CANAL = preload("res://world/urban_detail/CanalTunnel3D.gd")
const SKATE = preload("res://activities/skate/SkateParkLayout.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const EXTENT := 8192.0

static func build() -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var cuts: Array[Rect2] = [DESERT.BOUNDS, CANAL.WATER_CUT, Rect2(-413.25,85.35,6.10,3.30)]
	if SKATE.enabled(): cuts.append(SKATE.FOOTPRINT)
	for opening in PLACES.sewer_openings(): cuts.append(Rect2(opening.position/16.0,opening.size/16.0))
	# Um oceano completo se estende além do plano distante óptico em todas as direções.
	# As quatro fileiras norte antigas expunham uma borda artificial em z=-1024.
	# Ladrilhos distantes grosseiros preservam o período exato de UV de 256m do shader; só
	# a depressão local precisa de geometria densa, já que as ondas não deslocam vértices.
	for tile_z in range(-32,32):
		for tile_x in range(-32,32):
			var origin := Vector2(tile_x,tile_z)*256.0
			var tile := Rect2(origin,Vector2.ONE*256.0)
			var local_cuts: Array[Rect2] = []
			for cut in cuts:
				if cut.encloses(tile): local_cuts = [tile]; break
				if cut.intersects(tile): local_cuts.append(cut)
			if local_cuts.size()==1 and local_cuts[0]==tile: continue
			var distance := tile.get_center().distance_to(Vector2(303,-198))
			var subdivisions := 16 if distance<1100.0 else 4 if distance<2200.0 else 1
			var stride := 256.0/float(subdivisions)
			for z in subdivisions:
				for x in subdivisions:
					var p := origin+Vector2(x,z)*stride
					# Casa as duas amostras de 4m e a diagonal original em volta da
					# depressão da ponte. Uma interpolação grosseira poderia subir acima dela.
					var divisions := int(stride/4.0) if Rect2(384,-368,192,160).has_point(p) else 1
					var step := stride/float(divisions)
					for sub_z in divisions:
						for sub_x in divisions:
							var cell := p+Vector2(sub_x,sub_z)*step
							var pieces: Array[Rect2] = [Rect2(cell,Vector2.ONE*step)]
							for cut in local_cuts:
								var next: Array[Rect2] = []
								for piece in pieces: next.append_array(_outside(piece,cut))
								pieces = next
							for piece in pieces:
								var start := vertices.size()
								for point: Vector2 in [piece.position,Vector2(piece.end.x,piece.position.y),piece.end,Vector2(piece.position.x,piece.end.y)]:
									vertices.append(Vector3(point.x,OCEAN.surface_y(point)-.12,point.y))
									normals.append(Vector3.UP)
									colors.append(Color(1,0,0,1))
									uv.append(point-origin)
								indices.append_array(PackedInt32Array([start,start+1,start+3,start+1,start+2,start+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name = "LookoutDistantSea"
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/regions/harbor_ocean.gdshader")
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("panorama_extent",EXTENT)
	node.set_meta("water_exclusions",cuts)
	return node

static func _outside(rect: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap := rect.intersection(cut)
	if not overlap.has_area(): return [rect]
	var pieces: Array[Rect2] = []
	if overlap.position.y>rect.position.y: pieces.append(Rect2(rect.position,Vector2(rect.size.x,overlap.position.y-rect.position.y)))
	if overlap.end.y<rect.end.y: pieces.append(Rect2(Vector2(rect.position.x,overlap.end.y),Vector2(rect.size.x,rect.end.y-overlap.end.y)))
	if overlap.position.x>rect.position.x: pieces.append(Rect2(Vector2(rect.position.x,overlap.position.y),Vector2(overlap.position.x-rect.position.x,overlap.size.y)))
	if overlap.end.x<rect.end.x: pieces.append(Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(rect.end.x-overlap.end.x,overlap.size.y)))
	return pieces
