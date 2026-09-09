extends RefCounted
## Old saves retain their original map; new Harbor saves use a persisted flag.
const GAME := "res://district/harbor_preview/HarborGame.tscn"
const LEGACY := "res://Main.tscn"

static func for_save(data: Dictionary) -> String:
	if data.get("world", {}).get("region", "") == "mountain":
		return GAME
	var campaign: Dictionary = data.get("campaign", {})
	var flags: Dictionary = campaign.get("campaign_flags", {})
	return GAME if bool(flags.get("harbor_campaign_active", false)) else LEGACY
