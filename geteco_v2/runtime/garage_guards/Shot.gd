extends Node3D
var manager
var shooter: CharacterBody3D
var velocity := Vector3.ZERO
var remaining := 420.0/16.0
var travelled := 0.0
func _physics_process(delta: float) -> void:
	if not manager.active() or not is_instance_valid(shooter): queue_free(); return
	var next := global_position+velocity*delta
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position,next,7,[shooter.get_rid()]))
	manager.gameplay()._trace(global_position,next,.045,.009)
	if not hit.is_empty():
		travelled+=global_position.distance_to(hit.position)
		var damage: int=preload("res://gameplay/WeaponCatalog.gd").distance_damage(6,travelled*16,170,420,.25)
		manager.gameplay()._damage(hit.collider,damage,shooter)
		queue_free()
		return
	global_position=next
	travelled+=velocity.length()*delta
	remaining-=velocity.length()*delta
	if remaining<=0: queue_free()
