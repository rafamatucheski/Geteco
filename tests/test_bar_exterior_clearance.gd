extends SceneTree
## Protege o lote do Lastro contra o mapa salvo efetivo, não só o JSON de origem.
const BAR := preload("res://world/places/bars/BarCatalog.gd")
const PARKING := preload("res://world/roadside_parking/RoadsideParkingLayout.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
func envelope(point: Vector3) -> PackedVector2Array:
	# Includes 16x12 shell, canopy, physical push threshold and exterior return.
	return polygon(Rect2(point.x-8.1,point.z-6.1,16.2,14.9))
func segment_polygon(a: Vector3,b: Vector3,half_width: float) -> PackedVector2Array:
	var direction := Vector2(b.x-a.x,b.z-a.z).normalized()
	var across := Vector2(-direction.y,direction.x)*half_width
	var start := Vector2(a.x,a.z)-direction*half_width
	var end := Vector2(b.x,b.z)+direction*half_width
	return PackedVector2Array([start-across,end-across,end+across,start+across])
func intersects(a: PackedVector2Array,b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a,b).is_empty()
func run() -> void:
	var loaded := preload("res://world/editing/WorldEditData.gd").read_document()
	check(loaded.error.is_empty(),"effective editor document readable")
	var before := hash(loaded.document)
	var region = load("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var definition := BAR.definition("harbor_bar")
	var parcel := envelope(definition.exterior_position)
	var old := envelope(Vector3(134,0,65))
	var old_conflict := false
	for road: Dictionary in region.roads+region.walkways:
		for i in range(road.points.size()-1):
			var corridor := segment_polygon(road.points[i],road.points[i+1],float(road.width)*.5+3.0)
			check(not intersects(parcel,corridor),"Lastro shell/return clear of effective road+pavement "+str(road.id))
			old_conflict = old_conflict or intersects(old,corridor)
	check(old_conflict,"positive control rejects former parcel on warehouse_way")
	for building: Dictionary in region.buildings:
		if str(building.id) == "LastroBar": continue
		var size: Vector2 = building.size
		var footprint := PackedVector2Array()
		for local in polygon(Rect2(-size*.5,size).grow(1.0)):
			var rotated := local.rotated(-float(building.get("editor_rotation",0)))
			footprint.append(Vector2(building.position.x,building.position.z)+rotated)
		check(not intersects(parcel,footprint),"Lastro clear of effective building "+str(building.id))
	for site: Dictionary in region.get_meta(&"roadside_parking_sites",[]):
		var corners := PackedVector2Array()
		for delta in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
			var point: Vector3=site.edge+site.forward*delta.x*float(site.half_length)+site.outward*delta.y*PARKING.DEPTH
			corners.append(Vector2(point.x,point.z))
		check(not intersects(parcel,corners),"Lastro clear of parking bays "+str(site.id))
		check(not intersects(parcel,segment_polygon(site.approach,site.departure,2.5)),"Lastro clear of parking entry/exit "+str(site.id))
	for reserved: Rect2 in PARKING.HARBOR_RESERVED:
		check(not intersects(parcel,polygon(reserved.grow(1))),"Lastro clear of terminal plaza and approaches")
	for reserved: Rect2 in PARKING._transit_footprints(region):
		check(not intersects(parcel,polygon(reserved.grow(1))),"Lastro clear of effective transit footprint")
	for x in range(9):
		for z in range(9):
			var point := Vector2(definition.exterior_position.x-8.1+x*2.025,definition.exterior_position.z-6.1+z*1.8625)
			var on_land := false
			for shore: PackedVector2Array in region.harbor_ocean.shores:
				if Geometry2D.is_point_in_polygon(point,shore): on_land=true; break
			check(on_land,"Lastro parcel and return on effective shore "+str(point))
	check(hash(preload("res://world/editing/WorldEditData.gd").read_document().document)==before,"saved editor document unchanged")
	region.free()
	print("BAR_EXTERIOR_CLEARANCE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
