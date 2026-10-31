extends RefCounted
## O registro autoritativo de missões é dono da ponte. Sem flag de save duplicada.
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
static var _baseline_disabled: bool = "--north-gateway-baseline" in OS.get_cmdline_user_args()

static func campaign_completed(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or MISSIONS.ORDER.is_empty(): return false
	if not snapshot.get("completed") is Array or not snapshot.get("legacy_skipped",[]) is Array: return false
	if not CAMPAIGN.validate_snapshot(snapshot): return false
	return snapshot.completed.has(str(MISSIONS.ORDER.back()))

static func baseline_disabled() -> bool:
	# Só comparação de diagnóstico; a produção sempre instala o canteiro de obras.
	return _baseline_disabled
