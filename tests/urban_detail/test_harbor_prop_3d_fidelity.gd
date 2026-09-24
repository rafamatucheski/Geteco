extends SceneTree
## Directed check for V1-authored trees, rocks, benches and lamp housings.

const REGION:=preload("res://world/regions/NativeRegion.gd")
const PROP:=preload("res://world/urban_detail/HarborProp3D.gd")
const SCALE:=1.0/16.0
var failures:=0

func check(value:bool,message:String)->void:
	if not value:
		failures+=1
		push_error("FAIL: "+message)

func _initialize()->void:
	call_deferred("_run")

func _run()->void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Harbor prop validator refuses to run without --no-save")
		quit(2)
		return
	var definitions:=PROP.records()
	var counts:={"tree":0,"rock":0,"bench":0,"lamp":0}
	for definition in definitions: counts[String(definition.kind)]+=1
	check(counts=={"tree":80,"rock":10,"bench":6,"lamp":70},"productive V1 prop inventory is complete")
	var region:=REGION.build_region("harbor")
	root.add_child(region)
	for frame in 12: await process_frame
	var checked:=0
	var cell_groups:={}
	for definition in definitions:
		var source_point:Vector2=definition.point
		var expected:=Vector3(source_point.x*SCALE,0,source_point.y*SCALE)
		var cell:=Vector2i(floori(expected.x/64.0),floori(expected.z/64.0))
		if not cell_groups.has(cell): cell_groups[cell]=[]
		cell_groups[cell].append({"definition":definition,"expected":expected})
	for cell in cell_groups:
		region.set_focus(Vector3((cell.x+.5)*64.0,0,(cell.y+.5)*64.0))
		for frame in 12: await process_frame
		for entry in cell_groups[cell]:
			var entry_definition:Dictionary=entry.definition
			var entry_expected:Vector3=entry.expected
			var found:Node3D
			for candidate in region.find_children("*","Node3D",true,false):
				if candidate.get_script()==PROP and (candidate as Node3D).global_position.distance_to(entry_expected)<.01:
					found=candidate
					break
			check(found!=null,"%s loads at %s"%[entry_definition.kind,entry_definition.point])
			if found!=null:
				check(not found.find_children("*","MeshInstance3D",true,false).is_empty(),"%s is visible native geometry"%entry_definition.point)
				check(not found.find_children("*","CollisionShape3D",true,false).is_empty(),"%s keeps physical depth"%entry_definition.point)
				check(found.find_children("*","Sprite3D",true,false).is_empty(),"%s uses no flat sprite"%entry_definition.point)
			checked+=1
	check(checked==166,"all 166 authored static props were visited")
	print("HARBOR_PROP_3D_FIDELITY checked=",checked," failures=",failures)
	region.free()
	quit(1 if failures else 0)
