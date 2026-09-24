extends SceneTree
## Directed V1 HarborBridge -> native 3D contract. No save path is resolved.

const REGION:=preload("res://world/regions/NativeRegion.gd")
var failures:=0

func check(value:bool,message:String)->void:
	if value: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func _initialize()->void:
	call_deferred("_run")

func _run()->void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Harbor bridge validator refuses to run without --no-save")
		quit(2)
		return
	var center:=Vector3(3790.0/16.0,0,400.0/16.0)
	var region:=REGION.build_region("harbor",center)
	root.add_child(region)
	for frame in 24: await process_frame
	var bridge:=region.find_child("FoundryBridge3D",true,false) as Node3D
	check(bridge!=null,"productive Harbor bridge streams at its V1 centre")
	if bridge!=null:
		check(String(bridge.get_meta("source_id",""))=="world/harbor/HarborBridge.gd","bridge identifies the productive V1 source")
		check(bridge.find_children("PylonMast*","MeshInstance3D",true,false).size()==4,"four V1 pylon masts are volumetric")
		check(bridge.find_children("StayCable*","MeshInstance3D",true,false).size()==32,"all 32 V1 fan stays are volumetric")
		check(bridge.find_children("BridgeLampHead*","MeshInstance3D",true,false).size()==12,"bridge light housings preserve the V1 spacing")
		check(bridge.find_children("*Rail","MeshInstance3D",true,false).size()>=2,"both edge rails are visible 3D structure")
		var solids:=bridge.find_children("*","CollisionShape3D",true,false)
		check(solids.size()>=11,"rails, pylons and abutment have independent collision")
		check(bridge.find_children("*","Sprite3D",true,false).is_empty(),"bridge uses no flat sprites")
		check(bridge.find_children("*","SubViewport",true,false).is_empty(),"bridge uses no projected viewport")
	print("HARBOR_BRIDGE_FIDELITY failures=",failures)
	region.free()
	quit(1 if failures else 0)
