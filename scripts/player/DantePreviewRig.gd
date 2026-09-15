extends CharacterBody2D
## Visual host for the production wardrobe builder, without gameplay.
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D
var weapon_mount_node: Node3D
var mat_black_jacket: StandardMaterial3D
## Opt-in: a abertura e os renders de montanha continuam com o construtor antigo.
var use_meshy := false

func build(outfit_id: String) -> void:
	preload("res://scripts/player/DanteVisualAdapter.gd").build_dante_rig(self, outfit_id)
	left_upper_arm.rotation.z = -.04
	right_upper_arm.rotation.z = .04
	left_lower_arm.rotation.x = -.08
	right_lower_arm.rotation.x = -.08
	if use_meshy:
		var puppet := preload("res://scripts/player/MeshyDantePuppet.gd").new()
		model_root.add_child(puppet)
		puppet.configure(model_root, outfit_id, true)

func _update_equipped_weapon_3d_mesh() -> void:
	pass
