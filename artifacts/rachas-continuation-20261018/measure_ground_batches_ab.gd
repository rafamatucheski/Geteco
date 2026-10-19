extends "res://artifacts/rachas-continuation-20261018/measure_ground_cover_ab.gd"
## One finite same-process comparison. Copies are built hidden before sampling;
## switching only changes visibility. No duplicate breakable registration.
class Group:
	var buffer := PackedFloat32Array()
	var bounds := AABB()
	var has_bounds := false
	var parent: Node3D
	var mesh: Mesh
	var material: StandardMaterial3D
	var kind := ""
	var vertices := 0

var merged_cover: Array[Dictionary] = []
var merged_active := false

func _output_prefix() -> String: return "drag-batches-ab"
func _scope_note() -> String: return "same board and fixed production camera; identical instance buffers/materials/fade; only current 48 m or merged 96 m nodes visible; merged copies have no breakable registration"
func _variant_names() -> Array[String]: return ["current_48","merged_96","current_48_restored"]

func _save_cover() -> void:
	super._save_cover()
	var groups: Dictionary={}
	var original_instances:=0
	for item in saved_cover:
		var node: MultiMeshInstance3D=item.node
		item.visible=node.visible
		if not node.transform.is_equal_approx(Transform3D.IDENTITY):
			failed=true
			push_error("DRAG_BATCHES_AB cannot concatenate a transformed source")
			return
		var kind: String=str(node.name).split("_")[-1]
		var key:=str(node.get_parent().get_instance_id())+"|"+kind
		if not groups.has(key):
			var group:=Group.new()
			group.parent=node.get_parent()
			group.mesh=node.multimesh.mesh
			group.material=node.material_override
			group.kind=kind
			groups[key]=group
		var group: Group=groups[key]
		if group.mesh!=node.multimesh.mesh or group.material!=node.material_override:
			failed=true
			push_error("DRAG_BATCHES_AB source materials/meshes differ")
			return
		group.buffer.append_array(node.multimesh.buffer)
		group.bounds=group.bounds.merge(node.get_aabb()) if group.has_bounds else node.get_aabb()
		group.has_bounds=true
		group.vertices+=int(item.vertices)
		original_instances+=node.multimesh.instance_count
	var merged_instances:=0
	var exact_buffers:=true
	for group: Group in groups.values():
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.use_colors=true
		batch.mesh=group.mesh
		batch.instance_count=group.buffer.size()/16
		batch.buffer=group.buffer
		batch.custom_aabb=group.bounds
		var node:=MultiMeshInstance3D.new()
		node.name="DiagnosticMergedGround_"+group.kind
		node.multimesh=batch
		node.material_override=group.material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end=group.material.distance_fade_min_distance+group.bounds.size.length()*.5+2.0
		node.hide()
		group.parent.add_child(node)
		merged_instances+=batch.instance_count
		exact_buffers=exact_buffers and batch.buffer==group.buffer and group.bounds.has_volume()
		merged_cover.append({"node":node,"vertices":group.vertices})
	results.batch_construction={"current_batches":saved_cover.size(),"merged_batches":merged_cover.size(),"current_instances":original_instances,"merged_instances":merged_instances,"exact_concatenated_buffers":exact_buffers,"created_hidden":true,"breakables_registered":false}
	if original_instances!=merged_instances or not exact_buffers:
		failed=true
		push_error("DRAG_BATCHES_AB geometry equivalence failed")

func _apply_variant(variant: String) -> void:
	merged_active=variant=="merged_96"
	for item in saved_cover: item.node.visible=bool(item.visible) and not merged_active
	for item in merged_cover: item.node.visible=merged_active

func _snapshot() -> Dictionary:
	# The inherited inventory and actual renderer counters are read outside the
	# timed windows; point it at whichever complete representation is visible.
	var originals:=saved_cover
	if merged_active: saved_cover=merged_cover
	var result:=super._snapshot()
	saved_cover=originals
	result["representation"]="merged_96" if merged_active else "current_48"
	return result

func _restore() -> void:
	var visibility_restored:=true
	for item in saved_cover:
		if not is_instance_valid(item.node): visibility_restored=false; continue
		item.node.visible=item.get("visible",true)
		visibility_restored=visibility_restored and item.node.visible==item.get("visible",true)
	for item in merged_cover:
		if is_instance_valid(item.node): item.node.hide()
	results.batch_visibility_restored=visibility_restored
	super._restore()
