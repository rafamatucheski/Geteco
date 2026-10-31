extends RefCounted
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Substitui uma parte limitada da superfície real do teto por vidro. Os triângulos
## opacos originais são recortados, nunca cobertos por um decalque escuro.
var model: Node3D
var surfaces: Array = []
var glass_node: MeshInstance3D
var glass_material: StandardMaterial3D
var _style := ""
var _built := false
var cut_triangles := 0

func bind(source: Node3D, _painter: RefCounted) -> void:
	model = source

func apply(style: String) -> void:
	if style == _style: return
	_style = style
	if not style.is_empty() and not _built: _build()
	for row in surfaces:
		if is_instance_valid(row.part): row.part.mesh = row.original if style.is_empty() else row.cut
	if is_instance_valid(glass_node):
		glass_node.visible = not style.is_empty()
		glass_material.albedo_color = Color(.14,.23,.27,.32) if style == "glass" else Color(.65,.78,.81,.16)
	# Os amassados mantêm a topologia de repouso e se reconstroem dela a cada impacto/reparo.
	# Adota esta nova malha de repouso antes que eles possam ressuscitar a pele anterior do teto.
	var vehicle: Node = model.get_parent()
	if not surfaces.is_empty() and vehicle is CharacterBody3D and is_instance_valid(vehicle.get("body_dents")):
		vehicle.body_dents.geometry_changed()

func _build() -> void:
	_built = true
	var vehicle: Node = model.get_parent()
	# O builder de porta é dono da própria troca atômica de casca. Termina isso primeiro para que
	# remover um kit de teto salvo não possa restaurar uma casca anterior às portas sobre as folhas.
	if vehicle is CharacterBody3D and vehicle.has_method("finish_doors"): vehicle.finish_doors()
	var cabin: Dictionary = model.get_meta("vehicle_interior_spec",{})
	# Um forro opaco/alfa separado obstruiria a abertura; esses modelos ficam
	# excluídos de propósito pelo catálogo de compatibilidade até o forro deles ser separado.
	if cabin.is_empty() or bool(cabin.get("roof_liner",true)) or bool(cabin.get("open_top",false)): return
	var front := float(cabin.get("wz1",-.25))+.13
	var rear := float(cabin.get("rear_top",.55))-.13
	if rear-front < .22: return
	var half := float(cabin.get("hw",.7))*.52
	var rectangle := Vector4(-half,half,front,rear)
	var min_y := float(cabin.roof)-.05
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		if part.name in ["Interior","InteriorAlpha","RoofCut"]: continue
		# Cortar vértices já deformados e depois pedir a BodyDents que reaplique os
		# registros deformaria o mesmo impacto duas vezes. Sempre corta a malha de repouso.
		var original: Mesh = part.get_meta("body_dents_rest_mesh",part.mesh)
		var replacement := ArrayMesh.new()
		var changed := false
		var xf := relative_transform(part,model)
		for surface in original.get_surface_count():
			var arrays := MESH_ARRAYS.arrays_of(original,surface)
			if arrays.is_empty() or original.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return
			var material := part.get_active_material(surface) as StandardMaterial3D
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var surface_changed := false
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var polygon: Array = []
				for j in 3:
					var index := indices[i+j] if not indices.is_empty() else i+j
					polygon.append({"p":vertices[index],"n":normals[index] if not normals.is_empty() else Vector3.UP,"uv":uvs[index] if not uvs.is_empty() else Vector2.ZERO,"c":colors[index] if not colors.is_empty() else Color.WHITE})
				var p: Vector3 = xf*polygon[0].p
				var q: Vector3 = xf*polygon[1].p
				var r: Vector3 = xf*polygon[2].p
				var normal: Vector3 = (q-p).cross(r-p).normalized()
				var candidate: bool = material != null and material.resource_name != "glass" and minf(p.y,minf(q.y,r.y)) >= min_y and absf(normal.y) > .45
				if not candidate:
					emit_polygon(tool,polygon)
					continue
				var remaining := polygon
				# As peças de fora são disjuntas; o resto final é o furo.
				for plane in [[0,rectangle.x,1.0],[0,rectangle.y,-1.0],[2,rectangle.z,1.0],[2,rectangle.w,-1.0]]:
					var outside := clip(remaining,xf,int(plane[0]),float(plane[1]),float(plane[2]),false)
					emit_polygon(tool,outside)
					remaining = clip(remaining,xf,int(plane[0]),float(plane[1]),float(plane[2]),true)
				if remaining.size() >= 3:
					changed = true
					surface_changed = true
					cut_triangles += remaining.size()-2
					var glass_polygon: Array = []
					for vertex in remaining:
						var copy: Dictionary = vertex.duplicate()
						copy.p = xf*vertex.p
						copy.n = (xf.basis*vertex.n).normalized()
						copy.c = Color.WHITE
						glass_polygon.append(copy)
					# O vinil/acabamento do teto também é recortado, mas não pode criar outro vidro
					# sobre o vidro. Mantém uma pele voltada para cima da casca da carroceria.
					if material.resource_name in ["paint","roof_paint"] and (xf.basis*polygon[0].n).y > .1:
						emit_polygon(glass,glass_polygon)
			if surface_changed:
				tool.set_material(original.surface_get_material(surface))
				tool.commit(replacement)
			else:
				replacement.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays)
				replacement.surface_set_material(replacement.get_surface_count()-1,original.surface_get_material(surface))
		if changed: surfaces.append({"part":part,"original":original,"cut":replacement})
	if cut_triangles == 0: return
	glass_material = StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass_material.roughness = .15
	glass_material.metallic = .12
	glass.set_material(glass_material)
	glass_node = MeshInstance3D.new()
	glass_node.name = "TuningSunroofGlass"
	glass_node.mesh = glass.commit()
	glass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(glass_node)

static func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != null and cursor != ancestor:
		result = cursor.transform*result
		cursor = cursor.get_parent() as Node3D
	return result

static func clip(polygon: Array, xf: Transform3D, axis: int, edge: float, direction: float, inside: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i+1)%polygon.size()]
		var da: float = ((xf*a.p)[axis]-edge)*direction
		var db: float = ((xf*b.p)[axis]-edge)*direction
		var a_in: bool = da >= 0.0 if inside else da < 0.0
		var b_in: bool = db >= 0.0 if inside else db < 0.0
		if a_in: result.append(a)
		if a_in != b_in:
			var t := da/(da-db)
			result.append({"p":a.p.lerp(b.p,t),"n":a.n.lerp(b.n,t).normalized(),"uv":a.uv.lerp(b.uv,t),"c":a.c.lerp(b.c,t)})
	return result

static func emit_polygon(tool: SurfaceTool, polygon: Array) -> void:
	for i in range(1,polygon.size()-1):
		for index in [0,i,i+1]:
			var vertex: Dictionary = polygon[index]
			tool.set_normal(vertex.n)
			tool.set_uv(vertex.uv)
			tool.set_color(vertex.c)
			tool.add_vertex(vertex.p)
