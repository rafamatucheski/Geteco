extends SceneTree
## Coleta posições reais de postes/luzes construídos pela região (inclui os gerados
## por código, fora do documento do editor). Saída: lamps_<região>.json.
## Uso: --script res://evidence/world-audit-20260926/collect_lamps.gd -- --no-save --area=harbor
const REGION := preload("res://world/editing/EditableRegion.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var area := "harbor"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--area="): area = arg.trim_prefix("--area=")
	var bounds := Rect2(-80,-290,600,645) if area == "harbor" else Rect2(456,-500,365,260)
	var region: Node3D = REGION.build_region(area,Vector3(bounds.get_center().x,0,bounds.get_center().y))
	root.add_child(region)
	var found := {}
	var step := 96.0
	var y := bounds.position.y
	while y <= bounds.end.y:
		var x := bounds.position.x
		while x <= bounds.end.x:
			region.set_focus(Vector3(x,0,y))
			for i in 1200:
				await process_frame
				if region.is_streaming_idle(): break
			_collect(region,found)
			x += step
		y += step
	var rows := []
	for key in found: rows.append(found[key])
	var file := FileAccess.open("res://evidence/world-audit-20260926/lamps_%s.json" % area,FileAccess.WRITE)
	file.store_string(JSON.stringify(rows))
	file.close()
	print("LAMPS ",area," ",rows.size())
	quit(0)

func _collect(node: Node, found: Dictionary) -> void:
	for child in node.find_children("*","Node3D",true,false):
		var name_l := String(child.name).to_lower()
		var is_light: bool = child is OmniLight3D or child is SpotLight3D
		var is_lamp := name_l.contains("lamp") or name_l.contains("streetlight") or name_l.contains("poste") or name_l.contains("lantern")
		if not (is_light or is_lamp): continue
		if child is MultiMeshInstance3D:
			if name_l.ends_with("head"): continue
			for index in child.multimesh.instance_count:
				var q: Vector3 = child.global_transform * child.multimesh.get_instance_transform(index).origin
				found["%d_%d" % [roundi(q.x*2),roundi(q.z*2)]] = {"x":q.x,"z":q.z,"y":q.y,"name":"CityLook_sidewalk_lamp","class":"MultiMesh","path":""}
			continue
		var p: Vector3 = child.global_position
		var key := "%d_%d" % [roundi(p.x*2),roundi(p.z*2)]
		if found.has(key): continue
		found[key] = {"x":p.x,"z":p.z,"y":p.y,"name":String(child.name),"class":child.get_class(),"path":String(child.get_path()).substr(0,160)}
