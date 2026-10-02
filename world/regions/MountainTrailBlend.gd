extends RefCounted
## One union mask on the terrain: crossings never stack translucent road quads.
const CELL := 64.0
const STEP := 0.5
const SIZE := 129
var cells: Dictionary = {}

func configure(roads: Array) -> void:
	cells.clear()
	for road in roads:
		var points: PackedVector3Array = road.points
		var asphalt: bool = road.get("surface", "asphalt") == "asphalt"
		var half: float = float(road.width)*0.5
		var outer := half + (1.65 if asphalt else 1.4)
		var inner := half + 0.25 if asphalt else half*0.65
		for i in range(points.size()-1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i+1].x, points[i+1].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(outer)
			var first := Vector2i((bounds.position/CELL).floor())
			var last := Vector2i((bounds.end/CELL).floor())
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					var key := Vector2i(x,y)
					if not cells.has(key): cells[key] = []
					cells[key].append({"a":a,"b":b,"inner":inner,"outer":outer,"bounds":bounds})

func image_for(rect: Rect2) -> Image:
	var values := PackedByteArray()
	values.resize(SIZE*SIZE)
	for segment in cells.get(Vector2i((rect.position/CELL).floor()),[]):
		var bounds: Rect2 = segment.bounds.intersection(rect)
		var first := Vector2i(((bounds.position-rect.position)/STEP).floor()).clamp(Vector2i.ZERO,Vector2i(SIZE-1,SIZE-1))
		var last := Vector2i(((bounds.end-rect.position)/STEP).ceil()).clamp(Vector2i.ZERO,Vector2i(SIZE-1,SIZE-1))
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var point := rect.position+Vector2(x,y)*STEP
				var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b))
				var weight := 1.0-smoothstep(float(segment.inner),float(segment.outer),distance)
				var index := y*SIZE+x
				values[index] = maxi(values[index],roundi(weight*255.0))
	return Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_R8,values)
