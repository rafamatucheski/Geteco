extends RefCounted
## Water belongs to the incident, so two hoses cooperate and interruptions
## preserve work. Only the responder that reaches completion closes the job.
const HOSE_SECONDS := 4.8
const PROGRESS_META := &"fire_water_progress"

static func is_active(target: Node2D) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() \
		and (target.has_method("extinguish_fire") or target.has_node("ResidualFire")) \
		and not target.get_meta("service_complete", false) \
		and (target.get("is_exploding") != false or target.get_meta("fire_residual_burning", false))

static func apply_water(target: Node2D, seconds: float) -> bool:
	if not is_active(target): return true
	if seconds <= 0.0: return false
	var duration := maxf(0.5, float(target.get_meta("fire_hose_seconds", HOSE_SECONDS)))
	var progress := clampf(float(target.get_meta(PROGRESS_META, 0.0)) + seconds / duration, 0.0, 1.0)
	target.set_meta(PROGRESS_META, progress)
	if target.has_method("update_fire_suppression"):
		target.update_fire_suppression(progress)
	var residual := target.get_node_or_null("ResidualFire")
	if is_instance_valid(residual): residual.update_fire_suppression(progress)
	if progress < 1.0: return false
	if target.has_method("extinguish_fire"): target.extinguish_fire()
	if is_instance_valid(residual): residual.finish()
	target.set_meta("service_complete", true)
	target.remove_meta(PROGRESS_META)
	target.remove_meta("fire_response_assigned")
	return true
