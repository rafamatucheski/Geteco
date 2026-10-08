extends "res://assets/CivilianModel.gd"
## Production human rig and hand IK. The parent owns the single update clock.
const GEAR := preload("res://world/north_gateway/NorthGatewayWorkerGeometry.gd")
var job := 0
var tool: Node3D
var pencil: Node3D
var work_clock := 0.0

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 340+job*4
	coat_color = [Color("435461"),Color("686956"),Color("385260"),Color("62645e")][job]
	pants_color = [Color("303b45"),Color("39424a"),Color("3b4048"),Color("3b4745")][job]
	wardrobe_overrides = {"female":job==2,"build":1,"height":1.0,"top":1,"bottom":0,"shoe":1,
		"hat":0,"hair":0,"backpack":false,"bag":0,"glasses":job==1,
		"skin":[Color("b97d5d"),Color("e0ac86"),Color("7e4e38"),Color("c89272")][job],
		"shoe_color":Color("453b32"),"beard":1 if job==3 else 0}
	lod_enabled = false
	super._ready()
	set_process(false)
	set_physics_process(false)
	var helmet := GEAR.add(anchor(head_node),"helmet")
	helmet.set_instance_shader_parameter("inner_color",Color("eee7ca") if job==2 else Color("edc348"))
	var vest := GEAR.add(spine,"vest",Vector3.ZERO,job==2)
	vest.set_instance_shader_parameter("accent_color",Color("d4d755") if job==1 else Color("e87b2d"))
	tool = Node3D.new()
	tool.name = "WorkToolPivot"
	add_child(tool)
	GEAR.add(tool,["breaker","hammer","clipboard","wrench"][job])
	if job == 2:
		pencil = Node3D.new()
		pencil.name = "PencilPivot"
		tool.add_child(pencil)
		GEAR.add(pencil,"pencil")
	hand_provider = _work_hands
	sample_work(0.0,0.0)

func sample_work(time: float, delta: float) -> void:
	if not is_instance_valid(tool): return
	work_clock = time+float(job)*1.37
	clock = work_clock
	_speed = 0.0
	_travel = 0.0
	match job:
		0:
			var cycle := fposmod(work_clock,5.4)
			var vibration := sin(work_clock*TAU*8.0)*.004 if cycle < 3.8 else 0.0
			tool.position = Vector3(0,.56+vibration,.4)
			tool.rotation = Vector3.ZERO
		1:
			var swing := fposmod(work_clock,2.7)
			var angle := -.75
			if swing < .80: angle = lerpf(-.75,-.35,smoothstep(0.0,.8,swing))
			elif swing < 1.02: angle = lerpf(-.35,.79,smoothstep(.8,1.02,swing))
			elif swing < 1.3: angle = .79
			else: angle = lerpf(.79,-.75,smoothstep(1.3,2.7,swing))
			tool.position = Vector3(.13,1.12,.335)
			tool.rotation = Vector3(angle,0,0)
		2:
			tool.position = Vector3(0,1.12,.39)
			tool.rotation = Vector3(-.24,.025*sin(work_clock*.7),0)
			var writing := fposmod(work_clock,4.2) < 2.9
			pencil.position = Vector3(.06+.035*sin(work_clock*4.3),.025+(.018 if not writing else 0.0),.02+.025*sin(work_clock*2.1))
		3:
			tool.position = Vector3(0,1.065,.6)
			tool.rotation = Vector3(0,.34*sin(work_clock*1.9),0)
	_pose(delta)
	# A restrained downward glance keeps the action readable with planted feet.
	head_node.rotate_x(.12 if job==2 else .055)

func _work_hands() -> Array:
	match job:
		0: return [tool.to_global(Vector3(-.148,.53,0)),tool.to_global(Vector3(.148,.53,0))]
		1: return [to_global(Vector3(-.16,1.14,.36)),tool.global_position]
		2: return [tool.to_global(Vector3(-.17,0,.015)),pencil.to_global(Vector3(0,.07,0))]
		3: return [to_global(Vector3(-.17,1.10,.385)),tool.to_global(Vector3(0,.02,-.235))]
	return [null,null]
