extends RefCounted
## Exact opaque floor footprints of existing Harbor facades. Only the underlying
## city finish is cut; authored access heights and physical support stay intact.
const CUT := preload("res://world/urban_detail/GroundCut.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")

static func footprints() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for definition in CATALOG.definitions():
		if definition.region != "harbor": continue
		var rects: Array[Rect2] = []
		if definition.id == "harbor_hospital":
			# The two ambulance/public forecourt boxes in HarborHospitalModel3D.
			var projection := Vector2(18.0, 18.0 * .76822128)
			rects.append(Rect2(Vector2(30,6)/projection, Vector2(100,68)/projection))
			rects.append(Rect2(Vector2(104,-19)/projection, Vector2(34,136)/projection))
		elif definition.id == "harbor_ammunation":
			# UrbanBuildingFactory fits this model to its authored 230x180 px lot.
			var stretch := Vector2(230.0/16.0/8.7,180.0/16.0/4.7)
			rects.append(Rect2(Vector2(-4.35,1.975)*stretch,Vector2(8.7,1.35)*stretch))
		elif definition.id == "cemetery_keeper":
			rects.append(Rect2(-3.8,-2.95,7.6,5.9))
			rects.append(Rect2(-.8,2.745,1.6,.65))
		elif definition.id in ["westgate_garden", "quayside_house", "canal_north"]:
			# Foundation includes the thin floor strip kept by WalkupFacadeDoor.
			rects.append(Rect2(-4.7,-3.3,9.4,6.6))
			rects.append(Rect2(-1.1,3.12,2.2,.9))
			var offset := preload("res://world/places/ResidenceParking.gd").placement(int(definition.variant))
			rects.append(Rect2(Vector2(4.9,-3.7)+Vector2(offset.x,offset.z),Vector2(5.8,7.6)))
		if rects.is_empty(): continue
		var scale: Vector3 = definition.get("editor_scale",Vector3.ONE)
		var transform := Transform3D(Basis(Vector3.UP,float(definition.get("editor_rotation",0.0)))*Basis.from_scale(scale),definition.exterior_position)
		for rect in rects:
			var polygon := PackedVector2Array()
			for point in CUT.rect_polygon(rect):
				var world := transform * Vector3(point.x,0,point.y)
				polygon.append(Vector2(world.x,world.z))
			result.append(polygon)
	# Match CylinderMesh's 32-sided perimeter, rather than a square hole.
	var compass := PackedVector2Array()
	for index in 32:
		compass.append(Vector2(380,62.5)+Vector2.from_angle(float(index)*TAU/32.0)*2.875)
	result.append(compass)
	return result
