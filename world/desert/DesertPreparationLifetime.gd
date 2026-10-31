extends RefCounted
## Raízes de apresentação temporárias têm posse explícita mesmo enquanto as
## corrotinas estão suspensas. O cancelamento também funciona no desligamento da árvore,
## quando pode não chegar nenhum process_frame seguinte para retomar essas corrotinas.
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
