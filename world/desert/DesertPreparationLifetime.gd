extends RefCounted
## Temporary presentation roots have explicit ownership even while their
## coroutines are suspended. Cancellation also works during tree shutdown,
## when no following process_frame may arrive to resume those coroutines.
static func track(token: Dictionary, node: Node) -> void:
	if token.is_empty(): return
	if not token.has("roots"): token.roots=[]
	token.roots.append(weakref(node))

static func release(token: Dictionary, node: Node) -> void:
	if token.is_empty(): return
	var remaining: Array=[]
	for reference in token.get("roots",[]):
		if is_instance_valid(reference.get_ref()) and reference.get_ref()!=node: remaining.append(reference)
	token.roots=remaining

static func cancelled(token: Dictionary) -> bool:
	if not bool(token.get("cancelled",false)): return false
	cancel(token)
	return true

static func cancel(token: Dictionary) -> void:
	token["cancelled"]=true
	for reference in token.get("roots",[]):
		var node: Variant=reference.get_ref()
		if is_instance_valid(node) and node.get_parent()==null: node.free()
	token["roots"]=[]
