extends Node3D
## Native reconstruction of exact MountainSceneryBuilder 2D lake polygons.
## Existing terrain remains shallow traversable ground; swimming/depth behavior is separate.
var variant := "secret"
const SCALE := 1.0/16.0
const PINE = preload("res://world/regions/NativePine.gd")
var water_polygon := PackedVector2Array()
var dry_polygons: Array[PackedVector2Array] = []
var materials: Dictionary = {}
## Espelho d'água do lago alpino abaixo do chão, dentro da bacia de LakeBasins (0,6 m).
const ALPINE_WATER_Y := -.2
const WATER_SHADER := preload("res://world/regions/mountain_lake.gdshader")
func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalLakeData.json"))[variant]
	_collect_road_clearance()
	if variant == "alpine":
		# A margem agora é a encosta da bacia no próprio terreno (LakeBasins); a faixa
		# plana marrom da V1 ficava pintada por cima e deixava o lago mal encaixado.
		# Água cobre a margem inteira da V1; quem desenha a linha d'água é o terreno
		# da bacia cruzando ALPINE_WATER_Y, e o shader clareia o raso pela profundidade
		# real. A camada separada de água funda criava um segundo degrau de cor.
		water_polygon = _smooth(_clear_roads(_points(data.lake_shore,Vector2(-7000,0))))
		# A água nasce da própria bacia (LakeBasins): células de 2 m onde o terreno
		# afunda. Recortar água e bacia por caminhos diferentes deixava véu de água
		# sobre o capim ou buraco seco; assim as duas coincidem, e a borda da malha
		# fica sempre sob o chão.
		_basin_water()
		for pair in [[Vector2(7380,-260),Vector2(7350,-235)],[Vector2(7350,-235),Vector2(7310,-207)],[Vector2(7310,-207),Vector2(7285,-157)],[Vector2(7285,-157),Vector2(7260,-115)]]:
			_strip((pair[0]-Vector2(7000,0))*SCALE,(pair[1]-Vector2(7000,0))*SCALE,30*SCALE,.014,Color("1e5668"))
	else:
		_surface("GlacialShore",_points(data.shore),.007,Color("2a241e"))
		water_polygon = _points(data.shallow)
		water_polygon = _smooth(_clear_roads(water_polygon))
		_surface("GlacialShallows",water_polygon,.042,Color("175b6a"),true)
		_surface("GlacialDeepColor",_points(data.deep),.048,Color("0b2f3a"),true)
		_surface("FrozenCascade",_points(data.frozen_fall),.09,Color("709ba6"))
		var island := _points(data.is_rock,Vector2(245,-65))
		dry_polygons.append(island)
		_surface("CacheIsland",island,.085,Color("423a31"))
		_surface("IslandMoss",_points(data.is_moss,Vector2(245,-65)),.09,Color("22331f"))
		_surface("OriginalRowboat",_points(data.rowboat,Vector2(245,-65)),.10,Color("6d4c35"))
		_strip(Vector2(205,-45)*SCALE,Vector2(170,-25)*SCALE,14*SCALE,.06,Color("4e3725"))
		var tree := PINE.create(7,true)
		tree.position = Vector3(265*SCALE,.05,-80*SCALE)
		tree.scale = Vector3.ONE*1.15
		add_child(tree)
		_box(tree,Vector3(0,1.3,0),Vector3(.4,2.6,.4),Color("554333"),true)
		var camp := _points(data.camp_ground,Vector2(180,180))
		dry_polygons.append(camp)
		_surface("SmugglerCampsite",camp,.08,Color("382e22")) # Dry shelf above the moving shallow water.
		for point in [Vector2(120,220),Vector2(135,235)]: _box(self,Vector3(point.x*SCALE,.4,point.y*SCALE),Vector3(1.5,.8,1.25),Color("59402b"),true)
		var fire_center := Vector2(205,160)*SCALE
		for i in 12:
			var at := fire_center+Vector2.from_angle(TAU*i/12)*14*SCALE
			_box(self,Vector3(at.x,.10,at.y),Vector3(.24,.2,.22),Color("57606f"))
		_box(self,Vector3(fire_center.x,.08,fire_center.y),Vector3(.7,.12,.6),Color("ae5429"))
		var heat := Marker3D.new()
		heat.name = "OriginalCampHeatSource"
		heat.position = Vector3(fire_center.x,0,fire_center.y)
		heat.set_meta("radius",180*SCALE)
		heat.add_to_group("native_heat_source")
		add_child(heat)
		var positions := [Vector2(-135,-75),Vector2(95,-60),Vector2(-95,65),Vector2(45,80),Vector2(-54,-177),Vector2(-31,-168),Vector2(-66,-158)]
		for i in positions.size(): _ice(positions[i],i,[.85,.6,1.0,.55,.8,.5,.4][i])
		for point in [Vector2(45,105),Vector2(58,75),Vector2(65,50)]:
			var stone := _points([[-12,-9],[11,-10],[13,9],[-10,10]],point)
			dry_polygons.append(stone)
			_surface("SteppingStone",stone,.09,Color("57656a"))
	add_to_group("native_water_surface")
