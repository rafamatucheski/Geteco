extends Node
## Each interior owns one finite stash; the economy receipt survives reloads.
const CASH := [120,180,150,220,250,5000]
var session
var homes: Node3D
var _scan := 0.0
func configure(owner_session,house_manager: Node3D) -> void:
	session=owner_session
	homes=house_manager
func _process(delta: float) -> void:
	_scan-=delta
	if _scan>0 or session==null or not session.ready_for_play or not is_instance_valid(homes): return
	_scan=.2
	if session.state.region_id!="harbor" or not session.state.place_id.is_empty(): return
	var receipts: Dictionary = session.state.economy.snapshot().transactions
	for i in homes.homes.size():
		var stash: Node3D = homes.homes[i].loot
		var id := "tonico_home_stash_%d"%i
		var taken: bool = receipts.has("reward:"+id)
		stash.visible=not taken
		if taken or session.world.gameplay.health<=0 or session.world.player.get("dead")==true or session.world.driving.occupied: continue
		if homes.current_home!=i or homes.house_at(session.world.player.global_position)!=i or session.world.player.global_position.distance_to(stash.global_position)>1.3: continue
		if session.state.economy.grant_reward(id,CASH[i]):
			stash.visible=false
			session.show_message("Encontrou R$ %d."%CASH[i])
