extends Node3D
## The same authored/generated rocks as the playable desert. Their visible
## silhouettes live with the region; streamed cells retain the matching solids.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const AREA := Rect2(-1012,-1230,1452,502)
const FORMS=preload("res://world/desert/DesertHorizonRelief.gd")
const RELIEF=preload("res://world/desert/DesertTerrainRelief.gd")
var outcrop_cells := {}
var formations: Array[Dictionary]=[]

func configure(region: Node3D) -> void:
	name="DragScenery"
	for x in range(floori(AREA.position.x/96.0),ceili(AREA.end.x/96.0)):
		for z in range(floori(AREA.position.y/96.0),ceili(AREA.end.y/96.0)):
			var key := Vector2i(x,z)
			if posmod(x*7+z*3,9)!=0: continue
			var center := (Vector2(key)+Vector2.ONE*.5)*96.0
			if RELIEF.BOUNDS.grow(34).has_point(center) or not region._decoration_clear(center,34.0): continue
			var at := Vector3(center.x,region._ground_height(center),center.y)
			FORMS.create_outcrop(self,at,28.0,23.0,absi(x*771+z*331),false)
			outcrop_cells[key]=true
	# The long gap between the strip and the distant escarpment needs a middle
	# distance. Use flat, unreserved ground; roads, quests and the salt pan win.
	for band in 8:
		var placed := false
		var radius := 22.0+float(band%3)*3.0
		for along in [0.0,-35.0,35.0]:
			if placed: break
			for step in 6:
				var depth: float=[-940.0,-970.0,-1090.0,-1140.0,-1170.0,-1190.0][posmod(band*5+step,6)]
				var center := Vector2(-890.0+float(band)*160.0+along,depth)
				if not LAYOUT.BOUNDS.grow(-radius-4.0).has_point(center) or not region._decoration_clear(center,radius+4.0): continue
				var low: float=region._ground_height(center)
				var high := low
				for corner in 8:
					var at: Vector2=center+Vector2.from_angle(float(corner)*TAU/8.0)*radius*.85
					var ground: float=region._ground_height(at)
					low=minf(low,ground)
					high=maxf(high,ground)
				if high-low>1.2: continue
				var record := {"position":Vector3(center.x,low-.15,center.y),"radius":radius,"height":18.0+float(posmod(band*7,13)),"seed":72813+band*1291}
				formations.append(record)
				FORMS.create_outcrop(self,record.position,radius,record.height,record.seed,false)
				placed=true
				break

func owns_outcrop(key: Vector2i) -> bool:
	return outcrop_cells.has(key)

func reservation_clear(point: Vector2, radius: float) -> bool:
	for record in formations:
		var at: Vector3=record.position
		if point.distance_to(Vector2(at.x,at.z))<float(record.radius)+radius+3.0: return false
	return true

func build_collision(chunk: Node3D, rect: Rect2) -> void:
	for record in formations:
		var at: Vector3=record.position
		if rect.has_point(Vector2(at.x,at.z)):
			FORMS.create_outcrop(chunk,at,record.radius,record.height,record.seed,true,false)