func contains_water(world_position: Vector3) -> bool:
	var local := to_local(world_position)
	var point := Vector2(local.x,local.z)
	if variant == "secret" and absf(point.x)<1.7 and point.y>-13.6 and point.y<9.7: return false
	for polygon in dry_polygons:
		if Geometry2D.is_point_in_polygon(point,polygon): return false
	return Geometry2D.is_point_in_polygon(point,water_polygon)
func _points(raw: Array,offset := Vector2.ZERO) -> PackedVector2Array:
	var result := PackedVector2Array()
	for pair in raw: result.append((Vector2(pair[0],pair[1])+offset)*SCALE)
	return result
func _ice(at: Vector2,index: int,ice_scale: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7823+index*193
	var rim := PackedVector2Array()
	for i in 11:
		var angle := TAU*i/11.0
		var radius := rng.randf_range(.76,1.12)
		var point := Vector2(cos(angle)*22,sin(angle)*13)*radius
		rim.append((point.rotated(index*1.17)*ice_scale+at)*SCALE)
	_surface("FracturedIce",rim,.08,Color("a2c7ce"))
func _material(color: Color,water := false) -> Material:
	var key := color.to_html()+str(water)
	if materials.has(key): return materials[key]
	if water:
		var water_material := ShaderMaterial.new()
		water_material.shader = WATER_SHADER
		water_material.set_shader_parameter("base_color",Vector3(color.r,color.g,color.b))
		materials[key] = water_material
		return water_material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .9
	materials[key] = mat
	return mat
func _surface(id: String,polygon: PackedVector2Array,height: float,color: Color,water := false) -> void:
	if id in CLIPPED_SURFACES: polygon = _smooth(_clear_roads(polygon))
	if polygon.size() < 3: return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0,indices.size(),3):
		var a := polygon[indices[i]]
		var b := polygon[indices[i+1]]
		var c := polygon[indices[i+2]]
		var divisions := maxi(1,ceili(maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a)))/2.0)) if water else 1
		for row in divisions:
			for column in divisions-row:
				_add_water_triangle(surface,a,b,c,height,divisions,row,column,false)
				if row+column < divisions-1:
					_add_water_triangle(surface,a,b,c,height,divisions,row,column,true)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = id
	mesh.mesh = surface.commit()
	mesh.material_override = _material(color,water)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	# Só a água com bacia no terreno lê a profundidade (ver mountain_lake.gdshader).
	if id == "AlpineWater": mesh.set_instance_shader_parameter("depth_fade",1.0)
	if water and id.ends_with("Shallows") and height > 0.0:
		_water_edge(polygon,height,color.darkened(.28))
func _add_water_triangle(surface: SurfaceTool,a: Vector2,b: Vector2,c: Vector2,height: float,n: int,row: int,column: int,upper: bool) -> void:
	var p := a+(b-a)*(float(row)/n)+(c-a)*(float(column)/n)
	var q := a+(b-a)*(float(row+1)/n)+(c-a)*(float(column)/n)
	var r := a+(b-a)*(float(row)/n)+(c-a)*(float(column+1)/n)
	if upper:
		p = q
		q = a+(b-a)*(float(row+1)/n)+(c-a)*(float(column+1)/n)
	for point in [p,q,r]: surface.add_vertex(Vector3(point.x,height,point.y))
func _water_edge(polygon: PackedVector2Array,height: float,color: Color) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		for point in [Vector3(a.x,height,a.y),Vector3(a.x,-.012,a.y),Vector3(b.x,-.012,b.y),Vector3(a.x,height,a.y),Vector3(b.x,-.012,b.y),Vector3(b.x,height,b.y)]:
			surface.add_vertex(point)
	surface.generate_normals()
	var edge := MeshInstance3D.new()
	edge.name = "WaterEdge"
	edge.mesh = surface.commit()
	edge.material_override = _material(color)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)
