extends RefCounted
## Sweep every usable lateral band, including the vehicle's real corner motion.
static func sweep(world:Node2D,curve:Curve2D,space:Transform2D,width:float,hull_size:Vector2,begin:float,end:float)->Dictionary:
	var hull:=CharacterBody2D.new()
	hull.collision_layer=0
	hull.collision_mask=1
	var collision:=CollisionShape2D.new()
	collision.shape=RectangleShape2D.new()
	collision.shape.size=hull_size
	hull.add_child(collision)
	world.add_child(hull)
	await world.get_tree().physics_frame
	await world.get_tree().physics_frame
	var lateral_limit:=width*0.5-hull_size.y*0.5-2.0
	var bands:PackedFloat32Array=PackedFloat32Array([-lateral_limit,0.0,lateral_limit])
	for lateral in range(-int(lateral_limit),int(lateral_limit)+1,2):bands.append(float(lateral))
	var failures:Array[Dictionary]=[]
	var samples:=0
	var stop:=minf(end,curve.get_baked_length()-2.0)
	for lateral in bands:
		for progress in range(int(begin),int(stop)+1,2):
			var current:=space*curve.sample_baked_with_rotation(float(progress),true)
			var next:=space*curve.sample_baked_with_rotation(float(progress+2),true)
			current.origin+=current.y*lateral
			next.origin+=next.y*lateral
			for backwards in [false,true]:
				var source:Transform2D=next if backwards else current
				var target:Vector2=current.origin if backwards else next.origin
				var result:=KinematicCollision2D.new()
				samples+=1
				if hull.test_move(source,target-source.origin,result):
					failures.append({"progress":progress,"lateral":lateral,"backwards":backwards,"position":source.origin,"body":str(result.get_collider().get_path())})
	hull.queue_free()
	return {"samples":samples,"blocked":failures.size(),"examples":failures.slice(0,8),"width":width,"hull":hull_size,"bands":bands.size()}
