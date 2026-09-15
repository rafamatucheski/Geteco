class_name MountainSkiArea
extends Node2D

const LAYOUT := preload("res://world/mountain_pass/MountainSkiLayout.gd")
const GROUND := preload("res://world/mountain_pass/MountainGroundMaterials.gd")
const TOWER_SCRIPT := preload("res://world/mountain_pass/MountainChairliftTower.gd")
const CHAIR_SCRIPT := preload("res://world/mountain_pass/MountainChairliftChair.gd")
const GATE_SCRIPT := preload("res://world/mountain_pass/MountainSkiGate.gd")
const RACE_SCRIPT := preload("res://world/mountain_pass/SkiRaceController.gd")
const LIFT_SCRIPT := preload("res://world/mountain_pass/MountainSkiLift.gd")
const SKIER_SCRIPT := preload("res://world/mountain_pass/MountainSkier.gd")
const RESIDENT_SCRIPT := preload("res://world/mountain_pass/WinterResident.gd")
const TREE_SCRIPT := preload("res://world/mountain_pass/MountainPine3D.gd")

var region_ready := false
var chairlift_chairs: Array = []

func _ready() -> void:
	add_to_group("mountain_ski_area")
	z_index = 1
	_build_pistes()
	_build_lift()
	_build_skiers()
	_build_trees()
	_build_operators()
	region_ready = true

func downhill_at(global_point: Vector2) -> Vector2:
	return LAYOUT.closest_downhill_direction(to_local(global_point))

func _build_pistes() -> void:
	var colors := [Color("78a95c"), Color("5286ad"), Color("333b42")]
	for course_index in LAYOUT.COURSES.size():
		var course: Dictionary = LAYOUT.COURSES[course_index]
		var points := LAYOUT.all_course_points(course)
		var piste := Line2D.new()
		piste.name = "Piste_" + String(course.id)
		piste.z_index = -1
		piste.width = 128.0 if course_index < 2 else 104.0
		piste.joint_mode = Line2D.LINE_JOINT_ROUND
		piste.begin_cap_mode = Line2D.LINE_CAP_ROUND
		piste.end_cap_mode = Line2D.LINE_CAP_ROUND
		piste.default_color = Color("c8d4d7") if course_index < 2 else Color("aebbc0")
		piste.points = points
		piste.set_meta("ski_course_id", course.id)
		add_child(piste)
		GROUND.apply(piste, "snow")
		for point_index in points.size():
			var gate := GATE_SCRIPT.new()
			gate.name = "Gate_%s_%02d" % [course.id, point_index]
			gate.accent = colors[course_index]
			gate.position = points[point_index]
			var next_point := points[mini(point_index + 1, points.size() - 1)]
			var previous := points[maxi(0, point_index - 1)]
			gate.ground_angle = previous.direction_to(next_point).angle() + PI * 0.5
			add_child(gate)
		var race := RACE_SCRIPT.new()
		race.name = "Race_" + String(course.id)
		race.setup(course)
		add_child(race)

func _build_lift() -> void:
	var cable := Line2D.new()
	cable.name = "ChairliftCable"
	cable.z_index = 3
	cable.width = 2.4
	cable.default_color = Color("2e3840")
	cable.points = PackedVector2Array(LAYOUT.LIFT_CABLE_POINTS)
	add_child(cable)
	# The centre polyline remains the travel geometry; both visible cable lanes
	# use exactly the same offset as the chairs' grip anchor.
	cable.default_color.a = 0.0
	var across := cable.points[-1].direction_to(cable.points[0]).orthogonal()*14.0
	for side in [-1,1]:
		var lane := Line2D.new()
		lane.name = "LiftCableLane%d"%side
		lane.width = 1.8
		lane.z_index = 3
		lane.default_color = Color("2e3840")
		for point in cable.points: lane.add_point(point+across*side)
		add_child(lane)

	# 1. Torres 3D estruturais dedicadas
	for index in cable.points.size():
		if index in [1, 2]:
			var tower := TOWER_SCRIPT.new()
			tower.name = "LiftTower%d" % index
			tower.tower_number = index
			tower.position = cable.points[index]
			add_child(tower)

	# 2. Estação do Cume (Summit)
	var summit := LIFT_SCRIPT.new()
	summit.name = "SummitLiftStation"
	summit.position = LAYOUT.LIFT_SUMMIT
	add_child(summit)

	# 3. Estação da Base
	var base := LIFT_SCRIPT.new()
	base.name = "BaseLiftStation"
	base.is_base_station = true
	base.position = LAYOUT.LIFT_BASE
	add_child(base)

	# 4. Cadeirinhas 3D móveis circulando continuamente pelo cabo
	var chair_configs := [
		{"progress": 0.12, "asc": true, "rider": true, "color": Color("c95444")},
		{"progress": 0.35, "asc": false, "rider": false, "color": Color.WHITE},
		{"progress": 0.58, "asc": true, "rider": true, "color": Color("387799")},
		{"progress": 0.78, "asc": false, "rider": false, "color": Color.WHITE},
		{"progress": 0.92, "asc": true, "rider": true, "color": Color("d2a844")}
	]
	for i in chair_configs.size():
		var cfg = chair_configs[i]
		var chair := CHAIR_SCRIPT.new()
		chair.name = "ChairliftChair%d" % i
		add_child(chair)
		chair.setup(cable.points, cfg.progress, cfg.asc, cfg.rider, cfg.color)
		chairlift_chairs.append(chair)

