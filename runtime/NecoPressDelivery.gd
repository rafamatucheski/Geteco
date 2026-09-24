extends Node
## Owns only the temporary presentation. GarageRewards owns the transaction.
signal finished(completed: bool)
var press: Node3D
var car: Node3D
var proxy: Node3D
var sound: AudioStreamPlayer3D
var active := false
var saved := {}

func begin(vehicle: Node3D) -> bool:
	if active or not is_instance_valid(vehicle): return false
	for candidate in get_tree().get_nodes_in_group("native_neco_press"):
		if candidate.global_position.distance_to(vehicle.global_position)<25 and not candidate.is_active():
			press=candidate
			break
	if not is_instance_valid(press) or not press.is_admission_clear(): return false
	proxy=Node3D.new()
	_copy_meshes(vehicle.visual,vehicle.global_transform.affine_inverse(),proxy)
	if proxy.get_child_count()==0: proxy.free(); proxy=null; return false
	# Flatten only meshes: no scripts, collision bodies, lights or equipment are copied.
	var bounds := AABB()
	var first := true
	for mesh in proxy.get_children():
		var box: AABB=mesh.transform*mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	var bed: Vector3=press.get_reception_size()
	if bounds.size.x>bed.x or bounds.size.y>bed.y or bounds.size.z>bed.z:
		proxy.free(); proxy=null; return false
	var offset := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	for mesh in proxy.get_children(): mesh.position-=offset
	press.add_child(proxy)
	proxy.global_transform=press.get_reception_transform()*Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
	car=vehicle
	saved={"visible":car.visible,"physics":car.is_physics_processing(),"drivable":car.is_in_group("drivable")}
	# Keep the real hull reserving its original place, so cancellation can restore safely.
	car.hide()
	car.set_physics_process(false)
	car.remove_from_group("drivable")
	active=true
	press.presentation_completed.connect(_completed)
	press.presentation_cancelled.connect(cancel)
	press.tree_exiting.connect(cancel)
	if not press.start_presentation(proxy): cancel(); return false
	sound=AudioStreamPlayer3D.new()
	sound.stream=preload("res://audio/neco/SalvageAudio.gd").hydraulics()
	sound.bus="SFX" if AudioServer.get_bus_index("SFX")>=0 else "Master"
	sound.volume_db=-19
	sound.max_distance=35
	proxy.add_child(sound)
	sound.play()
	return true

func _copy_meshes(node: Node, inverse: Transform3D, target: Node3D) -> void:
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh!=null:
		var copy := MeshInstance3D.new()
		copy.mesh=node.mesh
		copy.material_override=node.material_override
		copy.material_overlay=node.material_overlay
		copy.cast_shadow=node.cast_shadow
		for surface in node.mesh.get_surface_count():
			copy.set_surface_override_material(surface,node.get_surface_override_material(surface))
		target.add_child(copy)
		copy.transform=inverse*node.global_transform
	for child in node.get_children(): _copy_meshes(child,inverse,target)

func _completed(_visual: Node3D) -> void: _finish(true)
func cancel() -> void: _finish(false)
func _exit_tree() -> void: cancel()

func _finish(completed: bool) -> void:
	if not active: return
	active=false
	if is_instance_valid(press):
		for pair in [[press.presentation_completed,_completed],[press.presentation_cancelled,cancel],[press.tree_exiting,cancel]]:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
		if press.is_active(): press.cancel_presentation()
	if is_instance_valid(car):
		car.visible=saved.visible
		car.set_physics_process(saved.physics)
		if saved.drivable: car.add_to_group("drivable")
	if is_instance_valid(sound): sound.stop()
	if is_instance_valid(proxy): proxy.queue_free()
	proxy=null
	press=null
	car=null
	finished.emit(completed)
