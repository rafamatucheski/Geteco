extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var pool := root.get_node("EmergencyPool")
 var before := get_nodes_in_group("police_officer").size()
 paused = true
 var memory_before := OS.get_static_memory_usage()
 var start := Time.get_ticks_usec()
 await pool.prepare_officers()
 print("RESERVE preparation_us=",Time.get_ticks_usec()-start," memory_delta=",OS.get_static_memory_usage()-memory_before)
 assert(get_nodes_in_group("police_officer").size()==before,"Unused reserve must not participate in gameplay")
 var world := Node2D.new()
 root.add_child(world)
 current_scene = world
 var vehicle := CharacterBody2D.new()
 world.add_child(vehicle)
 var target := Node2D.new()
 world.add_child(target)
 for level in [1,2,3,4,5,6]:
  var cold: Node2D = load("res://PoliceOfficer.tscn").instantiate()
  cold.set_meta("response_tier_level",level)
  cold.set_meta("quiet_patrol",true)
  start=Time.get_ticks_usec()
  world.add_child(cold)
  var cold_us := Time.get_ticks_usec()-start
  var unit: Node2D=pool.take_officer(level)
  var model: Node3D=unit.model_root
  var collision: CollisionShape2D=unit.collision_shape
  unit.set_meta("response_tier_level",level)
  unit.set_meta("quiet_patrol",true)
  unit.target=target
  unit.begin_service_disembark(vehicle,-1,-8)
  start=Time.get_ticks_usec()
  world.add_child(unit)
  var ready_us := Time.get_ticks_usec()-start
  assert(unit.model_root==model and unit.collision_shape==collision,"Activation reuses rig and collision")
  assert(unit.health==cold.health and unit.speed==cold.speed and unit.dropped_weapon==cold.dropped_weapon and unit.tier==cold.tier)
  assert(unit.target==target and unit.service_vehicle==vehicle and unit.service_disembark_active)
  assert(unit.get_collision_exceptions().has(vehicle))
  assert(unit.get_node("NPCCombatRig").actor==unit and unit.get_node("PoliceLoot").dropped_weapon==unit.dropped_weapon)
  assert(unit.visible and unit.process_mode==Node.PROCESS_MODE_INHERIT)
  print("OFFICER_RESERVE level=",level," cold_us=",cold_us," activation_us=",ready_us," children=",unit.get_child_count())
  cold.free()
  unit.free()
 # Exhaustion must still create a real unit; it cannot cap the dispatched crew.
 var remaining: Array=pool._officer_reserve[6]
 while not remaining.is_empty():
  var unused: Node2D=pool.take_officer(6)
  unused.free()
 var fallback: Node2D=pool.take_officer(6)
 assert(fallback.model_root==null)
 fallback.set_meta("response_tier_level",6)
 fallback.set_meta("quiet_patrol",true)
 world.add_child(fallback)
 assert(fallback.tier==4 and fallback.health==130)
 world.free()
 paused=false
 print("OFFICER_RESERVE PASS tiers/health/weapons/target/collision/reuse/exhaustion")
 quit(0)
