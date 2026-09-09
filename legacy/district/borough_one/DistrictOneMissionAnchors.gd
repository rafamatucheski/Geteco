class_name DistrictOneMissionAnchors
extends Node2D

## Stable, named destinations for future 30-35 minute mission content.  Mission
## scripts should request an anchor by id instead of hardcoding world positions.

const ANCHORS := {
	&"old_market": Vector2(420, 290),
	&"central_docks": Vector2(346, 960),
	&"central_precinct": Vector2(1560, 350),
	&"coastal_overlook": Vector2(1990, 600),
	&"west_service_alley": Vector2(520, 2520),
	&"north_civic_square": Vector2(690, 1680),
	&"rail_freight_yard": Vector2(340, 1840),
	&"viaduct_crossing": Vector2(920, 1740),
	&"south_industrial": Vector2(1900, 2500),
	&"district_two_gateway": Vector2(1480, 3500),
}

var _markers: Dictionary = {}


func _ready() -> void:
	for anchor_id: StringName in ANCHORS:
		var marker := Marker2D.new()
		marker.name = String(anchor_id).to_pascal_case()
		marker.position = ANCHORS[anchor_id]
		marker.add_to_group("district_one_mission_anchor")
		marker.set_meta("anchor_id", anchor_id)
		add_child(marker)
		_markers[anchor_id] = marker


func get_anchor(anchor_id: StringName) -> Marker2D:
	return _markers.get(anchor_id) as Marker2D


func get_anchor_position(anchor_id: StringName) -> Vector2:
	var marker := get_anchor(anchor_id)
	return marker.global_position if marker != null else Vector2.INF
