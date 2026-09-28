extends Node3D
## Bounded course markers. Ground probes run only near the skier, at 2 Hz.
var progression
var markers: Array[Node3D] = []
var clock := 0.0
func configure(owner_progression) -> void:
	progression = owner_progression
func _ready() -> void:
	var colors := [Color("48bb85"), Color("419ee0"), Color("343747")]
	var index := 0
	for id in progression.COURSES:
		var spec: Dictionary = progression.COURSES[id]
		var points: Array = [spec.start]
		points.append_array(spec.points)
		for i in points.size():
			var marker := Node3D.new()
			marker.position = progression.Definitions.at(points[i], "mountain")
			var next: Vector3 = progression.Definitions.at(points[mini(i+1,points.size()-1)], "mountain")
			var previous: Vector3 = progression.Definitions.at(points[maxi(0,i-1)], "mountain")
			var direction := previous.direction_to(next)
			marker.rotation.y = atan2(-direction.x,-direction.z)
			add_child(marker)
			marker.set_meta("course",id)
			marker.set_meta("gate",i-1)
			var color: Color = colors[index]
			var pole_height := 2.5 if i == 0 or i == points.size()-1 else 2.0
			for side in [-1,1]:
				_box(marker,Vector3(side*3.6,pole_height*.5,0),Vector3(.055,pole_height,.055),Color("e9eff1"))
				_box(marker,Vector3(side*3.25,1.65,0),Vector3(.65,.5,.045),color)
			if i == 0 or i == points.size()-1:
				_box(marker,Vector3(0,2.3,0),Vector3(7.3,.32,.12),color)
			marker.hide()
			markers.append(marker)
		index += 1
func _physics_process(delta: float) -> void:
	clock += delta
	if clock < .5: return
	clock = 0
	var session = progression.session
	var outside: bool = progression._outside()
	for marker in markers:
		marker.visible = outside and progression._flat(session.world.player.position).distance_to(progression._flat(marker.position)) < 95
		if not marker.visible: continue
		var point: Vector3 = progression._flat(marker.position)
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*5,1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		marker.visible = not hit.is_empty()
		if marker.visible: marker.position.y = hit.position.y + .02
func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
