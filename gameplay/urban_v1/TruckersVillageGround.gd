extends RefCounted
## Small worn yards, footpaths and soft verges; road access belongs to road data.
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const EARTH_TOP := .022
const RIM := 1.2
const STANDIN_GROUP := &"truckers_village_ground_standin"
const STANDIN_NAME := "TruckersVillageMeadowStandIn"
## TruckersVillageVisuals.FOOTPRINT: chunks fora dele nem calculam a cobertura.
const SITE_BOUNDS := Rect2(-418,62,176,88)
## GETECO_PLACE_GROUND_CUT=0 volta aos retalhos planos por cima do mato (anel a 2 cm).
static var cut_enabled := OS.get_environment("GETECO_PLACE_GROUND_CUT") != "0"
## A vila some com a região inativa (set_region_active); enquanto isso o mato recortado volta
## como substituto no chunk do Harbor (NativeRegion._place_ground_cut).
static var site_shown := false
static var _cover: Array[PackedVector2Array] = []

static func build(village: Node3D, homes: Array) -> void:
	var shader := preload("res://world/urban_detail/RuralGroundMaterial.gd").material()
	var plots := earth_plots(homes)
	if cut_enabled:
		var began := STALL_WORK.begin()
		_graded_ground(village,plots,shader)
		STALL_WORK.finish_slow("truckers_village.graded_ground",began,2000)
	else:
		for i in plots.size(): _patch(village,"VillageEarth%d"%i,plots[i],shader,EARTH_TOP)
	village.set_meta("earth_plots",plots)
	if cut_enabled: _track_site(village)
	# Broken apron edge instead of a raised slab. It meets the truck yard at grade.
	var concrete := preload("res://world/editing/WorldGroundFactory.gd").material("concrete")
	var apron := PackedVector2Array()
	for p in [Vector2(-49,-27),Vector2(-8,-27),Vector2(-8,-4),Vector2(-12,2),Vector2(-39,2),Vector2(-49,-3)]:
		var at: Vector3 = village.STATION_TRANSFORM*Vector3(p.x,0,p.y)
		apron.append(Vector2(at.x,at.z))
	if village.compact_station_enabled():
		apron=PackedVector2Array([Vector2(-41.68,-25.62),Vector2(-17.68,-25.62),Vector2(-17.68,-8),Vector2(-20,-5.62),Vector2(-39,-5.62),Vector2(-41.68,-8)])
		concrete=preload("res://runtime/desert/roadside/RoadsideArt.gd").concrete()
	_flat(village,"WornStationApron",apron,concrete,.037)
	concrete=preload("res://world/editing/WorldGroundFactory.gd").material("concrete")
	_flat(village,"WorkshopFloor",PackedVector2Array([Vector2(53.4,-9),Vector2(68.6,-9),Vector2(68.6,2),Vector2(67,3),Vector2(53.4,2)]),concrete,.038)

## Retalhos de terra (pátio, trilhas, quintais e vagas) já unidos, em coordenadas da vila.
static func earth_plots(homes: Array) -> Array[PackedVector2Array]:
	var yard := PackedVector2Array([Vector2(-51,-25),Vector2(-31,-28),Vector2(-9,-27),Vector2(-6,-17),Vector2(-7,1),Vector2(-21,4),Vector2(-42,5),Vector2(-52,-3)])
	var plots: Array[PackedVector2Array] = [yard]
	_path(plots,PackedVector2Array([Vector2(-56,4),Vector2(-35,6),Vector2(-10,6),Vector2(14,5),Vector2(36,7),Vector2(49,7)]),3.2)
	for i in homes.size():
		var center: Vector3 = homes[i][0]
		var yaw: float = homes[i][2]
		var basis := Basis(Vector3.UP,yaw)
		var plot := PackedVector2Array()
		for offset in [Vector3(-9,0,-6),Vector3(8,0,-6),Vector3(10,0,5),Vector3(7,0,9),Vector3(-8,0,9),Vector3(-10,0,3)]:
			var point: Vector3 = center+basis*offset
			plot.append(Vector2(point.x,point.z))
		plots.append(plot)
		var porch: Vector3 = center+basis*Vector3(0,0,8)
		var destination := Vector2(clampf(porch.x,-51,36),clampf(porch.z,-5,12))
		_path(plots,PackedVector2Array([Vector2(porch.x,porch.z),Vector2(porch.x,porch.z).lerp(destination,.5)+Vector2(1.6,-.6),destination]),2.2)
	_path(plots,PackedVector2Array([Vector2(34,4),Vector2(51,9),Vector2(61,6)]),2.6)
	_path(plots,PackedVector2Array([Vector2(-53,5),Vector2(-63,16),Vector2(-67,25)]),2.3)
	_path(plots,PackedVector2Array([Vector2(38,11),Vector2(45,23),Vector2(60,27)]),2.2)
	for spot in preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").SPOTS:
		var at: Vector3=spot[1]
		var bike: bool=str(spot[0]).begins_with("bike_")
		var half := Vector2(1.05,1.8) if bike else Vector2(1.8,3.3)
		var parking := PackedVector2Array()
		for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)]:
			parking.append(Vector2(at.x,at.z)+corner.rotated(-float(spot[2])))
		plots.append(parking)
	# Join plots before fading their edges; internal borders must never paint
	# strips of grass across other dirt paths. Road core remains above the rim.
	var merged := true
	while merged:
		merged=false
		for a in plots.size():
			for b in range(a+1,plots.size()):
				var union := Geometry2D.merge_polygons(plots[a],plots[b])
				if union.size()!=1: continue
				plots[a]=union[0]
				plots.remove_at(b)
				merged=true
				break
			if merged: break
	return plots

