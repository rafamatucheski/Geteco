extends RefCounted
## Keep the loading screen responsive without paying a full display frame for
## every small cached item. Gameplay callers retain the one-item-per-frame pace.
const BUDGET_USEC := 6000
var _started_us := Time.get_ticks_usec()

func checkpoint(tree: SceneTree) -> void:
	var loading := tree.root.get_node_or_null("GameLoading")
	if loading == null or not loading.active or Time.get_ticks_usec() - _started_us >= BUDGET_USEC:
		await tree.process_frame
		_started_us = Time.get_ticks_usec()
