extends SceneTree
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const AI := preload("res://gameplay/police_response/ground/PoliceTankWeapon.gd")
var failures: Array[String] = []
var checks := 0
var groups := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("CANNON PASS " if ok else "CANNON FAIL ")+label)
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	var b := KIT.build(self,KIT.grid_roads(),Vector3(12,.04,12))
	b.gameplay.set_physics_process(false)
	b.gameplay.police_air.set_physics_process(false)
	b.controller.set_physics_process(false)
	b.player.set_physics_process(false)
	var car := add_car(b.scene,"army_tank",Vector3(0,.04,0))
	car.controlled = true
	b.tank = car
	b.cannon = car.tank_cannon
	return b

func add_car(scene: Node3D, archetype: String, point: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = archetype
	car.position = point
	scene.add_child(car)
	car.set_physics_process(false)
	if car.has_node("TankDriverControls"): car.get_node("TankDriverControls").set_physics_process(false)
	return car

func advance(cannon: Node3D, delta: float) -> void:
	cannon._physics_process(delta)
	cannon.set_physics_process(false)

func shoot(b: Dictionary, point: Vector3, police: bool = false) -> bool:
	b.cannon.aim_at(point,10.0)
	var fired: bool = b.cannon.fire(b.gameplay,police)
	b.cannon.set_physics_process(false)
	return fired

func run() -> void:
	await aim_and_permissions()
	await direct_and_blast()
	await obstacles_and_cleanup()
	await police_cannon()
	check(groups == 4,"all four physical cannon scenarios completed")
	print("TANK_CANNON checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)

func aim_and_permissions() -> void:
	var b := fixture()
	await physics_frame
	var c: Node3D = b.cannon
	check(c != null and c.muzzle != null,"real tank builds articulated cannon and muzzle")
	if c == null or c.muzzle == null: KIT.teardown(b); return
	for target in [Vector3(30,2,0),Vector3(0,2,30),Vector3(-30,2,0),Vector3(0,2,-30)]:
		c.aim_at(target,10.0)
		check(c.is_aligned(target,.03) and is_zero_approx(b.tank.rotation.y),"turret aims cardinal direction without rotating hull "+str(target))
	b.tank.rotation.y = .8
	c.aim_at(Vector3(0,2,-30),10.0)
	check(c.is_aligned(Vector3(0,2,-30),.03) and is_equal_approx(b.tank.rotation.y,.8),"turret compensates for hull turn")
	c.aim_at(Vector3(0,100,-10),10.0)
	check(is_equal_approx(c.barrel.rotation.x,deg_to_rad(24.0)),"barrel elevation is mechanically bounded")
	b.tank.controlled = false
	check(not shoot(b,Vector3(0,2,-30)),"unoccupied tank cannot fire")
	b.tank.controlled = true
	b.state.safe = true
	check(not shoot(b,Vector3(0,2,-30)),"garage rejects cannon fire")
	b.state.safe = false
	b.player.input_locked = true
	check(not shoot(b,Vector3(0,2,-30)),"player transition rejects cannon fire")
	b.player.input_locked = false
	check(shoot(b,Vector3(0,2,-30)),"player can fire mounted cannon")
	check(c.cooldown == 3.0 and c.recoil.position.z > .2 and not c.fire(b.gameplay),"one shot starts reload and visual recoil, prevents immediate repeat")
	advance(c,.35)
	check(c.recoil.position.is_zero_approx() and is_equal_approx(b.tank.rotation.y,.8),"recoil returns barrel without moving chassis")
	advance(c,3.0)
	check(c.shells.is_empty() and not c.is_physics_processing(),"range expiry and reload return cannon to sleep")
	KIT.teardown(b)
	await process_frame
	groups += 1

func direct_and_blast() -> void:
	var b := fixture()
	var direct := add_car(b.scene,"coupe",Vector3(0,.04,-20))
	direct.health = 500
	var radial := add_car(b.scene,"coupe",Vector3(3.5,.04,-16.5))
	radial.health = 500
	var protected_parent := Node3D.new()
	protected_parent.set_meta("invulnerable",true)
	b.scene.add_child(protected_parent)
	var protected := add_car(protected_parent,"coupe",Vector3(-3.5,.04,-16.5))
	protected.health = 500
	var witness := KIT.add_patient(b.scene,Vector3(8,.04,-10),100)
	witness.controlled_automatically = true
	witness.set_physics_process(false)
	var sources: Array = []
	b.gameplay.explosion_occurred.connect(func(_point,_radius,source): sources.append(source))
	await physics_frame
	await physics_frame
	check(shoot(b,direct.global_position+Vector3.UP),"shell launches toward real vehicle")
	check(direct.health == 500 and b.cannon.shells.size() == 1,"launch does not deal instant hitscan damage")
	b.tank.controlled = false
	advance(b.cannon,.25)
	check(is_equal_approx(direct.health,320.0),"direct vehicle takes 180 damage exactly once, excluding own radial blast")
	check(radial.health < 500 and radial.health > 400,"nearby vehicle receives bounded radial falloff")
	check(radial.horizontal_velocity.length() > .1,"explosion imparts physical vehicle impulse")
	check(protected.health == 500 and protected.horizontal_velocity.is_zero_approx(),"protected ancestor shields Maciota-style body from damage and impulse")
	check(b.tank.health == b.tank.max_health,"own tank is excluded from its explosion")
	check(sources.size() == 1 and sources[0] == b.player,"impact retains player attribution after leaving tank")
	check(not b.gameplay.police_case.pending.is_empty(),"player cannon noise creates a witness report through actual crime system")
	KIT.teardown(b)
	await process_frame
	groups += 1

func obstacles_and_cleanup() -> void:
	var b := fixture()
	var target := add_car(b.scene,"coupe",Vector3(0,.04,-12))
	target.health = 500
	var wall := KIT.add_wall(b.scene,Vector3(0,2,-9),Vector3(10,4,.06))
	await physics_frame
	await physics_frame
	check(shoot(b,target.global_position+Vector3.UP),"shell fires at obstructed direction")
	advance(b.cannon,.5)
	check(b.cannon.impact_count == 1 and b.cannon.shells.is_empty(),"swept shell hits thin wall during a long physics step")
	check(target.health == 500,"wall blocks shell and blast damage behind it")
	wall.free()
	advance(b.cannon,3.0)
	var close_wall := KIT.add_wall(b.scene,Vector3(0,2,-4),Vector3(10,4,.06))
	await physics_frame
	await physics_frame
	check(shoot(b,target.global_position+Vector3.UP),"muzzle can fire into close exterior wall")
	advance(b.cannon,.1)
	check(b.tank.health == b.tank.max_health and b.tank.horizontal_velocity.is_zero_approx(),"point-blank blast cannot damage or propel firing tank")
	close_wall.free()
	advance(b.cannon,3.0)
	var muzzle_wall := KIT.add_wall(b.scene,Vector3(0,1.7,-2),Vector3(5,4,.10))
	await physics_frame
	await physics_frame
	check(not shoot(b,target.global_position+Vector3.UP),"barrel cannot launch a projectile from the other side of a wall")
	muzzle_wall.free()
	await physics_frame
	check(shoot(b,target.global_position+Vector3.UP),"clear muzzle fires after obstruction removal")
	b.state.safe = true
	advance(b.cannon,.5)
	check(target.health == 500 and b.cannon.shells.is_empty(),"entering garage cancels airborne shell before damage")
	b.state.safe = false
	advance(b.cannon,3.0)
	shoot(b,target.global_position+Vector3.UP)
	var shell: WeakRef = weakref(b.cannon.shells[0].visual)
	b.tank.free()
	check(shell.get_ref() == null,"unloading tank frees attached projectile visuals")
	KIT.teardown(b)
	await process_frame
	groups += 1

func police_cannon() -> void:
	var b := fixture()
	b.player.position = Vector3(0,.04,-20)
	b.tank.set_external_driver(true)
	var unit: RefCounted = b.controller._make_unit("police",b.tank,10.0,4.0)
	unit.variant = "tank"
	var ai := AI.new()
	await physics_frame
	await physics_frame
	ai.tick(unit,2.0,b.player)
	check(b.cannon.shot_count == 0,"police cannon never fires without observed force authorization")
	b.gameplay.register_crime(80,b.player.global_position,"police_assault")
	ai.tick(unit,2.0,b.player)
	b.cannon.set_physics_process(false)
	check(b.cannon.shot_count == 1,"actual dispatch AI now fires at hostile player on foot")
	advance(b.cannon,.3)
	check(b.gameplay.health > 0 and b.gameplay.health >= 45 and b.gameplay.health < 100,"single police shell cannot instantly kill full-health player on foot")
	advance(b.cannon,3.0)
	b.gameplay.police_case.tick(1.1)
	b.player.velocity = Vector3.ZERO
	check(shoot(b,b.player.global_position+Vector3.UP,true),"authorized police launches next physical shell")
	var health: float = b.gameplay.health
	check(b.gameplay.police_case.request_surrender(),"surrender accepted before incoming shell impact")
	advance(b.cannon,.3)
	check(b.cannon.shells.is_empty() and b.gameplay.health == health,"surrender cancels airborne police projectile")
	advance(b.cannon,3.0)
	check(not shoot(b,b.player.global_position+Vector3.UP,true),"surrender prevents subsequent police fire")
	b.gameplay.police_case.cancel_surrender()
	b.tank.set_external_driver(false)
	b.tank.controlled = true
	var count: int = b.cannon.shot_count
	ai.tick(unit,5.0,b.player)
	check(b.cannon.shot_count == count,"AI cannot commandeer cannon after player steals tank")
	unit = null
	KIT.teardown(b)
	await process_frame
	groups += 1
