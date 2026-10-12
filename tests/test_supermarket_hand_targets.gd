extends SceneTree
const MARKET = preload("res://world/places/supermarket/SupermarketPlace.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func run() -> void:
	var market := MARKET.new()
	market.definition = MARKET.definition_data()
	root.add_child(market)
	market.position = Vector3(40,0,-80)
	market.rotation.y = .7
	var player := Node3D.new()
	root.add_child(player)
	var session := {"world":{"gameplay":{"health":100,"stars":0},"player":player},"room_npcs":[]}
	market.on_session_entered(session)
	for customer in market.customers:
		customer.set_physics_process(false)
		customer.stage = "checkout"
		for yaw in [0.0,PI*.5,PI,-PI*.5]:
			customer.visual.rotation.y = yaw
			var hands: Array = customer.shopping_model.hand_provider.call()
			var left: Vector3 = customer.shopping_model.to_local(hands[0])
			var right: Vector3 = customer.shopping_model.to_local(hands[1])
			check(left.z>0 and right.z>0,"basket grips remain in front after turn")
			check(left.x<0 and right.x>0,"hands do not cross to opposite handles")
		customer.stage = "browse"
		customer.route_index = customer.route_points.size()
		customer.wait_time = 1
		var target: Vector3 = customer.shopping_model.hand_provider.call()[1]
		check(target.is_equal_approx(market.to_global(customer.position+Vector3(.65,1.1,0))),"shelf reach follows transformed room")
		customer.stage = "checkout"
		check(not customer.shopping_model.hand_provider.call()[1].is_equal_approx(target),"shelf target clears when carrying resumes")
		customer.dead = true
		check(customer.shopping_model.hand_provider.call()==[null,null],"death releases hand targets")
	market.free()
	player.free()
	print("SUPERMARKET_HAND_TARGETS failures=",failures)
	quit(0 if failures.is_empty() else 1)
