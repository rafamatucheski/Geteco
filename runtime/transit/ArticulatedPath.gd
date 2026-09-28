extends RefCounted
## Precomputed drawbar kinematics, shared by the fleet. No per-frame path baking.
const LENGTHS := [7.8,6.8,6.8]
const GAP := .65
var route: Curve3D
var samples: Array = []
var spacing := .25
var count := 0
func configure(value: Curve3D) -> void:
	route = value
	var length := route.get_baked_length()
	count = ceili(length/.25)
	spacing = length/count
	var poses: Array[Transform3D] = []
	for index in 3:
		var pose := front(-index*7.8)
		poses.append(pose)
	# Warm up one complete lap so the seam has the same hitch state as every turn.
	for step in range(count*2):
		poses[0] = front(step*spacing)
		for index in range(1,3):
			var hitch: Vector3 = poses[index-1].origin+poses[index-1].basis.z*(LENGTHS[index-1]*.5+GAP*.5)
			var direction: Vector3 = hitch-poses[index].origin
			var basis := Basis(Vector3.UP,atan2(-direction.x,-direction.z))
			poses[index] = Transform3D(basis,hitch+basis.z*(LENGTHS[index]*.5+GAP*.5))
		if step >= count: samples.append(poses.duplicate())
func front(offset: float) -> Transform3D:
	var length := route.get_baked_length()
	var point := route.sample_baked(fposmod(offset,length),true)
	var tangent := route.sample_baked(fposmod(offset+.15,length),true)-route.sample_baked(fposmod(offset-.15,length),true)
	return Transform3D(Basis(Vector3.UP,atan2(-tangent.x,-tangent.z)),point+Vector3.UP*.04)
func at(offset: float) -> Array[Transform3D]:
	var sample := fposmod(offset,route.get_baked_length())/spacing
	var index := floori(sample)%count
	var result: Array[Transform3D] = []
	for part in 3: result.append(samples[index][part].interpolate_with(samples[(index+1)%count][part],sample-floorf(sample)))
	return result
