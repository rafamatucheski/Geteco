extends RefCounted
## Optional backpack bridge. The backpack owns unlock, item identity and capacity.
## Provider contract: is_backpack_unlocked(), storage_items() -> Dictionary
## {id: {label: String, count: int}}, remove_storage_item(id,count) -> bool,
## add_storage_item(id,count) -> bool. Failed mutations must leave inventory intact.
## Bind through session.residence_services.storage.bind_inventory(provider).
const CAPACITY := 24
const STACK_LIMIT := 99
var provider: Object

func bind_inventory(inventory: Object) -> bool:
	if not is_instance_valid(inventory): return false
	for method in ["is_backpack_unlocked","storage_items","remove_storage_item","add_storage_item"]:
		if not inventory.has_method(method): return false
	provider = inventory
	return true

func unlocked() -> bool:
	return is_instance_valid(provider) and provider.is_backpack_unlocked() == true

func items() -> Dictionary:
	if not unlocked(): return {}
	var source: Variant = provider.storage_items()
	return source if source is Dictionary else {}

func deposit(chest: Dictionary, id: String) -> bool:
	if not unlocked() or not valid_id(id): return false
	var available: Variant = items().get(id,{})
	if not available is Dictionary or int(available.get("count",0)) < 1: return false
	if int(chest.get(id,0)) >= STACK_LIMIT or (not chest.has(id) and chest.size() >= CAPACITY): return false
	if provider.remove_storage_item(id,1) != true: return false
	chest[id] = int(chest.get(id,0))+1
	return true

func withdraw(chest: Dictionary, id: String) -> bool:
	if not unlocked() or int(chest.get(id,0)) < 1: return false
	if provider.add_storage_item(id,1) != true: return false
	chest[id] = int(chest[id])-1
	if chest[id] == 0: chest.erase(id)
	return true

static func valid_id(id: Variant) -> bool:
	return id is String and not id.is_empty() and id.length() <= 96 and id.is_valid_identifier()

static func validate_chest(value: Variant) -> bool:
	if not value is Dictionary or value.size() > CAPACITY: return false
	for id in value:
		if not valid_id(id): return false
		var count: Variant = value[id]
		if typeof(count) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(count)) or float(count) != floorf(float(count)) or count < 1 or count > STACK_LIMIT: return false
	return true
