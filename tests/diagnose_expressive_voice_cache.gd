extends SceneTree

## Diagnostic only: confirms ExpressiveVoice.cache (a static Dictionary shared
## process-wide, capped at 32 entries with oldest-key eviction) stabilizes
## instead of growing unbounded when the Harbor district is entered/exited
## repeatedly. Each cycle re-triggers HarborArrivalMission.configure()'s
## PHONE_LINES pre-warm, which is what test_harbor_terminal.gd's "4 ObjectDB
## instances remained" warning traced back to. Does not change any behavior.

const GAME := preload("res://world/harbor/HarborGame.tscn")
const VOICE := preload("res://ExpressiveVoice.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	print("CACHE_SIZE_BEFORE_ANY_CYCLE %d" % VOICE.cache.size())
	for cycle in 6:
		campaign.reset_campaign()
		for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
			campaign.set_campaign_flag(StringName(flag), true)
		var world := GAME.instantiate()
		root.add_child(world)
		current_scene = world
		for i in 15: await process_frame
		print("CACHE_SIZE cycle=%d size=%d keys=%s" % [cycle, VOICE.cache.size(), VOICE.cache.keys()])
		world.queue_free()
		await process_frame
	quit()
