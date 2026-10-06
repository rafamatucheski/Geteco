extends RefCounted
## The authoritative mission ledger owns the bridge. No duplicate save flag.
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
static var _baseline_disabled: bool = "--north-gateway-baseline" in OS.get_cmdline_user_args()

static func campaign_completed(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or MISSIONS.ORDER.is_empty(): return false
	if not snapshot.get("completed") is Array or not snapshot.get("legacy_skipped",[]) is Array: return false
	if not CAMPAIGN.validate_snapshot(snapshot): return false
	return snapshot.completed.has(str(MISSIONS.ORDER.back()))

static func baseline_disabled() -> bool:
	# Diagnostic comparison only; production always installs the construction site.
	return _baseline_disabled
