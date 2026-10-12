extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var r = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
 r.prepare_data()
 print("BANK ",preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_bank"))
 for b in r.buildings:
  if b.position.distance_to(Vector3(40,0,10)) < 45: print("BUILDING ",b)
 for road in r.roads:
  for p in road.points:
   if p.distance_to(Vector3(40,0,10)) < 50: print("ROAD ",road); break
 r.free()
 quit()
