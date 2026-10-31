extends "res://scripts/Actor.gd"
## Passageiro em close: o rig skinned de produção, com identidade mais velha e roupas próprias.
const DRESS := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const GEOMETRY := preload("res://assets/outfits/OutfitGeometry.gd")
var head_bone := -1

func _ready() -> void:
	is_player = true
	outfit_id = "dante_arctic"
	super._ready()
	set_physics_process(false)
	input_locked = true
	collision_layer = 0
	collision_mask = 0
	var cloth := _combat_skin.get_surface_override_material(0) as ShaderMaterial
	var colors: PackedColorArray = cloth.get_shader_parameter("region_tint")
	colors[DRESS.HAIR] = Color("858c87")
	colors[DRESS.SKIN] = Color("c69474")
	colors[DRESS.JACKET] = Color("8c7549")
	colors[DRESS.SHIRT] = Color("303b40")
	colors[DRESS.PANTS] = Color("233039")
	colors[DRESS.BOOTS] = Color("352e28")
	cloth.set_shader_parameter("region_tint",colors)
	var patterns: PackedFloat32Array = cloth.get_shader_parameter("region_pattern")
	patterns[DRESS.HAIR] = .65
	patterns[DRESS.SKIN] = .9
	patterns[DRESS.JACKET] = .04
	cloth.set_shader_parameter("region_pattern",patterns)
	# Troca a gola grande de fábrica por um cachecol de lã ajustado.
	for attachment in skeleton.get_children():
		if attachment.name == "MeshyOutfitneck": attachment.free()
	var spaces := {}
	var head := DRESS._space(skeleton,spaces,"Head")
	var knit := GEOMETRY._make_mat(Color("4a606c"),.95)
	for i in 56:
		var angle := TAU*float(i)/56.0
		var stitch := GEOMETRY._make_tapered_limb(.0018,.0018,.044,knit,Vector3(.004+sin(angle)*.138,1.575,-.025+cos(angle)*.155))
		head.add_child(stitch)
	var frame_material := GEOMETRY._make_mat(Color("534635"),.35,.5)
	# Thin reading-glass frames, eyes remain visible through the open lenses.
	for side in [-1.0,1.0]:
		var frame := DRESS._torus(.023,.026,frame_material,Vector3(side*.036+.004,1.542,.121))
		frame.rotation.x = PI*.5
		frame.scale = Vector3(1.08,1,.82)
		head.add_child(frame)
		head.add_child(GEOMETRY._make_box(Vector3(.003,.003,.10),frame_material,Vector3(side*.064+.004,1.547,.071)))
	head.add_child(GEOMETRY._make_box(Vector3(.023,.003,.004),frame_material,Vector3(.004,1.55,.122)))
	var chest := DRESS._space(skeleton,spaces,"Spine01")
	var brass := GEOMETRY._make_mat(Color("83725c"),.42,.45)
	for y in [1.28,1.22,1.16,1.10]:
		chest.add_child(GEOMETRY._make_ellipsoid(Vector3(.012,.012,.006),brass,Vector3(.016,y,.120)))
	DRESS._scarf(DRESS._space(skeleton,spaces,"neck"),Color("3c555d"))
	head_bone = skeleton.find_bone("Head")

func pose_at(t: float, speaking: bool, delta: float) -> void:
	_idle_clock = t+.8
	_pose_delta = delta
	_apply_pose(_idle_pose)
	_apply_idle_breath()
	if head_bone >= 0:
		var base := skeleton.get_bone_pose_rotation(head_bone)
		skeleton.set_bone_pose_rotation(head_bone,base*Quaternion(Vector3.UP,-.16)*Quaternion(Vector3.RIGHT,sin(t*2.0)*(.024 if speaking else .008)))
		skeleton.set_bone_pose_scale(head_bone,Vector3(.94,.98,1.04))
	_set_combat_grips(false,false,false,false,true,true)
