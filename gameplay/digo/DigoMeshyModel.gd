extends Node3D
## A single imported skinned mesh. Source animations remain in the supplied asset.
const SOURCE := preload("res://assets/digo/digo.glb")
var skeleton: Skeleton3D
var outfit := -1
var material: ShaderMaterial
var shirt_print: Label3D
var _spine := -1
var _rest_rotation := Quaternion.IDENTITY
var _clock := 0.0

func _ready() -> void:
	var imported := SOURCE.instantiate() as Node3D
	add_child(imported)
	scale = Vector3.ONE * (1.76 / 1.70)
	skeleton = imported.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# Lower the A-pose arms in skeleton space; the feet retain the authored rest pose.
	for side in ["Left", "Right"]:
		var bone := skeleton.find_bone("mixamorig_" + side + "Arm")
		var parent := skeleton.get_bone_parent(bone)
		var basis := skeleton.get_bone_global_rest(parent).basis
		var axis := basis.inverse() * Vector3.FORWARD
		var angle := deg_to_rad(32.0 if side == "Left" else -32.0)
		skeleton.set_bone_pose_rotation(bone, Quaternion(axis.normalized(), angle) * skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	_spine = skeleton.find_bone("mixamorig_Spine2")
	_rest_rotation = skeleton.get_bone_pose_rotation(_spine)
	material = ShaderMaterial.new()
	material.shader = preload("res://gameplay/digo/DigoShirt.gdshader")
	material.set_shader_parameter("albedo_texture",preload("res://assets/digo/digo_Image_0.jpg"))
	material.set_shader_parameter("normal_texture",preload("res://assets/digo/digo_Image_2.jpg"))
	material.set_shader_parameter("roughness_texture",preload("res://assets/digo/digo_Image_1.jpg"))
	for mesh: MeshInstance3D in imported.find_children("*","MeshInstance3D",true,false):
		mesh.material_override = material
	var chest := BoneAttachment3D.new()
	chest.bone_name = "mixamorig_Spine2"
	skeleton.add_child(chest)
	shirt_print = Label3D.new()
	shirt_print.name = "ShirtPrint"
	shirt_print.font = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
	shirt_print.font_size = 48
	shirt_print.pixel_size = .00085
	shirt_print.outline_size = 0
	shirt_print.shaded = true
	shirt_print.double_sided = false
	chest.add_child(shirt_print)
	shirt_print.transform = skeleton.get_bone_global_rest(_spine).affine_inverse() * Transform3D(Basis.IDENTITY, Vector3(.015,1.22,.145))
	set_day(2)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-.5,0,-.3),Vector3(1,1.8,.6))
	notifier.screen_entered.connect(func(): set_process(true))
	notifier.screen_exited.connect(func(): set_process(false))
	add_child(notifier)

func set_day(day: int) -> void:
	var next := posmod(day - 2, 3)
	if next == outfit: return
	outfit = next
	material.set_shader_parameter("outfit",outfit)
	material.set_shader_parameter("shirt_color",Color("85837d") if outfit == 1 else Color("23333e"))
	shirt_print.visible = outfit != 0
	shirt_print.text = "Eu amo\nvolkswagen" if outfit == 1 else "saudades\namarok"
	shirt_print.modulate = Color("17191c") if outfit == 1 else Color("eee8dc")

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or global_position.distance_squared_to(camera.global_position) > 35.0 * 35.0: return
	_clock += delta
	skeleton.set_bone_pose_rotation(_spine, _rest_rotation * Quaternion(Vector3.RIGHT, sin(_clock * 1.6) * .006))
