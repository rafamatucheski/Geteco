extends Node3D
## Silhuetas só visuais da geografia de produção. Não monta chunks remotos,
## física, atores, luzes, posições de cidade chutadas nem estado de save.
const DESERT := preload("res://world/editing/EditableDesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const VILLAGE := preload("res://world/desert/DesertMoonVillage.gd")
const HEIGHTS := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const SEA := preload("res://world/places/coastal_lookout/LookoutDistantSea.gd")
const CANAL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const SKATE := preload("res://activities/skate/SkateParkLayout.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const HARBOR_COAST := preload("res://world/shape/HarborCoast.gd")
var _geometry: Dictionary = {}
var _cells: Array[Dictionary] = []
var _cube := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _material: StandardMaterial3D
var source_buildings: Array[Dictionary] = []

func build(production) -> void:
	name = "LookoutDistantCity"
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = .94
	_cube.size = Vector3.ONE
	_cylinder.radial_segments = 10
	_cylinder.rings = 1
	_cylinder.top_radius = .5
	_cylinder.bottom_radius = .5
	_cylinder.height = 1.0
	# prepare_data é preparação de geografia só de leitura; a região destacada nunca
	# entra na árvore, então nenhuma vida ambiente, horizonte, chunk ou sistema de mineração começa.
	var desert = DESERT.new()
	desert.prepare_data()
	for data: Dictionary in desert.buildings:
		var row := data.duplicate(true)
		row["region"] = "desert"
		source_buildings.append(row)
		_building(row,"desert",96.0)
	for road: Dictionary in desert.roads:
		if str(road.get("id","")).begins_with("mining"): continue
		_road(road,"desert",96.0)
	for records: Array in desert.records.values():
		for record: Dictionary in records:
			if record.kind == "water_tower": _tower(record.position,"desert",96.0)
	for data in VILLAGE.definitions():
		if data.kind=="tower": _tower(data.position,"desert",96.0)
	desert.free()
	var harbor = production.regions.get("harbor")
	if is_instance_valid(harbor):
		for data: Dictionary in harbor.buildings:
			# A garagem principal e os serviços subterrâneos/de bueiro têm arte independente.
			if str(data.get("id","")) in ["Garage","maciota_garage"]: continue
			if str(data.get("kind","")) in ["sewer","manhole"]: continue
			var row := data.duplicate(true)
			row["height"] = HEIGHTS.resolved_height(row)
			row["region"] = "harbor"
			source_buildings.append(row)
			_building(row,"harbor",64.0)
		_harbor_land(harbor)
		for road: Dictionary in harbor.roads: _road(road,"harbor",64.0)
	_flush()
	set_meta("authored_building_count",source_buildings.size())
	set_meta("proxy_cell_count",_cells.size())
	refresh(production)

func _key(region: String, point: Vector3, cell: float) -> String:
	var index := Vector2i(floori(point.x/cell),floori(point.z/cell))
	var key := "%s:%d:%d"%[region,index.x,index.y]
	if not _geometry.has(key):
		_geometry[key] = {"region":region,"cell":index,"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
	return key

func _building(data: Dictionary, region: String, cell: float) -> void:
	var point: Vector3 = data.position
	var size: Vector2 = data.size
	var height := float(data.get("height",4.0))
	if height<=0.0 or size.x<=0.0 or size.y<=0.0: return
	var key := _key(region,point,cell)
	var color := Color(data.get("color",Color("b7a085") if region=="desert" else Color("879087")))
	var city_basis := Basis(Vector3.UP,float(data.get("editor_rotation",data.get("yaw",0.0))))
	var kind := str(data.get("kind",""))
	# Bodies sit just inside the real authored shell. During incremental chunk
	# arrival its outer walls occlude the proxy without coplanar surfaces.
	var dimensions := Vector3(size.x*.985,maxf(.2,height-.05),size.y*.985)
	if kind == "urban_setback":
		_box(key,point+city_basis*Vector3(0,height*.25,0),Vector3(dimensions.x,height*.5,dimensions.z),color,city_basis)
		_box(key,point+city_basis*Vector3(0,height*.70,0),Vector3(dimensions.x*.76,height*.4,dimensions.z*.76),color,city_basis)
		_box(key,point+city_basis*Vector3(0,height*.95,0),Vector3(dimensions.x*.48,height*.1,dimensions.z*.48),color,city_basis)
	elif kind == "urban_twin":
		_box(key,point+Vector3(0,height*.1,0),Vector3(dimensions.x,height*.2,dimensions.z),color,city_basis)
		for side in [-1.0,1.0]: _box(key,point+city_basis*Vector3(side*size.x*.28,height*.6,0),Vector3(dimensions.x*.40,height*.8,dimensions.z*.86),color,city_basis)
	else:
		_box(key,point+Vector3(0,dimensions.y*.5,0),dimensions,color,city_basis)
		_box(key,point+Vector3(0,height+.09,0),Vector3(size.x+.28,.18,size.y+.28),color.darkened(.20),city_basis)
	var floors := clampi(int(height/3.0),1,8)
	for floor_index in floors:
		var y := minf(height-.65,(floor_index+.60)*height/floors)
		for side in [-1.0,1.0]:
			for column in [-.28,.28]:
				var at := point+city_basis*Vector3(size.x*column,y,side*(size.y*.5+.025))
				_box(key,at,Vector3(minf(2.2,size.x*.16),minf(1.25,height*.35),.04),Color("435352"),city_basis)
	# Source commercial adobe silhouettes have a visible shade over their front.
	if region=="desert" and kind in ["bank","shop","diner","motel","workshop"]:
		var side := -1.0 if kind in ["shop","diner"] else 1.0
		_box(key,point+Vector3(0,minf(3.1,height-.5),side*(size.y*.5+.75)),Vector3(size.x*.8,.18,1.6),Color("97714f"),city_basis)

func _tower(point: Vector3, region: String, cell: float) -> void:
	var key := _key(region,point,cell)
	for x in [-2.0,2.0]:
		for z in [-2.0,2.0]: _box(key,point+Vector3(x,5,z),Vector3(.28,10,.28),Color("78684d"))
	_mesh(key,_cylinder,Transform3D(Basis.from_scale(Vector3(6.2,4,6.2)),point+Vector3(0,11,0)),Color("a29777"))
	_mesh(key,_cylinder,Transform3D(Basis.from_scale(Vector3(6.6,.2,6.6)),point+Vector3(0,13.04,0)),Color("736c56"))

func _road(road: Dictionary, region: String, cell: float) -> void:
	var points: PackedVector3Array = road.points
	var width := float(road.width)
	for index in range(1,points.size()):
		var from := points[index-1]
		var to := points[index]
		var count := maxi(1,ceili(from.distance_to(to)/24.0))
		var tangent := (to-from).normalized()
		var side := Vector3(-tangent.z,0,tangent.x)*width*.5
		for part in count:
			var a := from.lerp(to,float(part)/count)
			var b := from.lerp(to,float(part+1)/count)
			# Never lay visual asphalt over the underground canal's open ramps.
			if region=="harbor" and CANAL.WATER_CUT.has_point(Vector2((a.x+b.x)*.5,(a.z+b.z)*.5)): continue
			var key := _key(region,(a+b)*.5,cell)
			_quad(key,[a-side+Vector3.UP*.003,a+side+Vector3.UP*.003,b+side+Vector3.UP*.003,b-side+Vector3.UP*.003],Color("565953"))

func _harbor_land(region) -> void:
	var cuts: Array[Rect2] = [CANAL.WATER_CUT,Rect2(-413.25,85.35,6.10,3.30)]
	if SKATE.enabled(): cuts.append(SKATE.FOOTPRINT)
	for opening in PLACES.sewer_openings(): cuts.append(Rect2(opening.position/16.0,opening.size/16.0))
	for row: Array in region.source_data.harbor_land:
		var land := Rect2(float(row[0])/16.0,float(row[1])/16.0,float(row[2])/16.0,float(row[3])/16.0)
		for x in range(floori(land.position.x/64.0),ceili(land.end.x/64.0)):
			for z in range(floori(land.position.y/64.0),ceili(land.end.y/64.0)):
				var rect := land.intersection(Rect2(x*64,z*64,64,64))
				var pieces: Array[Rect2] = [rect]
				for cut in cuts:
					var remaining: Array[Rect2] = []
					for piece in pieces: remaining.append_array(SEA._outside(piece,cut))
					pieces = remaining
				for piece in pieces:
					var key := _key("harbor",Vector3(piece.get_center().x,0,piece.get_center().y),64.0)
					_quad(key,[Vector3(piece.position.x,-.035,piece.position.y),Vector3(piece.end.x,-.035,piece.position.y),Vector3(piece.end.x,-.035,piece.end.y),Vector3(piece.position.x,-.035,piece.end.y)],Color("737b69"))
	# Mundo orgânico (etapa 3): o chão natural dos bairros com costa curva, sem repetir os retângulos.
	var rects: Array[PackedVector2Array] = []
	for row: Array in region.source_data.harbor_land: rects.append(GROUND_CUT.rect_polygon(Rect2(float(row[0])/16.0,float(row[1])/16.0,float(row[2])/16.0,float(row[3])/16.0)))
	for polygon in GROUND_CUT.subtract_exact(HARBOR_COAST.natural_land(),rects):
		var bounds := GROUND_CUT.bounds(polygon)
		for x in range(floori(bounds.position.x/64.0),ceili(bounds.end.x/64.0)):
			for z in range(floori(bounds.position.y/64.0),ceili(bounds.end.y/64.0)):
				for piece in Geometry2D.intersect_polygons(polygon,GROUND_CUT.rect_polygon(Rect2(x*64,z*64,64,64))):
					# Mesmo sentido dos quadrados acima, para a face ficar para cima.
					if Geometry2D.is_polygon_clockwise(piece) != Geometry2D.is_polygon_clockwise(GROUND_CUT.rect_polygon(Rect2(0,0,1,1))): piece.reverse()
					var triangles := Geometry2D.triangulate_polygon(piece)
					if triangles.is_empty(): continue
					var batch: Dictionary = _geometry[_key("harbor",Vector3(x*64+32,0,z*64+32),64.0)]
					for index in triangles:
						batch.vertices.append(Vector3(piece[index].x,-.035,piece[index].y))
						batch.normals.append(Vector3.UP)
						batch.colors.append(Color("52683f"))

func _box(key: String, point: Vector3, size: Vector3, color: Color, box_basis := Basis.IDENTITY) -> void:
	_mesh(key,_cube,Transform3D(box_basis*Basis.from_scale(size),point),color)

func _mesh(key: String, mesh: PrimitiveMesh, mesh_transform: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_matrix := mesh_transform.basis.inverse().transposed()
	var batch: Dictionary = _geometry[key]
	for index in indices:
		batch.vertices.append(mesh_transform*vertices[index])
		batch.normals.append((normal_matrix*normals[index]).normalized())
		batch.colors.append(color)

func _quad(key: String, points: Array, color: Color) -> void:
	var batch: Dictionary = _geometry[key]
	for index in [0,1,3,1,2,3]:
		batch.vertices.append(points[index])
		batch.normals.append(Vector3.UP)
		batch.colors.append(color)

func _flush() -> void:
	for key: String in _geometry:
		var data: Dictionary = _geometry[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_COLOR] = data.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual := MeshInstance3D.new()
		visual.name = key.replace(":","_")
		visual.mesh = mesh
		visual.material_override = _material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.set_meta("panorama_region",data.region)
		visual.set_meta("panorama_cell",data.cell)
		add_child(visual)
		_cells.append({"region":data.region,"cell":data.cell,"visual":visual,"shown":visual.visible})
	_geometry.clear()

func restore_prebuilt(sources: Array[Dictionary]) -> void:
	# O PackedScene preserva recursos de malha/material e metadados de célula. Sem
	# gerador, leitura de editor, região destacada nem alocação de geometria ao reentrar.
	source_buildings.assign(sources)
	_cells.clear()
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("panorama_cell"):
			_cells.append({"region":str(child.get_meta("panorama_region")),"cell":child.get_meta("panorama_cell"),"visual":child,"shown":child.visible})

func refresh(production) -> void:
	# Uma região pode estar residente só com as células da ponte. Mantém todas as células
	# da cidade distante até os registros de prédios daquela célula terminarem o mobiliário.
	var completed := {}
	for id in ["harbor","desert"]:
		var region = production.regions.get(id)
		var ready_chunks := {}
		if is_instance_valid(region) and region.visible:
			var building := {}
			for job in region.build_jobs: building[job.key] = true
			for key in region.chunks:
				var chunk: Node = region.chunks[key]
				if not building.has(key) and is_instance_valid(chunk) and not chunk.is_queued_for_deletion(): ready_chunks[key] = true
		completed[id] = ready_chunks
	for row in _cells:
		var shown: bool = not completed.get(row.region,{}).has(row.cell)
		if shown == bool(row.shown): continue
		row.visual.visible = shown
		row.shown = shown
