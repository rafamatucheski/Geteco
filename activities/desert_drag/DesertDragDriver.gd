extends RefCounted
## Os retratos dos rivais no mundo são as mesmas pessoas vistas pelo vidro.
const CABIN := preload("res://gameplay/VehicleInterior.gd")
const PEOPLE := preload("res://runtime/desert/DesertCharacter.gd")

static func attach(car: CharacterBody3D, identity: String) -> Node3D:
	CABIN.attach(car)
	var cabin: Dictionary = CABIN.spec(car)
	var model: Node3D
	if identity == "takeshi":
		model = preload("res://gameplay/CobraModel.gd").new()
		model.tier = 2
		model.seated = true
		model.position = Vector3(float(cabin.sx),float(cabin.floor),float(cabin.sz))
		car.add_child(model)
		model.fit_seat(car,cabin,true)
	elif identity == "digo":
		model = preload("res://gameplay/digo/DigoMeshyModel.gd").new()
		car.add_child(model)
		model.rotation.y = PI
		model.position = Vector3(float(cabin.sx),float(cabin.cush)-.91,float(cabin.sz))
		var skeleton: Skeleton3D = model.skeleton
		for side in ["Left","Right"]:
			for piece in ["UpLeg","Leg"]:
				var bone := skeleton.find_bone("mixamorig_"+side+piece)
				if bone < 0: continue
				var bend := -PI*.48 if piece=="UpLeg" else PI*.48
				skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,bend))
	else:
		model = preload("res://gameplay/jessica/JessicaModel.gd").new() if identity=="jessica" else preload("res://assets/CivilianModel.gd").new()
		if identity != "jessica":
			var look: Dictionary = PEOPLE.LOOKS.get(identity,{"variant":12000+absi(identity.hash())%500,"coat":"64727b","pants":"30383e","skin":"bd8d6c","hair":"302721","height":1.0,"build":1,"female":identity in ["open_celia","open_mara"],"hat":0,"beard":0,"glasses":false})
			model.appearance_locked = true
			model.appearance_variant = int(look.variant)
			model.coat_color = Color(look.coat)
			model.pants_color = Color(look.pants)
			model.wardrobe_overrides = {"female":look.female,"height":look.height,"build":look.build,"skin":Color(look.skin),"hair_color":Color(look.hair),"hat":look.hat,"beard":look.beard,"glasses":look.glasses,"bag":0,"backpack":false,"top":1,"bottom":0,"shoe":0}
		preload("res://runtime/desert/drag_meet/DragMeetWardrobe.gd").style_rival(model,identity)
		model.sit_amount = 1.0
		model.seat_height = float(cabin.cush)-float(cabin.floor)
		model.position = Vector3(float(cabin.sx),float(cabin.floor),float(cabin.sz))
		model.rotation.y = PI
		car.add_child(model)
		var hub := Vector3(float(cabin.sx),float(cabin.hub_y),float(cabin.hub_z))
		model.hand_provider = func() -> Array:
			return [car.to_global(hub+Vector3(float(cabin.r)*.8,0,.02)),car.to_global(hub+Vector3(-float(cabin.r)*.8,0,.02))]
	model.name = "DragRivalDriver"
	model.set_meta("character_identity",identity)
	return model
