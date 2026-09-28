extends Node3D
class_name MountainChairliftParity3D

## Native 3D environmental presentation of the production V1 chairlift.
## The streaming owner mounts/unmounts the whole mechanism. Animation has no
## physics tick and can be suspended explicitly while its chunk is dormant.

const SCALE := 1.0 / 16.0
const SOURCE_CENTER := Vector2(7465.0, -3952.5)
const SOURCE_POINTS: Array[Vector2] = [
	Vector2(6880.0, -3015.0),
	Vector2(8050.0, -3600.0),
	Vector2(7900.0, -4220.0),
	Vector2(7100.0, -4890.0),
]
const SOURCE_CHAIRS := [
	{"progress": 0.12, "ascending": true, "rider": true, "color": Color("c95444")},
	{"progress": 0.35, "ascending": false, "rider": false, "color": Color.WHITE},
	{"progress": 0.58, "ascending": true, "rider": true, "color": Color("387799")},
	{"progress": 0.78, "ascending": false, "rider": false, "color": Color.WHITE},
	{"progress": 0.92, "ascending": true, "rider": true, "color": Color("d2a844")},
]
const TRIP_SECONDS := 35.0

var _cable_points := PackedVector3Array()
var _chairs: Array[Dictionary] = []
var _operating := true
var _animation_active := true
var _clock := 0.0

func _ready() -> void:
	_build()
	set_process(_animation_active and _operating)

func set_operating(value: bool) -> void:
	_operating = value
	set_process(_animation_active and _operating)

func set_animation_active(value: bool) -> void:
	_animation_active = value
	set_process(_animation_active and _operating)

func _process(delta: float) -> void:
	_clock += minf(delta, 0.1)
	for state in _chairs:
		var progress: float = float(state.progress)
		var ascending: bool = bool(state.ascending)
		progress += (1.0 if ascending else -1.0) * delta / TRIP_SECONDS
		if progress >= 1.0:
			progress = 1.0
			ascending = false
		elif progress <= 0.0:
			progress = 0.0
			ascending = true
		state.progress = progress
		state.ascending = ascending
		_update_chair(state)

func _build() -> void:
	set_meta("source_id", "world/mountain_pass/MountainSkiArea.gd:_build_lift")
	for source_point in SOURCE_POINTS:
		var relative: Vector2 = source_point - SOURCE_CENTER
		_cable_points.append(Vector3(relative.x * SCALE, 8.0, relative.y * SCALE))

	_build_cable_lane(-0.875)
	_build_cable_lane(0.875)
	_build_tower(1)
	_build_tower(2)
	_build_station("SummitLiftStation", _cable_points[0], false)
	_build_station("BaseLiftStation", _cable_points[_cable_points.size() - 1], true)

	for index in SOURCE_CHAIRS.size():
		var config: Dictionary = SOURCE_CHAIRS[index]
		var chair := _build_chair(index, bool(config.rider), config.color)
		var state := {
			"node": chair,
			"progress": float(config.progress),
			"ascending": bool(config.ascending),
		}
		_chairs.append(state)
		_update_chair(state)

func _build_cable_lane(offset: float) -> void:
	for index in range(_cable_points.size() - 1):
		var a := _cable_points[index] + Vector3(offset, 0, 0)
		var b := _cable_points[index + 1] + Vector3(offset, 0, 0)
		_cylinder_between(self, "LiftCable", a, b, 0.045, _material(Color("2e3840"), 0.68, 0.45))

func _build_tower(index: int) -> void:
	var tower := Node3D.new()
	tower.name = "LiftTower%d" % index
	tower.position = _cable_points[index] - Vector3.UP * 8.0
	add_child(tower)
	var steel := _material(Color("637078"), 0.48, 0.60)
	var dark := _material(Color("262f36"), 0.66, 0.48)
	var concrete := _material(Color("585c60"), 0.94)
	_box(tower, "ConcreteBase", Vector3(0, 0.25, 0), Vector3(1.8, 0.5, 1.8), concrete)
	_cylinder(tower, "Pylon", Vector3(0, 4.0, 0), 0.38, 7.5, steel)
	_box(tower, "ServicePlatform", Vector3(0, 7.4, 0), Vector3(1.4, 0.10, 1.4), dark)
	_box(tower, "Crossarm", Vector3(0, 7.8, 0), Vector3(4.8, 0.45, 0.45), steel)
	for side in [-2.1, 2.1]:
		for sheave_index in 4:
			var sheave := _cylinder(tower, "Sheave", Vector3(side, 7.95, (float(sheave_index) - 1.5) * 0.24), 0.14, 0.08, dark)
			sheave.rotation_degrees = Vector3(90, 0, 0)
	_add_tower_collision(tower)

