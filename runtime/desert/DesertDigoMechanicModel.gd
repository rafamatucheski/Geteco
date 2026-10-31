extends "res://gameplay/digo/DigoMeshyModel.gd"
## A malha fornecida do Digo mantém o rosto e as proporções; só esta instância
## do deserto usa roupa de trabalho e recebe a pose procedural da oficina.
const G := preload("res://world/desert/DesertGeometry.gd")
var activity := "repair"
var speed := 0.0
var frozen := false
var pose_clock := 0.0
var _phase := 0.0
var _work_weight := 0.0
var _walk_weight := 0.0
var _bone_rest: Dictionary = {}
var _tool: Node3D

func _ready() -> void:
	super._ready()
	material.shader=preload("res://runtime/desert/digo_mechanic.gdshader")
	material.set_shader_parameter("albedo_texture",preload("res://assets/digo/digo_Image_0.jpg"))
	material.set_shader_parameter("normal_texture",preload("res://assets/digo/digo_Image_2.jpg"))
	material.set_shader_parameter("roughness_texture",preload("res://assets/digo/digo_Image_1.jpg"))
	material.set_shader_parameter("outfit",2)
	material.set_shader_parameter("shirt_color",Color("334755"))
	shirt_print.hide()
	for bone_name in ["Hips","Spine","Spine1","Spine2","Head","LeftArm","RightArm","LeftForeArm","RightForeArm","LeftUpLeg","RightUpLeg","LeftLeg","RightLeg"]:
		var index := skeleton.find_bone("mixamorig_"+bone_name)
		if index >= 0: _bone_rest[bone_name] = {"index":index,"rotation":skeleton.get_bone_pose_rotation(index)}
	var chest := _attachment("Spine2")
	G.box(chest,"WorkApronBib",Vector3(0,1.20,.152),Vector3(.31,.35,.032),Color("263845"))
	for side in [-1.0,1.0]:
		G.box(chest,"ApronStrap",Vector3(side*.125,1.38,.13),Vector3(.035,.19,.03),Color("445766"))
		G.box(chest,"ChestPocket",Vector3(side*.087,1.24,.174),Vector3(.11,.105,.018),Color("425462"))
	var waist := _attachment("Hips")
	G.box(waist,"MechanicApron",Vector3(0,.88,.18),Vector3(.35,.35,.035),Color("263845"))
	G.box(waist,"ToolBelt",Vector3(0,1.045,.165),Vector3(.42,.052,.038),Color("6d5340"))
	G.box(waist,"ToolPouch",Vector3(-.18,.94,.185),Vector3(.095,.16,.06),Color("534a3a"))
	G.box(waist,"PocketRag",Vector3(.14,.965,.202),Vector3(.08,.17,.014),Color("b4a58a"))
	_tool = _attachment("RightHand")
	_tool.transform=Transform3D.IDENTITY
	G.box(_tool,"SpannerHandle",Vector3(0,.045,0),Vector3(.028,.018,.21),Color("adb3b4"))
	G.box(_tool,"SpannerJaw",Vector3(0,.045,-.11),Vector3(.065,.02,.045),Color("adb3b4"))
	# Os acessórios usam o mesmo buffer de profundidade e esqueleto; sem viewport de ator.
	set_meta("desert_mechanic_clothes",true)
	_work_weight=1.0

func _attachment(bone_name: String) -> Node3D:
	var bone := skeleton.find_bone("mixamorig_"+bone_name)
	var attachment := BoneAttachment3D.new()
	attachment.bone_idx=bone
	skeleton.add_child(attachment)
	var authoring := Node3D.new()
	authoring.transform=skeleton.get_bone_global_rest(bone).affine_inverse()
	attachment.add_child(authoring)
	return authoring

func _process(delta: float) -> void:
	if frozen or _bone_rest.is_empty(): return
	pose_clock+=delta
	_phase+=maxf(speed,0.0)*delta*4.5
	_walk_weight=move_toward(_walk_weight,clampf(speed/1.05,0,1),delta*5)
	_work_weight=move_toward(_work_weight,1.0 if activity in ["repair","tools"] else 0.0,delta*3)
	var stride := sin(_phase)*.32*_walk_weight
	var wrench := sin(pose_clock*3.0)*.07*_work_weight
	var talk := sin(pose_clock*2.4)*.14 if activity=="talk" else 0.0
	var lean := .21 if activity=="repair" else .12
	_pose_bone("Spine",Vector3.RIGHT,lean*_work_weight)
	_pose_bone("Spine2",Vector3.RIGHT,.14*_work_weight+sin(pose_clock*1.6)*.005)
	_pose_bone("Head",Vector3.RIGHT,-.08*_work_weight+talk*.25)
	_pose_bone("LeftUpLeg",Vector3.RIGHT,stride)
	_pose_bone("RightUpLeg",Vector3.RIGHT,-stride)
	_pose_bone("LeftLeg",Vector3.RIGHT,-maxf(0,-stride)*.65)
	_pose_bone("RightLeg",Vector3.RIGHT,-maxf(0,stride)*.65)
	_pose_bone("LeftArm",Vector3.RIGHT,-stride*.7-.85*_work_weight)
	_pose_bone("RightArm",Vector3.RIGHT,stride*.7-.95*_work_weight-talk)
	_pose_bone("LeftForeArm",Vector3.RIGHT,-.35*_work_weight)
	_pose_bone("RightForeArm",Vector3.RIGHT,-.54*_work_weight+wrench-talk)
	_tool.visible=activity in ["repair","tools"]

func _pose_bone(bone_name: String, axis: Vector3, angle: float) -> void:
	if not _bone_rest.has(bone_name): return
	var row: Dictionary=_bone_rest[bone_name]
	var index: int=row.index
	var parent := skeleton.get_bone_parent(index)
	var local_axis := skeleton.get_bone_global_rest(parent).basis.inverse()*axis
	skeleton.set_bone_pose_rotation(index,Quaternion(local_axis.normalized(),angle)*row.rotation)
