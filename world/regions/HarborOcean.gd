extends RefCounted
## Opaque, streamed ocean. Shore distance is baked on creation, never per frame.
const WATER_Y := -0.94 # Preserve the top of the previous water box.
const STEP := 4.0
const DEPTH_RANGE := 24.0
## Período das ondas em metros. O shader recebe coordenada local 0..PERIOD em UV:
## no renderizador Mobile a coordenada de mundo (~500 m) perdia precisão no
## fragmento e a fase das ondas virava blocos quadrados (captura de 2026-09-24).
const PERIOD := 256.0
const SHADER := preload("res://world/regions/harbor_ocean.gdshader")
var shores: Array[PackedVector2Array] = []
var material: ShaderMaterial
var shore_wash := preload("res://world/regions/HarborShoreWash.gd").new()

func configure(land: Array, extra: Array[PackedVector2Array]) -> void:
	shores.clear()
	for row in land:
		var rect := Rect2(float(row[0])/16.0,float(row[1])/16.0,float(row[2])/16.0,float(row[3])/16.0)
		shores.append(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))
	shores.append_array(extra)
	material = ShaderMaterial.new()
	material.shader = SHADER
	shore_wash.configure(shores)

func shore_distance(point: Vector2) -> float:
	var nearest := DEPTH_RANGE
	for polygon in shores:
		for i in polygon.size():
			var closest := Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
			nearest = minf(nearest,point.distance_to(closest))
	return nearest

func build_chunk(parent: Node3D, rect: Rect2) -> MeshInstance3D:
	var count := maxi(1,ceili(rect.size.x/STEP))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	# Chunks de 64 m alinhados cabem inteiros num bloco de PERIOD: sem costura dentro do chunk.
	var base := (rect.position/PERIOD).floor()*PERIOD
	var indices := PackedInt32Array()
	for z in range(count+1):
		for x in range(count+1):
			var point := rect.position+rect.size*Vector2(float(x)/count,float(z)/count)
			vertices.append(Vector3(point.x,WATER_Y,point.y))
			normals.append(Vector3.UP)
			colors.append(Color(shore_distance(point)/DEPTH_RANGE,0,0,1))
			uvs.append(point-base)
	for z in count:
		for x in count:
			var a := z*(count+1)+x
			indices.append_array(PackedInt32Array([a,a+1,a+count+1,a+1,a+count+2,a+count+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface := MeshInstance3D.new()
	surface.name = "Water"
	surface.mesh = mesh
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(surface)
	shore_wash.build_chunk(surface,rect)
	return surface
