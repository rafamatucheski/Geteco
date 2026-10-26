extends "res://assets/CivilianModel.gd"
## Imported civilian bodies, posed on the actual saddle, grips and footrests.
var bike: Node3D
var _last_left := Vector3.INF
var _last_right := Vector3.INF

func _pose(_dt: float) -> void:
	if pelvis == null or not is_instance_valid(bike): return
	var holds: Dictionary = bike.motorcycle_handholds()
	if not holds.has("Left") or not holds.has("Right"): return
	var left := to_local(holds.Left.origin)
	var right := to_local(holds.Right.origin)
	# The seated body has no walking cycle. Repose only when steering changes;
	# the shared rig driver also skips syncing unchanged joints.
	if left.is_equal_approx(_last_left) and right.is_equal_approx(_last_right): return
	_last_left = left
	_last_right = right
	var seat := to_local(bike.driver_seat_anchor()) + Vector3(0,.95,0)
	# Fit the torso to each body's real arm lengths; never stretch the limbs.
	var lean := .2
	var shift := Vector3.ZERO
	for step in 11:
		lean = .2 + step * .1
		var trial := Transform3D(Basis(Vector3.RIGHT,lean),seat+SPINE_OFFSET)
		shift = Vector3.ZERO
		for i in 2:
			var target := right if i == 0 else left
			var reach := target - trial * _shoulders[i]
			var lengths := _arm_measure(i)
			var correction := reach.normalized() * maxf(0,reach.length()-lengths.x-lengths.y+.025)
			if correction.length() > shift.length(): shift = correction
		if shift.length() < .02: break
	seat += shift.limit_length(.28)
	pelvis.transform = Transform3D(Basis.IDENTITY, seat)
	spine.transform = Transform3D(Basis(Vector3.RIGHT,lean), SPINE_OFFSET)
	head_node.transform = Transform3D(Basis(Vector3.RIGHT,-.10)*Basis.from_scale(_head_scale), NECK)
	var chest := pelvis.transform * spine.transform
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var foot := to_local(bike.visual.to_global(bike._motorcycle_seat + Vector3(-side*.27,.40,-.38)))
		_place_leg(i, Basis.IDENTITY, seat, foot, 0.0)
		var key := "Right" if i == 0 else "Left"
		if not holds.has(key): continue
		var target := to_local(holds[key].origin)
		var arm := _reach_arm(i,chest,target,Vector3(side*.5,-1,-.2))
		upper_arms[i].transform = Transform3D(arm[0],_shoulders[i])
		forearms[i].transform = Transform3D(arm[1],Vector3(0,-_arm_measure(i).x,0))

static func create(vehicle: Node3D, identity: int) -> Node3D:
	var model = load("res://assets/civilians/TrafficMotorcyclist.gd").new()
	model.bike = vehicle
	model.name = "TrafficRider"
	model.appearance_locked = true
	model.appearance_variant = identity
	if str(vehicle.get("archetype")) == "bike_police":
		# The mounted officer uses the same procedural uniform recipe as the
		# dismounted motorcycle PoliceModel, never the civilian body catalogue.
		model.coat_color = Color(.11,.15,.24)
		model.pants_color = model.coat_color.darkened(.25)
		model.wardrobe_overrides = {"female":false,"build":1,"top":6,"bottom":0,"shoe":2,"hat":3,"bag":0,"backpack":false,"glasses":false,"accent":Color("dce2df"),"inner":Color("d9d6cc"),"shoe_color":Color("141416")}
		model.set_meta("police_motorcycle_rider",true)
		model.rotation.y = PI
		model.set_meta("motorcycle_rider",true)
		model.ready.connect(func(): _police_badge(model))
		return model
	preload("res://assets/civilians/CivilianBodyCatalog.gd").apply(model, identity)
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 7919 + 47
	var colors := [Color("20252e"),Color("e1ddd3"),Color("a83930"),Color("315b83"),Color("b99b42")]
	model.body_accessories = [{"kind":"motorcycle_helmet","color":colors[rng.randi_range(0,colors.size()-1)]}]
	if rng.randf() < .4: model.body_accessories.append({"kind":"sunglasses"})
	model.rotation.y = PI
	model.set_meta("motorcycle_rider",true)
	return model

static func _police_badge(model: Node3D) -> void:
	var badge := MeshInstance3D.new()
	badge.name = "OfficerBadge"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.048,.067,.012)
	badge.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c4b568")
	badge.material_override = material
	badge.position = Vector3(-.095,.22,.145)
	model.spine.add_child(badge)
