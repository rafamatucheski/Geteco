extends RefCounted
## Recently completed cells retain the exact constructed nodes, including their
## physical shapes and local state. Detached cells cannot process or collide.
## A small LRU bounds retained cells independently of developer overview size.
const MAX_CELLS := 8
var entries: Dictionary = {}
var order: Array[Vector2i] = []
var hits := 0
var misses := 0
var evictions := 0

func take(key: Vector2i) -> Dictionary:
	if not entries.has(key):
		misses += 1
		return {}
	var entry: Dictionary = entries[key]
	entries.erase(key)
	order.erase(key)
	if not is_instance_valid(entry.chunk) or entry.chunk.is_queued_for_deletion():
		misses += 1
		return {}
	hits += 1
	return entry

func put(key: Vector2i, entry: Dictionary) -> Array[Node3D]:
	var retired: Array[Node3D] = []
	if entries.has(key):
		var old: Node3D = entries[key].chunk
		if is_instance_valid(old) and old != entry.chunk: retired.append(old)
	order.erase(key)
	entries[key] = entry
	order.append(key)
	while order.size() > MAX_CELLS:
		var oldest: Vector2i = order.pop_front()
		var stale: Dictionary = entries[oldest]
		entries.erase(oldest)
		if is_instance_valid(stale.chunk): retired.append(stale.chunk)
		evictions += 1
	return retired

func clear() -> Array[Node3D]:
	var retired: Array[Node3D] = []
	for entry: Dictionary in entries.values():
		if is_instance_valid(entry.chunk): retired.append(entry.chunk)
	entries.clear()
	order.clear()
	return retired

func diagnostics() -> Dictionary:
	return {"cells": entries.size(), "limit": MAX_CELLS, "hits": hits, "misses": misses, "evictions": evictions}
