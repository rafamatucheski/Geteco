extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var doc = GLTFDocument.new()
 var state = GLTFState.new()
 print("IMPORT ", doc.append_from_file("res://assets/characters/meshy_dante/dante.glb",state))
 var model = doc.generate_scene(state)
 root.add_child(model)
 model.print_tree_pretty()
 for n in model.find_children("*","Skeleton3D",true,false):
  for i in n.get_bone_count(): print(n.get_bone_name(i)," ",n.get_bone_global_rest(i))
 for a in model.find_children("*","AnimationPlayer",true,false): print("ANIMS ",a.get_animation_list())
 quit()