## Contorno externo do anel de um retalho (sem buracos): o anel desce até o mato exatamente aqui.
static func _rim_outlines(plot: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for outline in Geometry2D.offset_polygon(plot,RIM,Geometry2D.JOIN_ROUND):
		if not Geometry2D.is_polygon_clockwise(outline): result.append(outline)
	return result

## Área que a terra da vila (retalhos e anéis) cobre, em coordenadas do Harbor, para o Land não
## desenhar mato por baixo. Mesmos polígonos que _graded_patch usa para o anel.
static func world_cover() -> Array[PackedVector2Array]:
	if not cut_enabled: return []
	if _cover.is_empty():
		# A vila já está carregada quando o Harbor monta; load() só busca no cache. Sem ciclo de preload.
		var visuals = load("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
		var origin: Vector3 = visuals.ORIGIN
		for plot in earth_plots(visuals.HOME_LAYOUT):
			for outline in _rim_outlines(plot):
				var world := PackedVector2Array()
				for point in outline: world.append(point+Vector2(origin.x,origin.z))
				_cover.append(world)
	return _cover

## Retalhos na cota EARTH_TOP e anéis que descem dela até o mato (y 0) em RIM metros, com o alfa
## passando da terra para a grama. Cada anel perde a área dos retalhos e dos anéis anteriores:
## nenhuma superfície da vila fica sobre outra (era o anel a 2 cm sob o retalho a 2,2 cm).
static func _graded_ground(parent: Node3D,plots: Array[PackedVector2Array],material: Material) -> void:
	var outlines: Array[PackedVector2Array] = []
	var outline_owner: Array[int] = []
	for i in plots.size():
		_flat(parent,"VillageEarth%d"%i,plots[i],material,EARTH_TOP)
		for outline in _rim_outlines(plots[i]):
			outlines.append(outline)
			outline_owner.append(i)
	var plot_bounds: Array[Rect2] = []
	for plot in plots: plot_bounds.append(GROUND_CUT.bounds(plot).grow(RIM))
	var outline_bounds: Array[Rect2] = []
	for outline in outlines: outline_bounds.append(GROUND_CUT.bounds(outline).grow(.01))
	var taken: Array[PackedVector2Array] = plots.duplicate()
	for k in outlines.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vertices := 0
		for piece in GROUND_CUT.subtract_exact([outlines[k]],taken):
			piece = GROUND_CUT._without_degenerate_edges(piece)
			if piece.size() < 3: continue
			var indices := Geometry2D.triangulate_polygon(piece)
			for i in range(0,indices.size(),3):
				var triangle := PackedVector3Array()
				var alphas := PackedFloat32Array()
				for corner in 3:
					var p: Vector2 = piece[indices[i+corner]]
					var fade := _fade(p,plots,plot_bounds,outlines,outline_bounds)
					triangle.append(Vector3(p.x,EARTH_TOP*(1.0-fade),p.y))
					alphas.append(1.0-fade)
				# Face da frente no sentido horário (normal para cima), como os pisos do Harbor.
				var order := [0,1,2] if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).y <= 0 else [0,2,1]
				for corner: int in order:
					surface.set_normal(Vector3.UP)
					surface.set_color(Color(1,1,1,alphas[corner]))
					surface.add_vertex(triangle[corner])
					vertices += 1
		taken.append(outlines[k])
		if vertices == 0: continue
		var rim := MeshInstance3D.new()
		rim.name="VillageEarth%dVerge%d"%[outline_owner[k],k]
		rim.mesh=surface.commit()
		rim.material_override=material
		rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(rim)

## 0 na borda de qualquer retalho (encosta na terra na mesma cota), 1 no contorno externo de
## qualquer anel (encosta no mato recortado, sem degrau), distância/RIM no meio. As duas regras
## dependem só do ponto, então anéis vizinhos dão a mesma altura no vértice que dividem.
static func _fade(p: Vector2,plots: Array[PackedVector2Array],plot_bounds: Array[Rect2],outlines: Array[PackedVector2Array],outline_bounds: Array[Rect2]) -> float:
	var nearest := RIM
	for k in plots.size():
		if plot_bounds[k].has_point(p): nearest = minf(nearest,p.distance_to(_closest(p,plots[k])))
	if nearest < .002: return 0.0
	for k in outlines.size():
		if outline_bounds[k].has_point(p) and p.distance_to(_closest(p,outlines[k])) < .002: return 1.0
	return clampf(nearest/RIM,0,1)

static func _track_site(village: Node3D) -> void:
	var sync := func() -> void: _set_site_shown(village,village.is_inside_tree() and village.is_visible_in_tree())
	village.tree_entered.connect(sync)
	village.visibility_changed.connect(sync)
	village.tree_exiting.connect(func() -> void: _set_site_shown(village,false))
	if village.is_inside_tree(): sync.call()

static func _set_site_shown(village: Node3D,shown: bool) -> void:
	if shown == site_shown: return
	site_shown = shown
	if village.is_inside_tree(): village.get_tree().call_group(STANDIN_GROUP,"set_visible",not shown)

static func _path(plots: Array[PackedVector2Array],points: PackedVector2Array,width: float) -> void:
	plots.append_array(Geometry2D.offset_polyline(points,width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND))

static func _patch(parent: Node3D,label: String,points: PackedVector2Array,material: Material,y: float) -> void:
	# A short opaque transition ring inherits the exact surrounding grass texture.
	_flat(parent,label,points,material,y)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area := 0.0
	for i in points.size(): area+=points[i].cross(points[(i+1)%points.size()])
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		var outward := Vector2((b-a).y,-(b-a).x).normalized()*1.2*signf(area)
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([a,b,b+outward,a+outward])]
		# Short fans close convex corners without bridges across concave paths.
		for side in 8:
			pieces.append(PackedVector2Array([a,a+Vector2.from_angle(side*TAU/8)*1.2,a+Vector2.from_angle((side+1)*TAU/8)*1.2]))
		for piece in pieces:
			for outside in Geometry2D.clip_polygons(piece,points):
				for index in Geometry2D.triangulate_polygon(outside):
					var p: Vector2 = outside[index]
					surface.set_normal(Vector3.UP)
					surface.set_color(Color(1,1,1,clampf(1.0-p.distance_to(_closest(p,points))/1.2,0,1)))
					surface.add_vertex(Vector3(p.x,y-.002,p.y))
	var rim := MeshInstance3D.new()
	rim.name=label+"Verge"
	rim.mesh=surface.commit()
	rim.material_override=material
	rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(rim)

static func _closest(point: Vector2,polygon: PackedVector2Array) -> Vector2:
	var closest := polygon[0]
	var distance := INF
	for i in polygon.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
		if point.distance_squared_to(candidate)<distance:
			distance=point.distance_squared_to(candidate)
			closest=candidate
	return closest

static func _flat(parent: Node3D,label: String,polygon: PackedVector2Array,material: Material,y: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(polygon):
		var p := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_color(Color.WHITE)
		surface.set_uv(p*.4)
		surface.add_vertex(Vector3(p.x,y,p.y))
	var display := MeshInstance3D.new()
	display.name=label
	display.mesh=surface.commit()
	display.material_override=material
	display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(display)
