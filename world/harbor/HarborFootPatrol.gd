extends "res://police/PoliceOfficer.gd"
var patrol_route := PackedVector2Array()
var patrol_index := 0
var alerted := false
var lost_sight := 0.0
var _patrol_logic_elapsed := 0.0
var _wanted_scan_elapsed := 0.0
const PATROL_LOGIC_INTERVAL := 1.0 / 30.0
const WANTED_SCAN_INTERVAL := 0.25
const WANTED_SIGHT_RANGE := 430.0

func _ready() -> void:
	set_meta("quiet_patrol",true)
	super._ready()
	collision_layer=4
	collision_mask=3
	add_to_group("foot_patrol")
	get_node("/root/WantedManager").crime_reported.connect(_on_crime)

func _on_crime(_severity: int) -> void:
	_try_engage_wanted_suspect()

func _try_engage_wanted_suspect() -> bool:
	if is_dead: return false
	var wanted := get_node("/root/WantedManager")
	if wanted.current_stars <= 0: return false
	var suspect: Node2D = wanted.get_suspect_actor()
	if not is_instance_valid(suspect) or global_position.distance_to(suspect.global_position) > WANTED_SIGHT_RANGE: return false
	target = suspect
	if not wanted.report_visual_contact(self):
		target = null
		return false
	alerted = true
	lost_sight = 0.0
	return true

func _physics_process(delta: float) -> void:
	if is_dead or is_flying:
		super._physics_process(delta)
		return
	var wm := get_node("/root/WantedManager")
	if alerted:
		if is_instance_valid(target) and _has_target_sight():
			lost_sight=0
			wm.report_visual_contact(self)
		else: lost_sight+=delta
		if wm.current_stars==0 or lost_sight>8:
			alerted=false
			target=null
			_reset_arrest_warning()
		else:
			viewport_3d.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
			super._physics_process(delta)
			return
	elif wm.current_stars > 0:
		# A patrulha já presente na rua também entra numa perseguição que começou
		# longe dela. A consulta cadenciada evita raycasts de visão a cada frame.
		_wanted_scan_elapsed += delta
		if _wanted_scan_elapsed >= WANTED_SCAN_INTERVAL:
			_wanted_scan_elapsed = 0.0
			if _try_engage_wanted_suspect():
				super._physics_process(delta)
				return
	else:
		_wanted_scan_elapsed = 0.0
	# Patrulha ambientada mantém colisão e deslocamento a cada tick, mas não
	# precisa refazer rota, cruzamento e consulta de procurado a 60 Hz. Crime,
	# visão e perseguição continuam no caminho integral acima.
	_patrol_logic_elapsed += delta
	if _patrol_logic_elapsed < PATROL_LOGIC_INTERVAL:
		move_and_slide()
		return
	var logic_delta := _patrol_logic_elapsed
	_patrol_logic_elapsed = 0.0
	if patrol_route.size()<2: return
	var goal := patrol_route[patrol_index]
	if global_position.distance_to(goal)<12:
		patrol_index=(patrol_index+1)%patrol_route.size()
		goal=patrol_route[patrol_index]
	velocity=_navigate_towards(goal,34,logic_delta)
	if preload("res://world/harbor/HarborPedestrianRoutes.gd").crossing_wait(self,goal): velocity=Vector2.ZERO
	move_and_slide()
	if velocity.length()>1:
		model_root.rotation.y=-velocity.angle()-PI*.5
		walk_clock+=delta*5
	left_upper_leg.rotation.x=sin(walk_clock)*.3 if velocity.length()>1 else 0.0
	right_upper_leg.rotation.x=-left_upper_leg.rotation.x
	var viewer := get_tree().get_first_node_in_group("player") as Node2D
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if viewer and viewer.global_position.distance_to(global_position)<900 else SubViewport.UPDATE_DISABLED
