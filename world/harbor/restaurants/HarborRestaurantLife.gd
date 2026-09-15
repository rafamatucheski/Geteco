extends Node2D
## Outdoor dining follows the world's clock. Tables flank entrances and keep
## their collision footprint even while their presentation is streamed out.
const TERRACE := preload("res://world/harbor/restaurants/RestaurantTerraceView.gd")
const VENUES := [
	{"id":"anchor","hours":Vector2(7,23),"tables":[Vector2(555,1132),Vector2(685,1132)],"fabric":Color("b96a46")},
	{"id":"tideline","hours":Vector2(10,23),"tables":[Vector2(5735,1644),Vector2(5845,1644)],"fabric":Color("477f7d")},
	{"id":"early_shift","hours":Vector2(5,18),"tables":[Vector2(6145,-1238),Vector2(6255,-1238)],"fabric":Color("68784a")},
]
var terraces: Array[Node2D] = []
var world_hour := 12.0
var rain_intensity := 0.0

func _ready() -> void:
	name = "RestaurantLife"
	for venue_index in VENUES.size():
		var venue: Dictionary = VENUES[venue_index]
		for i in 2:
			var table := TERRACE.new()
			table.name = "%sTable%d" % [venue.id.to_pascal_case(),i+1]
			table.venue_id = venue.id
			table.table_index = i
			table.variant = venue_index*2+i
			table.fabric = venue.fabric
			table.position = venue.tables[i]
			add_child(table)
			terraces.append(table)

func update_context(hour: float, rain: float, focus: Vector2, delta: float) -> void:
	world_hour = fposmod(hour,24.0)
	rain_intensity = clampf(rain,0.0,1.0)
	for table in terraces:
		table.update_context(scheduled_guests(table.venue_id,table.table_index,world_hour),rain_intensity,focus,delta)

static func scheduled_guests(venue_id: String, table_index: int, hour: float) -> int:
	hour = fposmod(hour,24.0)
	for venue in VENUES:
		if venue.id != venue_id: continue
		var hours: Vector2 = venue.hours
		# Small stagger avoids a whole block standing/sitting on one clock tick.
		var stagger := table_index*.18
		if hour < hours.x+stagger or hour >= hours.y-stagger: return 0
		var breakfast := hour>=7.0 and hour<10.0
		var lunch := hour>=11.5 and hour<14.5
		var dinner := hour>=18.0 and hour<21.5
		if breakfast or lunch or dinner or table_index == 0: return 2
		return 0
	return 0

func get_status() -> Dictionary:
	var occupied := 0
	var active_views := 0
	for table in terraces:
		occupied += int(table.get_status().guests)
		if table.active: active_views += 1
	return {"hour":world_hour,"rain":rain_intensity,"guests":occupied,"tables":terraces.size(),"active_views":active_views}