func _build_station(node_name: String, cable_point: Vector3, is_base: bool) -> void:
	var station := Node3D.new()
	station.name = node_name
	station.position = cable_point - Vector3.UP * 8.0
	add_child(station)
	var concrete := _material(Color("74787a"), 0.92)
	var steel := _material(Color("4b5961"), 0.55, 0.48)
	var roof := _material(Color("34444b"), 0.72, 0.30)
	var platform := _box(station, "Platform", Vector3(0, 0.18, 0), Vector3(7.6, 0.36, 6.0), concrete)
	if not is_base:
		platform.create_trimesh_collision()
		_build_walkup_ramp(station,concrete)
	for x in [-3.1, 3.1]:
		_box(station, "StationPost", Vector3(x, 3.3, 0), Vector3(0.26, 6.6, 0.26), steel)
	_box(station, "StationRoof", Vector3(0, 6.65, 0), Vector3(7.8, 0.24, 6.2), roof)
	var wheel := _cylinder(station, "BullWheel", Vector3(0, 5.65, 0), 1.35, 0.28, steel)
	wheel.rotation_degrees = Vector3(90, 0, 0)
	station.set_meta("station_role", "base" if is_base else "summit")
	var body := StaticBody3D.new()
	body.name = "StationPostsSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	for x in [-3.1, 3.1]:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.5, 6.6, 0.5)
		collision.shape = shape
		collision.position = Vector3(x, 3.3, 0)
		body.add_child(collision)
	station.add_child(body)

func _build_walkup_ramp(station: Node3D, material: Material) -> void:
	# Meet the 2.2 m trail at ground level and the existing platform at 36 cm.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-1.1,.36,3),Vector3(1.1,.36,3),Vector3(-1.1,0,4.8),
		Vector3(1.1,.36,3),Vector3(1.1,0,4.8),Vector3(-1.1,0,4.8)]:
		surface.set_normal(Vector3(0,1,.2).normalized())
		surface.add_vertex(point)
	var ramp := MeshInstance3D.new()
	ramp.name = "WalkupRamp"
	ramp.mesh = surface.commit()
	ramp.material_override = material
	station.add_child(ramp)
	ramp.create_trimesh_collision()

func _build_chair(index: int, with_rider: bool, rider_color: Color) -> Node3D:
	var chair := Node3D.new()
	chair.name = "ChairliftChair%d" % index
	add_child(chair)
	var steel := _material(Color("4a5660"), 0.52, 0.64)
	var seat := _material(Color("2d4b68"), 0.76)
	var safety := _material(Color("d99834"), 0.48, 0.24)
	_box(chair, "CableGrip", Vector3(0, 0, 0), Vector3(0.26, 0.32, 0.22), steel)
	_cylinder(chair, "Hanger", Vector3(0, -1.15, 0), 0.045, 2.0, steel)
	_box(chair, "SeatBench", Vector3(0, -2.75, 0.15), Vector3(1.35, 0.10, 0.62), seat)
	_box(chair, "Backrest", Vector3(0, -2.3, 0.44), Vector3(1.35, 0.72, 0.08), seat)
	_box(chair, "SafetyBar", Vector3(0, -2.35, -0.22), Vector3(1.38, 0.06, 0.06), safety)
	if with_rider:
		_box(chair, "RiderCoat", Vector3(0.18, -1.95, 0.05), Vector3(0.42, 0.72, 0.30), _material(rider_color, 0.82))
		_box(chair, "RiderHead", Vector3(0.18, -1.45, 0.05), Vector3(0.24, 0.28, 0.24), _material(Color("b98362"), 0.86))
	return chair

func _update_chair(state: Dictionary) -> void:
	var chair: Node3D = state.node
	if not is_instance_valid(chair):
		return
	var progress: float = float(state.progress)
	var ascending: bool = bool(state.ascending)
	chair.position = _sample_cable(progress) + Vector3(0.875 if ascending else -0.875, 0, 0)
	chair.rotation.z = sin(_clock * 1.6 + progress * TAU) * 0.045

func _sample_cable(progress: float) -> Vector3:
	var total := 0.0
	for index in range(_cable_points.size() - 1):
		total += _cable_points[index].distance_to(_cable_points[index + 1])
	var remaining := clampf(progress, 0.0, 1.0) * total
	for index in range(_cable_points.size() - 1, 0, -1):
		var a := _cable_points[index]
		var b := _cable_points[index - 1]
		var length := a.distance_to(b)
		if remaining <= length:
			return a.lerp(b, remaining / maxf(length, 0.001))
		remaining -= length
	return _cable_points[0]

func _add_tower_collision(tower: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "TowerBaseSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.5, 1.8)
	collision.shape = shape
	collision.position = Vector3(0, 0.25, 0)
	body.add_child(collision)
	tower.add_child(body)

func _cylinder_between(parent: Node3D, node_name: String, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var delta := b - a
	var mesh := _cylinder(parent, node_name, (a + b) * 0.5, radius, delta.length(), material)
	mesh.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return mesh

func _box(parent: Node3D, node_name: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	result.mesh = mesh
	result.position = point
	result.material_override = material
	parent.add_child(result)
	return result

func _cylinder(parent: Node3D, node_name: String, point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	result.mesh = mesh
	result.position = point
	result.material_override = material
	parent.add_child(result)
	return result

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
