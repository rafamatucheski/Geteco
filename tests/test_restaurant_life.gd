extends SceneTree
const LIFE := preload("res://world/harbor/restaurants/HarborRestaurantLife.gd")
const TABLE := preload("res://world/harbor/restaurants/RestaurantTable3D.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	check(LIFE.scheduled_guests("anchor",0,3.0)==0,"Diner is empty overnight")
	check(LIFE.scheduled_guests("early_shift",0,6.0)==2,"Early Shift opens for morning workers")
	check(LIFE.scheduled_guests("tideline",0,6.0)==0,"Promenade café stays closed early")
	check(LIFE.scheduled_guests("anchor",0,10.8)==2,"Initial world time has customers")
	check(LIFE.scheduled_guests("anchor",1,12.5)==2,"Second table fills during lunch")
	check(LIFE.scheduled_guests("anchor",1,16.0)==0,"Second table clears between meal peaks")
	check(LIFE.scheduled_guests("early_shift",0,19.0)==0,"Worker café closes before evening diner")
	check(LIFE.scheduled_guests("anchor",0,19.0)==2,"Diner remains occupied for dinner")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var life := LIFE.new()
	world.add_child(life)
	check(life.terraces.size()==6,"Three venues each have two tables")
	life.update_context(12.5,.65,Vector2(10000,10000),.25)
	check(life.get_status().active_views==0,"Distant tables do not render")
	for view in life.terraces:
		check(view.viewport_3d==null,"Distant tables do not allocate viewports")
		check(view.get_child_count()==3,"Streaming preserves physical table and chair colliders")
		var access := Rect2(590,1120,62,28) if view.venue_id=="anchor" else (Rect2(5760,1620,60,580) if view.venue_id=="tideline" else Rect2(6175,-1260,50,160))
		for body in view.get_children():
			var shape: RectangleShape2D = body.get_child(0).shape
			check(not access.intersects(Rect2(body.global_position-shape.size*.5,shape.size)),"Furniture keeps entrance corridor clear")
	var model := TABLE.new()
	root.add_child(model)
	model.build(2)
	model.set_conditions(2,0.0,0.0,true)
	check(model.guests.size()==2 and model.guests[0].sit_amount==1.0,"Both guests are physically seated")
	check(model.guests[0].hips[0].rotation.x>1.5 and model.guests[0].knees[0].rotation.x< -1.5,"Seated thighs and knees articulate naturally")
	var before: float = model.guests[0].elbows[1].rotation.x
	model.set_conditions(2,.65,.5)
	check(model.opening>0.0 and model.opening<1.0,"Rain opens the parasol progressively")
	var animated := false
	for i in 160:
		model.set_conditions(2,.65,.1)
		animated = animated or not is_equal_approx(before,model.guests[0].elbows[1].rotation.x)
	check(model.get_status().umbrella_open,"Rain fully deploys shelter")
	check(animated,"Eating and conversation animate the arms")
	model.set_conditions(0,0.0,.3)
	check(model.guests[0].visible and model.guests[0].sit_amount<1.0,"Closing begins standing animation without disappearing")
	for i in 50: model.set_conditions(0,0.0,.1)
	check(not model.guests[0].visible and not model.place_settings[0].visible,"Guests and dirty place settings clear after departure")
	check(model.opening==0.0,"Parasol folds after the rain")
	var view: Node2D = life.terraces[0]
	await physics_frame
	view.hear_gunfire(view.global_position+Vector2(350,0),view.global_position)
	check(view.alarm_remaining==0.0,"Distant shot does not disturb diners")
	view.hear_gunfire(view.global_position+Vector2(0,60),view.global_position)
	check(view.alarm_remaining>0.0,"Local danger sends customers indoors")
	life.update_context(12.0,0.0,Vector2(10000,10000),30.0)
	check(view.alarm_remaining==0.0,"Customers may return when local danger has passed")
	model.queue_free()
	world.queue_free()
	await process_frame
	print("RESTAURANT_LIFE failures=%d" % failures)
	quit(1 if failures else 0)