func _strip(a: Vector2,b: Vector2,width: float,height: float,color: Color) -> void:
	var normal := (b-a).orthogonal().normalized()*width*.5
	_surface("OriginalPath",PackedVector2Array([a-normal,b-normal,b+normal,a+normal]),height,color)
func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color,solid := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _material(color)
	parent.add_child(mesh)
	if solid: mesh.create_trimesh_collision()

## Recorte das estradas: os polígonos da V1 foram desenhados com a estrada pintada
## por cima; em 3D a água e a margem encostavam no asfalto e pareciam invadir a
## pista (relato do jogador em 2026-09-24). Água e margem ficam ROAD_CLEARANCE
## além da borda da estrada.
const ROAD_CLEARANCE := 3.5
const CLIPPED_SURFACES := ["AlpineShore","AlpineShallows","AlpineDeepColor","GlacialShore","GlacialShallows","GlacialDeepColor"]
var _road_buffers: Array[PackedVector2Array] = []

func _collect_road_clearance() -> void:
	_road_buffers.clear()
	var region: Node = get_parent()
	while region != null and not ("roads" in region): region = region.get_parent()
	if region == null: return
	for road in region.roads:
		var points: PackedVector3Array = road.points
		var half: float = float(road.width)*.5+ROAD_CLEARANCE
		for i in range(points.size()-1):
			var a := Vector2(points[i].x-position.x,points[i].z-position.z)
			var b := Vector2(points[i+1].x-position.x,points[i+1].z-position.z)
			if Geometry2D.get_closest_point_to_segment(Vector2.ZERO,a,b).length() > 120.0: continue
			var along := (b-a).normalized()*half
			var side := along.orthogonal()
			_road_buffers.append(PackedVector2Array([a-along-side,b+along-side,b+along+side,a-along+side]))

func _clear_roads(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := polygon
	for buffer in _road_buffers:
		if result.size() < 3: return result
		var pieces := Geometry2D.clip_polygons(result,buffer)
		if pieces.is_empty(): return PackedVector2Array()
		# Fica o maior pedaço (um furo é sempre menor que o contorno de fora); a água
		# não vira ilhas soltas por causa de uma estrada.
		var best := PackedVector2Array()
		var best_area := 0.0
		for piece in pieces:
			var area := absf(_area(piece))
			if area > best_area:
				best_area = area
				best = piece
		result = best
	return result

static func _area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size(): sum += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return sum*.5

## Contorno arredondado (Chaikin): os polígonos da V1 têm poucos pontos e cantos
## retos, e em 3D o lago parecia recortado em papel (relato do jogador em 2026-09-24).
static func _smooth(polygon: PackedVector2Array, iterations := 2) -> PackedVector2Array:
	var result := polygon
	for n in iterations:
		if result.size() < 3: return result
		var next := PackedVector2Array()
		for i in result.size():
			var a := result[i]
			var b := result[(i+1)%result.size()]
			next.append(a.lerp(b,.25))
			next.append(a.lerp(b,.75))
		result = next
	return result

func _basin_water() -> void:
	var basins := preload("res://world/regions/LakeBasins.gd")
	basins.depth_at(Vector2.ZERO) # carrega o contorno
	var bounds: Rect2 = basins._bounds
	if bounds.size == Vector2.ZERO: return
	var cell := 2.0
	var origin := Vector2(position.x, position.z)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := ALPINE_WATER_Y
	var x := bounds.position.x - cell
	while x < bounds.end.x + cell:
		var z := bounds.position.y - cell
		while z < bounds.end.y + cell:
			var corners := [Vector2(x, z), Vector2(x + cell, z), Vector2(x + cell, z + cell), Vector2(x, z + cell)]
			var wet := false
			for corner in corners:
				if basins.depth_at(corner) > 0.0: wet = true
			if wet:
				for k in [0, 1, 2, 0, 2, 3]:
					var c: Vector2 = corners[k] - origin
					surface.add_vertex(Vector3(c.x, y, c.y))
			z += cell
		x += cell
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "AlpineWater"
	mesh.mesh = surface.commit()
	mesh.material_override = _material(Color("226274"), true)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.set_instance_shader_parameter("depth_fade", 1.0)
