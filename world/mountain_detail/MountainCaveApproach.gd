extends Node3D
## Static cover between the road and cave; the path bends around the west side.
const ROCK := preload("res://assets/regions/source/world/mountain_pass/CaveRockGeometry.gd")
const PINE := preload("res://world/regions/NativePine.gd")

func _ready() -> void:
	for row in [
		[Vector3(-1.2,.9,0),Vector3(4.4,2.4,4.0)],
		[Vector3(1.9,.6,-1.0),Vector3(3.8,1.8,3.4)],
		[Vector3(-2.1,.45,2.3),Vector3(3.2,1.4,3.1)]]:
		var rock := ROCK.rock(self,row[0],row[1],410+get_child_count(),Color("526157"))
		rock.create_trimesh_collision()
		# Reuse desert fracture with the authored rock's contact footprint.
		var size: Vector3 = rock.get_aabb().size
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_rock",rock,self,{},[],maxf(size.x,size.z)*.5)
	for point in [Vector3(3.5,0,1.5),Vector3(-3.8,0,.5),Vector3(2.8,0,-4.4)]:
		var tree := PINE.create(0,false)
		tree.position = point
		add_child(tree)
		var trunk := StaticBody3D.new()
		trunk.collision_layer = 1
		trunk.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = .24
		shape.height = 2.8
		collision.shape = shape
		collision.position.y = 1.4
		trunk.add_child(collision)
		tree.add_child(trunk)
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree",tree,self)
