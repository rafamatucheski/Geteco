extends RefCounted
## Joint origins preserve the authored transport silhouette. Each moving link
## stays a separate material batch so its mesh and physical volume agree.
static func create(root: Node3D, art: Script, key: String, paint: Color) -> void:
	var swing := _pivot(root,"RearExcavator",Vector3(0,1.10,1.55))
	var boom := _pivot(swing,"Boom",Vector3.ZERO)
	var elbow := Vector3(0,1.8,.8)
	art.beam(boom,"BackhoeBoom",Vector3.ZERO,elbow,.30,key,paint)
	art.beam(boom,"BackhoeRam",Vector3(.19,.25,.05),Vector3(.19,1.5,.70),.08,"hydraulic",Color("bbc0b6"))
	for side in [-1,1]:
		art.beam(boom,"BackhoeHose",Vector3(side*.18,.35,.03),Vector3(side*.18,1.65,.75),.042,"rubber",Color("222820"))
		art.pin(boom,Vector3(side*.20,0,0),.12,.10)
	var dipper := _pivot(boom,"Dipper",elbow)
	var wrist := Vector3(0,-1.8,.55)
	art.beam(dipper,"BackhoeDipper",Vector3.ZERO,wrist,.23,key,paint)
	for side in [-1,1]:
		art.beam(dipper,"BackhoeHose",Vector3(side*.18,-.15,-.05),Vector3(side*.18,-1.5,.47),.042,"rubber",Color("222820"))
		art.pin(dipper,Vector3(side*.20,0,0),.13,.10)
	var bucket := _pivot(dipper,"DiggingBucket",wrist)
	art.box(bucket,"DiggerFloor",Vector3(.85,.14,.70),Vector3(0,-.37,-.10),"metal",Color("595749"))
	art.box(bucket,"DiggerBack",Vector3(.85,.48,.13),Vector3(0,-.12,.20),"metal",Color("595749"))
	for x in [-.37,.37]: art.tapered_box(bucket,"DiggerCheek",Vector3(.12,.52,.70),Vector3(x,-.12,-.10),"metal",Color("595749"),.78)
	art.box(bucket,"DiggerWearLip",Vector3(.85,.10,.16),Vector3(0,-.40,-.43),"worn_steel",Color("7f837d"))
	for x in [-.3,0,.3]: art.box(bucket,"BackTooth",Vector3(.13,.24,.22),Vector3(x,-.55,-.40),"hydraulic",Color("aaa48b"))
	for side in [-1,1]: art.pin(bucket,Vector3(side*.20,0,0),.09,.10)

static func _pivot(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label; pivot.position = at
	parent.add_child(pivot)
	return pivot
