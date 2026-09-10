extends RefCounted
## IDs persistidos continuam estáveis; a interface apresenta nomes legíveis.
static func slot_name(id: String) -> String:
	var en := TranslationServer.get_locale().begins_with("en")
	if id == "autosave": return "Autosave" if en else "Automático"
	return ("Game " if en else "Partida ")+str(id.trim_prefix("slot_").to_int())

static func stage_name(id: String, campaign: Node) -> String:
	var names := {"prologue_call":"The Call","bus_terminal_arrival":"Two Months Later","port_vehicle_job":"Marked Car","trap_and_arrest":"Dead End","ankle_monitor_release":"Supervised Release","garage_and_contracts":"He's Alive","contracts_arc":"Hot List","final_race":"Last Lap","district_one_aftermath":"Open Road"}
	if TranslationServer.get_locale().begins_with("en"): return names.get(id,"Your journey")
	return String(campaign.get_beat(StringName(id)).get("title","Sua jornada"))
