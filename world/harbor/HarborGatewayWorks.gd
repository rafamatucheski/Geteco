@tool
extends Node2D

## Construction progress is not permission to enter an unavailable map.
const BOUNDS := Rect2(5750,-4930,500,682)
const AXES := [6120.0]
const WORKERS := [Vector2(5810,-4390),Vector2(6070,-4405),Vector2(6198,-4385)]
var works_complete := false
var _clock := 0.0
var _refresh := 0.0
var _proximity_check := 0.0
var _near := false

func _ready() -> void:
	# Only this cosmetic construction animation survives a cinematic pause;
	# proximity gating still prevents off-screen redraw work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1
	for index in AXES.size():
		var gate_name := "FrontierGate%d" % index
		if has_node(NodePath(gate_name)): continue
		var barrier := StaticBody2D.new()
		barrier.name = gate_name
		barrier.position = Vector2(AXES[index],-4460)
		barrier.collision_layer = 1
		barrier.collision_mask = 0
		var collision := CollisionShape2D.new()
		collision.shape = RectangleShape2D.new()
		collision.shape.size = Vector2(124,14)
		barrier.add_child(collision)
		add_child(barrier)
	queue_redraw()

func set_works_complete(value: bool) -> void:
	if works_complete == value: return
	works_complete = value
	queue_redraw()

func get_focus_position() -> Vector2:
	return to_global(Vector2(6000,-4510))

func get_works_contract() -> Dictionary:
	return {"works_complete":works_complete,"connected":false,"destination_available":false,
		"destination":"future_north_region","bounds":BOUNDS,"coordinate_space":"local",
		"deck_rects":[Rect2(6064,-4910,112,440)],
		"approach_rects":[Rect2(6064,-4470,112,222)],
		"barrier_rects":[Rect2(6058,-4467,124,14)],
		"temporary_return_road_id":"RoadLayout/map2_temporary_return",
		"worker_positions":[] if works_complete else WORKERS.duplicate()}

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or works_complete: return
	_proximity_check -= delta
	if _proximity_check <= 0:
		_proximity_check = 0.5
		var camera := get_viewport().get_camera_2d()
		_near = camera != null and camera.get_screen_center_position().distance_to(get_focus_position()) < 1100
	if not _near: return
	_clock += delta
	_refresh += delta
	if _refresh >= 0.12:
		_refresh = fmod(_refresh,0.12)
		queue_redraw()

func _draw() -> void:
	for x in AXES:
		# A construction apron reaches the north edge of the existing return.
		# It is concrete work access, not a marked/open lane or graph provider.
		draw_rect(Rect2(x-56,-4470,112,222),Color("92978d"))
		for y in range(-4450,-4250,38):
			draw_line(Vector2(x-53,y),Vector2(x+53,y),Color("7a827d"),1)
		for side in [-1.0,1.0]:
			draw_line(Vector2(x+side*54,-4470),Vector2(x+side*54,-4252),Color("b5b4a3"),2)
		# Structural work above existing water, not a second road provider.
		for y in [-4825.0,-4650.0]:
			draw_rect(Rect2(x-65,y,130,25),Color("485b60"))
			draw_rect(Rect2(x-48,y-4,96,15),Color("929c99"))
		var length := 440.0 if works_complete else 150.0
		draw_rect(Rect2(x-56,-4470-length,112,length),Color("acae9e"))
		draw_rect(Rect2(x-47,-4470-length,94,length),Color("343c41"))
		for side in [-1.0,1.0]:
			draw_line(Vector2(x+side*53,-4470-length),Vector2(x+side*53,-4470),Color("ddd5b6"),3)
		if works_complete:
			for y in range(-4880,-4480,48):
				draw_line(Vector2(x,y),Vector2(x,y+24),Color("d9d6bd"),2)
		else:
			for side in [-1.0,1.0]:
				draw_line(Vector2(x+side*39,-4905),Vector2(x+side*39,-4620),Color("6b7777"),8)
			for y in range(-4890,-4615,35):
				draw_line(Vector2(x-55,y),Vector2(x+55,y),Color("ad8b59"),3)
				draw_line(Vector2(x-55,y),Vector2(x+55,y+30),Color("746c57"),2)
		_draw_gate(Vector2(x,-4460))
	if not works_complete:
		_draw_equipment(Vector2(5995,-4350))
		for i in WORKERS.size(): _draw_worker(WORKERS[i],_clock+i*1.7)
		for point in [Vector2(5800,-4345),Vector2(6152,-4325),Vector2(5925,-4400)]:
			draw_rect(Rect2(point,Vector2(25,12)),Color("827460"))
			for offset in [4,12,20]: draw_line(point+Vector2(offset,0),point+Vector2(offset,12),Color("b49a70"),2)

func _draw_gate(center: Vector2) -> void:
	draw_rect(Rect2(center-Vector2(65,10),Vector2(130,20)),Color("4b4942"))
	for offset in range(-58,60,16):
		draw_line(center+Vector2(offset,-7),center+Vector2(offset+9,7),Color("e5b44e"),7)
	for side in [-1.0,1.0]:
		draw_circle(center+Vector2(side*62,0),7,Color("2c3437"))
		draw_circle(center+Vector2(side*62,-2),3,Color("e4aa42"))
	# Closed lock icon: no oversized ground text or localization dependency.
	draw_rect(Rect2(center+Vector2(-7,-11),Vector2(14,15)),Color("e3d5a8"))
	draw_arc(center+Vector2(0,-12),5,PI,TAU,12,Color("e3d5a8"),3)

func _draw_worker(point: Vector2,time: float) -> void:
	draw_circle(point+Vector2(2,3),8,Color(0,0,0,0.25))
	draw_line(point+Vector2(-3,3),point+Vector2(-4,10),Color("28323a"),4)
	draw_line(point+Vector2(3,3),point+Vector2(5,10),Color("28323a"),4)
	draw_rect(Rect2(point+Vector2(-5,-5),Vector2(10,12)),Color("cc8638"))
	draw_line(point+Vector2(-3,-4),point+Vector2(-3,6),Color("ecdb94"),2)
	draw_line(point+Vector2(4,-1),point+Vector2(10,-3+sin(time*2)*3),Color("b49c7c"),3)
	draw_circle(point+Vector2(0,-6),5,Color("e9c65b"))

func _draw_equipment(point: Vector2) -> void:
	for side in [-1.0,1.0]:
		draw_rect(Rect2(point+Vector2(side*15-5,-23),Vector2(10,48)),Color("252b2c"))
	draw_rect(Rect2(point-Vector2(14,20),Vector2(28,39)),Color("bb8838"))
	draw_rect(Rect2(point+Vector2(-10,-16),Vector2(20,18)),Color("334a50"))
	draw_line(point,point+Vector2(12,-38),Color("d2a34c"),7)
	draw_line(point+Vector2(12,-38),point+Vector2(35,-54),Color("d2a34c"),6)
	draw_rect(Rect2(point+Vector2(29,-61),Vector2(21,13)),Color("665b45"))