func _build_skiers() -> void:
	var colors := [Color("b54d43"), Color("3e7189"), Color("c09b4f"), Color("6d5685"), Color("47705a"), Color("d17a48")]
	var index := 0
	for course in LAYOUT.COURSES:
		var points := LAYOUT.all_course_points(course)
		for lane in 2:
			var shifted := PackedVector2Array()
			# Old +/-22 offsets ran directly into gate posts (+/-20.7 pixels).
			# Approach guides prevent cutting across a post on each bend.
			for gate_index in points.size():
				var tangent := points[maxi(0,gate_index-1)].direction_to(points[mini(points.size()-1,gate_index+1)])
				var center := points[gate_index]+tangent.orthogonal()*((lane*2-1)*3.0)
				for along in [-85.0,0.0,85.0]: shifted.append(center+tangent*along)
			# Longitudinal separation keeps both skiers within the narrowest
			# projected gate opening. Their waiting places fan out after it.
			shifted[0] -= points[0].direction_to(points[1])*lane*150.0
			shifted[-1] += points[-2].direction_to(points[-1]).orthogonal()*((lane*2-1)*11.0)
			var skier := SKIER_SCRIPT.new()
			skier.name = "AmbientSkier%02d" % index
			skier.configure(shifted, 155.0 + float(index/2)*28.0, colors[index % colors.size()], index)
			add_child(skier)
			index += 1

func _build_trees() -> void:
	var candidate_positions: Array[Vector2] = []
	for y_step in range(12):
		var y := -3120.0 - float(y_step) * 145.0
		candidate_positions.append(Vector2(6260.0, y))
		candidate_positions.append(Vector2(7960.0, y))
		for x in [6780.0,7360.0]: candidate_positions.append(Vector2(x+sin(y*.011)*55.0,y))

	for pos in candidate_positions:
		var safe := pos.distance_to(LAYOUT.LIFT_SUMMIT)>180 and pos.distance_to(LAYOUT.LIFT_BASE)>180
		# Keep the projected crown clear of the suspended cable corridor.
		for segment in LAYOUT.LIFT_CABLE_POINTS.size()-1:
			if Geometry2D.get_closest_point_to_segment(pos,LAYOUT.LIFT_CABLE_POINTS[segment],LAYOUT.LIFT_CABLE_POINTS[segment+1]).distance_to(pos)<100: safe = false
		for course in LAYOUT.COURSES:
			var points := LAYOUT.all_course_points(course)
			for i in range(points.size() - 1):
				var center := Geometry2D.get_closest_point_to_segment(pos, points[i], points[i + 1])
				if center.distance_to(pos) < 155.0:
					safe = false
					break
			if not safe:
				break
		if safe:
			var tree := TREE_SCRIPT.new()
			tree.name = "SkiBoundaryTree%d" % get_child_count()
			tree.position = pos
			tree.is_snowy = true
			tree.variant_seed = int(pos.x*43+pos.y*71)
			tree.tree_scale = randf_range(1.1, 1.4)
			tree.add_to_group("ski_boundary_tree")
			add_child(tree)

func _build_operators() -> void:
	# Operador da Base
	var base_op := RESIDENT_SCRIPT.new()
	base_op.name = "BaseLiftOperator"
	base_op.position = LAYOUT.LIFT_BASE + Vector2(-60, 25)
	base_op.resident_name = "RODRIGO"
	base_op.role = "ranger"
	base_op.coat_color = Color("2c4a5e")
	base_op.is_stationary = true
	base_op.lines = [
		"Embarque liberado. Puxe a barra de proteção assim que sentar.",
		"O teleférico opera até as 18:00."
	]
	base_op.home = base_op.position
	base_op.destination = base_op.position
	add_child(base_op)

	# Operador do Cume
	var summit_op := RESIDENT_SCRIPT.new()
	summit_op.name = "SummitLiftOperator"
	summit_op.position = LAYOUT.LIFT_SUMMIT + Vector2(65, 35)
	summit_op.resident_name = "TIAGO"
	summit_op.role = "ranger"
	summit_op.coat_color = Color("2c4a5e")
	summit_op.is_stationary = true
	summit_op.lines = [
		"Cuidado ao desembarcar na rampa de neve.",
		"Pistas abertas: Verde para iniciantes, Azul e Preta à direita."
	]
	summit_op.home = summit_op.position
	summit_op.destination = summit_op.position
	add_child(summit_op)
