extends RefCounted
## Preserve Maciota's existing rig proportions while reaching and sitting.
var actor: CharacterBody2D
var saved: Array[Dictionary] = []
var yaw := 0.0
var cane_visible := false
func setup(person: CharacterBody2D) -> void:
	actor = person
	yaw = actor.model_root.rotation.y
	for key in ["model_root","torso_node","head_node","left_upper_arm","left_lower_arm","right_upper_arm","right_lower_arm","left_upper_leg","left_lower_leg","right_upper_leg","right_lower_leg"]:
		var joint: Node3D = actor.get(key)
		if is_instance_valid(joint): saved.append({"joint":joint,"transform":joint.transform})
	cane_visible = actor.cane_mesh.visible if is_instance_valid(actor.cane_mesh) else false
func apply(t: float, heading: float) -> void:
	for state in saved: state.joint.transform = state.transform
	var reach := smoothstep(.05,.35,t)
	var sit := smoothstep(.35,.9,t)
	actor.model_root.rotation.y = lerp_angle(yaw,-heading-PI*.5,smoothstep(.15,.75,t))
	for joint in [actor.torso_node,actor.head_node,actor.left_upper_arm,actor.right_upper_arm,actor.left_upper_leg,actor.right_upper_leg]:
		joint.position.y -= .13*sit
	actor.torso_node.rotation.x = .28*reach*(1.0-.65*sit)
	actor.head_node.rotation.x = -.10*reach
	actor.left_upper_arm.rotation.x = -.9*reach
	actor.left_lower_arm.rotation.x = -.55*reach
	actor.right_upper_arm.rotation.x = -.7*sit
	actor.right_lower_arm.rotation.x = -.7*sit
	for joint in [actor.left_upper_leg,actor.right_upper_leg]: joint.rotation.x = -1.15*sit
	for joint in [actor.left_lower_leg,actor.right_lower_leg]: joint.rotation.x = 1.25*sit
	if is_instance_valid(actor.cane_mesh): actor.cane_mesh.visible = cane_visible and t < .30
func restore() -> void:
	for state in saved:
		if is_instance_valid(state.joint): state.joint.transform = state.transform
	if is_instance_valid(actor) and is_instance_valid(actor.cane_mesh): actor.cane_mesh.visible = cane_visible
