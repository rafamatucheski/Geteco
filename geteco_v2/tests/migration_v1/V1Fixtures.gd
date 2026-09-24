extends RefCounted
## Synthetic data shaped only from the productive V1 writers. No user:// access.

static func start() -> Dictionary:
	return {
		"save_version":1,"timestamp":0.0,"date_string":"synthetic","slot_id":"fixture","summary":{},
		"campaign":{
			"schema_version":1,"current_stage":"prologue_call","completed_beats":[],
			"unlocked_regions":["central"],"unlocked_territories":["mercado_velho"],"campaign_flags":{},
			"cobra_campaign":{},"salvage_state":{},"residence_state":{},"race_best_times":{},
			"bank_incident":{},"npc_medical_care":{},"coroner_cases":{},"coroner_staff_serial":0,
		},
		"player":{
			"position":[790.0,1495.0],"rotation":0.0,"health":100,"armor":0,"money":3000,
			"active_weapon_id":"fists","weapon_inventory":{"fists":true,"pistol":false,"smg":false,"shotgun":false,"knife":false,"bat":false,"axe":false,"knuckles":false},
			"weapon_customization":{},"personal_car_state":{},"personal_loadout_enabled":false,
			"personal_loadout":{"curta":"","longa":"","corpo":"","granada":""},"mountain_thermal_coat":false,
			"world_pickups_collected":[],"weapon_ammo":{"fists":{"clip":-1,"reserve":-1}},
			"current_outfit_id":"dante_classic","owned_outfits":{"dante_classic":true},"collectibles_found":[],
			"secret_car_leads":0,"races_finished":0,"races_best_time_count":0,"best_drift_score":0,
			"drift_challenges_completed":0,"chop_shop_deliveries":0,"chop_shop_total_scrap":0,"unlocked_achievements":[],
		},
		"world":{"region":"harbor","coordinates_version":2,"north_access_lower":false},
		"wanted":{"current_stars":0,"crime_points":0,"hidden_time":0.0,"dispatch_timer":0.0,"deployed_this_pursuit":[]},
	}

static func intermediate() -> Dictionary:
	var value := start()
	value.player.money = 4120
	value.player.active_weapon_id = "pistol"
	value.player.weapon_inventory.pistol = true
	value.player.weapon_ammo.pistol = {"clip":7,"reserve":31}
	value.player.collectibles_found = ["harbor_memorial_letter"]
	value.campaign.completed_beats = ["prologue_call"]
	value.campaign.current_stage = "bus_terminal_arrival"
	value.campaign.campaign_flags = {"brother_reported_dead":true,"intro_cgi_seen":true,"harbor_delivery_started":true,"harbor_first_favors_v3":true,"harbor_delivery_receipt":true,"harbor_delivery_picked_up":true,"harbor_delivery_complete":true}
	value.campaign.cobra_campaign = {"completed":{"primeiro_giro":true,"cobra_contact":true},"reward_claimed":{"cobra_contact":true},"active_id":"","stage":""}
	return value

static func interior() -> Dictionary:
	var value := start()
	value.world.region = "mountain"
	value.world.interior = "mountain_cabin"
	value.world.exterior_return = [7350.0,730.0]
	value.world.temperature = 72.5
	value.world.weather_clock = 87.0
	value.player.position = [120.0,80.0]
	return value

static func vehicle() -> Dictionary:
	var value := start()
	value.player.position = [1600.0,800.0]
	value.world.vehicle = {
		"script":"res://cars/traffic/TrafficVehicle.gd","name":"SyntheticCar","archetype":"sport_coupe",
		"paint":"336699ff","x":1600.0,"y":800.0,"rotation":0.25,"values":{"health":70.0},
	}
	return value

static func reward_received() -> Dictionary:
	var value := intermediate()
	value.player.money = 7777
	value.player.world_pickups_collected = ["mountain_bunker_cash_01"]
	return value

static func invalid_format() -> Dictionary:
	var value := start()
	value.save_version = 2
	return value

static func unknown_fields() -> Dictionary:
	var value := start()
	value.future_top_level = {"value":1}
	value.player.future_player_field = "preserve-me"
	value.world.future_world_field = true
	return value
