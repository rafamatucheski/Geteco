extends RefCounted
## Narrow, static shoreline strips. GPU animates the wash; no frame callbacks.
const WIDTH := 1.7
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var strips: Array[Dictionary] = []
var material: ShaderMaterial

func configure(polygons: Array[PackedVector2Array]) -> void:
	strips.clear()
	material = ShaderMaterial.new()
	material.shader = preload("res://world/regions/harbor_shore_wash.gdshader")
	for polygon in polygons:
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i+1)%polygon.size()]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var tangent := (b-a)/length
			var normal := Vector2(-tangent.y,tangent.x)
			var steps := maxi(1,ceili(length/2.0))
			for step in steps:
				var start := a.lerp(b,float(step)/steps)
				var end := a.lerp(b,float(step+1)/steps)
				var midpoint := (start+end)*0.5
				var outward := normal
				if _on_land(midpoint+outward*0.05,polygons): outward = -normal
				if _on_land(midpoint+outward*0.05,polygons): continue
				# Avoid filling narrow gaps or overlapping another shore's strip.
				var width := WIDTH
				while width > 0.1 and _on_land(midpoint+outward*width,polygons): width *= 0.5
				var quad := PackedVector2Array([start,end,end+outward*width,start+outward*width])
				strips.append({"quad":quad,"origin":a,"tangent":tangent,"normal":outward,"bounds":_bounds(quad)})

# O mar é recortado sobre o Túnel do canal (WATER_CUT), mas a espuma não era: as faixas
# animadas em y=-0,925 ficavam por cima do teto de vidro e da lâmina de água do tubo e
# apareciam como leques claros "piscando" na parede norte conforme a câmera andava.
static func _outside_canal_cut(pieces: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var cut: Rect2 = CANAL_TUNNEL.WATER_CUT
	var cut_polygon := PackedVector2Array([cut.position,Vector2(cut.end.x,cut.position.y),cut.end,Vector2(cut.position.x,cut.end.y)])
	var result: Array[PackedVector2Array] = []
	for piece in pieces:
		for outside in Geometry2D.clip_polygons(piece,cut_polygon):
			# Faixa estreita contra retângulo de 20 m: o recorte nunca gera furo.
			if outside.size() >= 3: result.append(outside)
	return result

func _on_land(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
	return false

func _bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0],Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result

func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for strip in strips:
		if not rect.intersects(strip.bounds): continue
		for piece in _outside_canal_cut(Geometry2D.intersect_polygons(strip.quad,clip)):
			var base := vertices.size()
			for point in piece:
				vertices.append(Vector3(point.x,-0.925,point.y))
				normals.append(Vector3.UP)
				var offset: Vector2 = point-strip.origin
				uv.append(Vector2(offset.dot(strip.normal),offset.dot(strip.tangent)))
			for index in Geometry2D.triangulate_polygon(piece): indices.append(base+index)
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.name = "ShoreWash"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
