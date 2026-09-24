extends RefCounted
## Keep Dante's authored light directions when his rig joins another depth buffer.
## Reuses the suspended personal viewport's lights; no per-frame work or shadows.
const ACTOR_LAYER := 1 << 18
var lights: Array[Dictionary] = []
var meshes: Array[Dictionary] = []
var destination_lights: Array[Dictionary] = []
var material: ShaderMaterial

func configure(actor: Node, destination: SubViewport, basis := Basis.IDENTITY) -> void:
	if not is_instance_valid(actor.get("meshy_rig")): return
	var source: SubViewport = actor.viewport_3d
	material = actor.meshy_rig.material
	for node in actor.model_root.find_children("*", "GeometryInstance3D", true, false):
		meshes.append({"node": node, "layers": node.layers})
		node.layers = ACTOR_LAYER
	for node in destination.find_children("*", "Light3D", true, false):
		destination_lights.append({"node": node, "mask": node.light_cull_mask})
		node.light_cull_mask &= ~ACTOR_LAYER
	for node in source.get_children():
		if not node is DirectionalLight3D: continue
		lights.append({"node": node, "parent": source, "transform": node.transform, "mask": node.light_cull_mask, "shadows": node.shadow_enabled})
		node.reparent(destination, false)
		node.basis = basis * node.basis
		node.light_cull_mask = ACTOR_LAYER
		node.shadow_enabled = false
	var native_environment := source.find_world_3d().environment
	var target_environment := destination.find_world_3d().environment
	if native_environment != null and target_environment != null:
		var native_color := native_environment.ambient_light_color.srgb_to_linear() * native_environment.ambient_light_energy
		var target_color := target_environment.ambient_light_color.srgb_to_linear() * target_environment.ambient_light_energy
		material.set_shader_parameter("shared_ambient_compensation", Vector3(native_color.r - target_color.r, native_color.g - target_color.g, native_color.b - target_color.b))

func restore() -> void:
	for state in meshes:
		if is_instance_valid(state.node): state.node.layers = state.layers
	for state in destination_lights:
		if is_instance_valid(state.node): state.node.light_cull_mask = state.mask
	for state in lights:
		if is_instance_valid(state.node) and is_instance_valid(state.parent):
			state.node.reparent(state.parent, false)
			state.node.transform = state.transform
			state.node.light_cull_mask = state.mask
			state.node.shadow_enabled = state.shadows
	if is_instance_valid(material): material.set_shader_parameter("shared_ambient_compensation", Vector3.ZERO)
	lights.clear()
	meshes.clear()
	destination_lights.clear()
	material = null
