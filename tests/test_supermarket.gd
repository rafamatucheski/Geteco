extends SceneTree
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const SHOP := preload("res://runtime/SupermarketShop.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const FACADE := preload("res://world/places/supermarket/SupermarketFacade.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var economy := ECONOMY.new()
	economy.enable_grid_inventory()
	economy.grant_reward("market_test",5000)
	for id in SHOP.STOCK:
		var before := economy.balance
		check(economy.purchase("supply",id,"test_"+id).ok,"buy "+id)
		check(economy.inventory.get(id,0) == 1 and economy.balance == before-ECONOMY.SUPPLIES[id].price,"one item, exact debit "+id)
		check(economy.purchase("supply",id,"test_"+id).ok and economy.inventory.get(id,0) == 1,"receipt replay never duplicates "+id)
		check(GRID.spec(id).heal > 0,"usable healing item "+id)
		check(economy.consume_item(id),"consume "+id)
	var restored := ECONOMY.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(economy.snapshot()))),"purchase receipts survive JSON save/load")
	check(restored.purchase("supply","apple","test_apple").ok and restored.inventory.get("apple",0)==0,"consumed receipt cannot recreate item after restore")
	economy.grant_item("apple",5); economy.grant_item("water",5)
	var full := economy.snapshot()
	check(not economy.purchase("supply","bread","full").ok and economy.snapshot()==full,"full pockets reject without debit")
	var empty := ECONOMY.new()
	check(not empty.purchase("supply","apple","poor").ok and empty.inventory.is_empty(),"insufficient money grants nothing")
	check(not economy.purchase("supply","not_stock","unknown").ok,"unknown product rejected")
	var before_armor := economy.balance
	check(not economy.purchase_body_armor(100,100,"armor_full").ok and economy.balance==before_armor,"full armor never charges")
	var armor := economy.purchase_body_armor(15,100,"armor_buy")
	check(armor.ok and armor.armor==100 and economy.balance==before_armor-500,"armor equips and costs 500")
	var stage := Node3D.new()
	root.add_child(stage)
	var room = PLACES.create_place("harbor_supermarket")
	stage.add_child(room)
	check(room.model.product_count > 600,"diverse stocked market has hundreds of products")
	check(room.solid_bounds.size() >= 20,"fixtures have physical footprints")
	for frame in 3: await physics_frame
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		await physics_frame
		var who := "player" if player else "npc"
		for x in [-4.8,-1.6,1.6,4.8]:
			actor.position = Vector3(x,.04,2.6)
			check(actor.test_move(actor.global_transform,Vector3(0,0,-7)),who+" gondola blocks large swept move "+str(x))
			actor.position = Vector3(x-1.1,.04,2.5)
			check(actor.test_move(actor.global_transform,Vector3(1.8,0,-1.8)),who+" gondola corner blocks diagonal "+str(x))
		for x in [-6.35,-3.15,0,3.25,6.4]:
			actor.position = Vector3(x,.04,2.6)
			check(not actor.test_move(actor.global_transform,Vector3(0,0,-6.6)),who+" clear full-length aisle "+str(x))
		for point in [room.spawn_position,room.exit_position,room.interaction_points.service,Vector3(-6.55,0,4.5),Vector3(6.55,0,4.5),Vector3(-7,0,6.25)]:
			actor.position = point+Vector3.UP*.04
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" spawn/service/reward capsule clear "+str(point))
		for side in [-1,1]:
			actor.position = Vector3(side*4.1,.04,4.4)
			check(actor.test_move(actor.global_transform,Vector3(side*2.5,0,0)),who+" checkout blocks")
		actor.free()
	var facade := FACADE.new()
	facade.position = Vector3(40,0,0)
	stage.add_child(facade)
	var actor := ACTOR.new()
	actor.controlled_automatically = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.position = Vector3(40,.04,7)
	await physics_frame
	check(actor.test_move(actor.global_transform,Vector3(0,0,-3)),"closed exterior door blocks")
	facade.set_open_amount(1)
	await physics_frame
	check(not actor.test_move(actor.global_transform,Vector3(0,0,-3)),"open exterior door admits full body")
	stage.free()
	print("SUPERMARKET checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
