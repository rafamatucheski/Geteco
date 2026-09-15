extends Node2D
## Finite, unarmed incident on an authored sidewalk; no global crime broadcasts.
const RESIDENT := preload("res://world/harbor/events/StreetIncidentResident.gd")
const OFFICER := preload("res://world/harbor/events/StreetIncidentOfficer.gd")
const SITES := [
	{"id":"cobra_north", "hotspot":true, "point":Vector2(7560,1290), "axis":Vector2.RIGHT},
	{"id":"cobra_south", "hotspot":true, "point":Vector2(7670,2080), "axis":Vector2.RIGHT},
	{"id":"downtown", "hotspot":false, "point":Vector2(1750,1332), "axis":Vector2.RIGHT},
]
var site: Dictionary = SITES[0]
var phase := "approach"
var phase_age := 0.0
var age := 0.0
var complete := false
var suspect: Node2D
var victim: Node2D
var officer: Node2D
var reported := false
var outcome := ""
var _leaving_started := false
var _fading := false

func _ready() -> void:
	position = Vector2.ZERO
	var origin: Vector2 = site.point
	var axis: Vector2 = site.axis
	suspect = RESIDENT.new()
	suspect.name = "StreetSuspect"
	suspect.resident_name = "MATEUS"
	suspect.appearance_variant = 13
	suspect.set_meta("ambient_crime",true)
	suspect.position = origin-axis*145
	suspect.travel_speed = 31
	add_child(suspect)
	suspect.set_route(PackedVector2Array([origin-axis*25]))
	victim = RESIDENT.new()
	victim.name = "StreetWitness"
	victim.resident_name = "HELENA"
	victim.appearance_variant = 34
	victim.position = origin+axis*105
	victim.travel_speed = 25
	add_child(victim)
	victim.model.carrying_bag = true
	victim.set_route(PackedVector2Array([origin]))
	officer = OFFICER.new()
	officer.name = "LocalFootOfficer"
	officer.position = origin-axis*285
	add_child(officer)
	modulate.a = 0
	create_tween().tween_property(self,"modulate:a",1.0,1.8)

func tick(delta: float) -> void:
	if complete: return
	age += delta
	phase_age += delta
	if phase not in ["leaving","finished"]:
		if not is_instance_valid(suspect) or suspect.is_dead or not is_instance_valid(victim) or victim.is_dead or not is_instance_valid(officer) or officer.is_dead:
			_begin_leaving("interrupted")
		elif suspect.panic_timer > 0 or victim.panic_timer > 0:
			_begin_leaving("interrupted")
		elif age > 110:
			_begin_leaving("escaped")
	match phase:
		"approach":
			if suspect.finished and victim.finished:
				suspect.pose("threaten",victim.global_position)
				victim.pose("hands_up",suspect.global_position)
				_set_phase("confrontation")
			elif phase_age > 18: _begin_leaving("blocked")
		"confrontation":
			if phase_age > 4:
				suspect.pose("handover",victim.global_position)
				victim.pose("handover",suspect.global_position)
				_set_phase("handover")
		"handover":
			if phase_age > 2:
				victim.model.carrying_bag = false
				suspect.model.carrying_bag = true
				suspect.model.gesture = "idle"
				suspect.travel_speed = 46
				suspect.set_route(PackedVector2Array([site.point+site.axis*350]))
				victim.pose("call",suspect.global_position)
				_set_phase("calling")
		"calling":
			if phase_age > 5.5:
				reported = true
				officer.target = suspect
				officer.responding = true
				victim.pose("idle",officer.global_position)
				_set_phase("pursuit")
		"pursuit":
			if suspect.arrested:
				# The seized bag leaves with the suspect; no remote teleport to its owner.
				_begin_leaving("arrested")
			elif officer.global_position.distance_to(suspect.global_position) < 115 and officer._has_target_sight():
				suspect.pose("hands_up",officer.global_position)
			elif phase_age > 46: _begin_leaving("escaped")
		"leaving":
			if not _leaving_started and phase_age > 3:
				_leaving_started = true
				if is_instance_valid(officer): officer.return_home()
				if is_instance_valid(victim) and not victim.is_dead:
					victim.model.gesture = "idle"
					victim.set_route(PackedVector2Array([site.point+site.axis*350]))
				if is_instance_valid(suspect) and not suspect.is_dead:
					suspect.travel_speed = 38
					suspect.model.gesture = "idle"
					var exit_point: Vector2 = officer.home_point+site.axis*24 if outcome=="arrested" and is_instance_valid(officer) else site.point+site.axis*350
					suspect.set_route(PackedVector2Array([exit_point]))
			if phase_age > 22 and not _fading:
				_fading = true
				var fade := create_tween()
				fade.tween_property(self,"modulate:a",0.0,2)
				fade.tween_callback(func(): complete=true; phase="finished")

func _set_phase(next: String) -> void:
	phase = next
	phase_age = 0

func _begin_leaving(result: String) -> void:
	if phase == "leaving": return
	outcome = result
	_set_phase("leaving")
	if is_instance_valid(suspect): suspect.set_meta("ambient_crime",false)
	if is_instance_valid(officer): officer.responding = false

func _exit_tree() -> void:
	if is_instance_valid(officer): officer.target = null
