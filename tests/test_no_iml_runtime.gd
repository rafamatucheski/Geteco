extends SceneTree

const GAME := preload("res://world/harbor/HarborGame.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while not world.gameplay_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	var pool := root.get_node("EmergencyPool")
	check((pool._pool.get("coroner", []) as Array).is_empty(), "The IML fleet is not instantiated")
	var director := get_first_node_in_group("emergency_depot_director")
	check(is_instance_valid(director) and not director.DEPOTS.has("coroner"), "Harbor has no IML dispatch depot")
	check(director.request_dispatch("coroner", world.get_node("Player")) == null, "Fatalities cannot dispatch a coroner vehicle")
	world.queue_free()
	await process_frame
	print("NO_IML_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)
