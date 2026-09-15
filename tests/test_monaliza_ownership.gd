extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
 print(("PASS " if value else "FAIL ") + label)
 if not value: failures += 1
func run() -> void:
 root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", false)
 change_scene_to_file("res://world/harbor/HarborGame.tscn")
 for i in 30: await process_frame
 var manager: Node = current_scene.get_node("PersonalCarManager")
 var car: Node = manager.car
 var player: Node = manager.player
 check(not car.visible and car.collision_layer == 0, "absent before delivery")
 root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
 manager._grant(false)
 check(car.visible and car.unlocked, "appears after reward")
 var identity: int = car.get_instance_id()
 player.global_position = manager.bay_position()
 car.global_position += Vector2(500, 0)
 player.money = 100
 check(not manager.recover() and player.money == 100, "parked car cannot be summoned or charged")
 car.is_broken = true
 car.health = 0
 check(manager.recover() and player.money == 50, "destroyed car recovered for 50")
 check(car.get_instance_id() == identity and car.health == 180, "same car repaired without duplicate")
 car.is_driven_by_player = true
 manager.impound_if_driven()
 check(manager.impounded and not car.visible, "police impound removes world car")
 car.enter_vehicle(player)
 check(not car.is_driven_by_player, "impounded car cannot be entered before payment")
 manager.capture_state()
 manager.restore_from_player()
 check(manager.impounded and not car.visible, "impound persists on restore")
 player.global_position = manager.bay_position()
 check(manager.recover() and player.money == 0, "impounded car released for 50")
 paused = false
 manager.show_introduction()
 check(paused and manager.introduction.page == 0, "introduction pauses driving")
 manager.introduction.advance()
 check(manager.introduction.page == 1 and manager.introduction.sound.playing, "next message plays sound")
 manager.introduction.advance()
 manager.introduction.advance()
 check(not paused and manager.introduction_seen, "completion restores play and records tutorial")
 manager.capture_state()
 manager.restore_from_player()
 check(manager.introduction_seen, "tutorial completion persists")
 print("OWNERSHIP FAILURES: %d" % failures)
 quit(1 if failures else 0)
