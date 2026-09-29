extends Node3D
## Real motocross start: one row of hinged bars across the final straight. The
## bars are visual only (bikes are held by the race controller until the drop),
## so they lie flat on the clay whenever no race is being started and practice
## riders cross them freely. One MultiMesh, animated only while moving.
const GRID_DISTANCE := -18.0
## Bars hinge half a metre ahead of the front tires on the grid.
const GATE_DISTANCE := GRID_DISTANCE+1.45
## Grid order: the player first, then rivals outwards. 1.7 m spacing leaves the
## mounting rider (0.95 m left of the seat) clear of the neighbour's handlebar;
## the outer right lane sits on the gentle start of the first corner's berm.
const LANES := [-.85,.85,-2.55,2.55,-4.25,4.25]
const BAR_SIZE := Vector3(1.5,.52,.05)
var course: Node3D
var raised := false
var _angle := 1.0
var _target := 1.0
var _pivots: Array[Transform3D] = []
var _bars: MultiMeshInstance3D

func _ready() -> void:
	name = "MotocrossStartGate"
	var road: Transform3D = course.pose(GATE_DISTANCE)
	road.origin = course.sample(GATE_DISTANCE)
	for lane in LANES:
		var lateral := float(lane)
		var left: float = course.ribbon_height(GATE_DISTANCE,lateral-BAR_SIZE.x*.5)
		var right: float = course.ribbon_height(GATE_DISTANCE,lateral+BAR_SIZE.x*.5)
		# Each hinge follows the clay's cross slope, including the right berm.
		var across := (road.basis.x*BAR_SIZE.x+Vector3.UP*(right-left)).normalized()
		var forward := -road.basis.z
		var up := across.cross(forward).normalized()
		var pivot := Transform3D(Basis(across,up,-forward),road.origin+road.basis.x*lateral)
		pivot.origin.y = (left+right)*.5+.012
		_pivots.append(pivot)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = BAR_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c9c3ae")
	material.metallic = .55
	material.roughness = .5
	mesh.material = material
	multimesh.mesh = mesh
	multimesh.instance_count = LANES.size()
	_bars = MultiMeshInstance3D.new()
	_bars.name = "DropBars"
	_bars.multimesh = multimesh
	add_child(_bars)
	_build_frame()
	_apply()
	set_process(false)

func grid_pose(index: int) -> Transform3D:
	return course.pose(GRID_DISTANCE,float(LANES[clampi(index,0,LANES.size()-1)]))

func raise_gate() -> void:
	raised = true
	_target = 0.0
	set_process(true)

func drop_gate() -> void:
	raised = false
	_target = 1.0
	set_process(true)

func _process(delta: float) -> void:
	# Springs drop the bars quickly; the starter raises them slowly.
	_angle = move_toward(_angle,_target,delta*(7.5 if _target > _angle else 1.6))
	_apply()
	if is_equal_approx(_angle,_target): set_process(false)

func _apply() -> void:
	# The bar top falls back toward the waiting riders, as on a real gate.
	var hinge := Basis(Vector3.RIGHT,_angle*PI*.5)
	for index in _pivots.size():
		var local := Transform3D(hinge,Vector3.ZERO)*Transform3D(Basis.IDENTITY,Vector3(0,BAR_SIZE.y*.5,0))
		_bars.multimesh.set_instance_transform(index,global_transform.affine_inverse()*_pivots[index]*local)

func _build_frame() -> void:
	# Starter's box and end pylons stand outside the riding width on both sides.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("4a5351")
	steel.metallic = .5
	steel.roughness = .55
	var road: Transform3D = course.pose(GATE_DISTANCE)
	for side in [-1.0,1.0]:
		# Outside the course tape line at HALF_WIDTH+0.45.
		var lateral: float = side*(course.HALF_WIDTH+1.0)
		# Lowest corner of the footprint on the sloped shoulder, sunk 6 cm.
		var ground := minf(course.ground_height(GATE_DISTANCE,lateral-.16),course.ground_height(GATE_DISTANCE,lateral+.16))
		var pylon := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.32,.8,.32)
		pylon.mesh = box
		pylon.material_override = steel
		pylon.position = to_local(road.origin+road.basis.x*lateral)
		pylon.position.y = ground+.34
		pylon.name = "GatePylon"
		add_child(pylon)
