class_name SpatialHashGrid3D
extends RefCounted

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 spatial partition. Uniform hash grid backing stealth queries
# (vision-cone candidate gather, sound-propagation radius notify).
#
# Cell size is LOCKED to the maximum guard cone range (~14m) per ADR-002.
# Because cell >= max cone range, a radius query at <= CELL never misses an
# entity straddling a cell boundary (no cross-cell leakage). Insert/remove are
# O(1); query_radius gathers candidate ids from the cells overlapping the
# query sphere (callers do the precise angle/distance filter — ADR-002).

const CELL := 14.0

var _buckets: Dictionary = {}    # String(cellKey "cx,cy,cz") -> Array[int] of entity ids
var _id_to_key: Dictionary = {}  # int(id) -> String(cellKey) for O(1) removal


func _cell_key(pos: Vector3) -> String:
	var cx := int(floor(pos.x / CELL))
	var cy := int(floor(pos.y / CELL))
	var cz := int(floor(pos.z / CELL))
	return "%d,%d,%d" % [cx, cy, cz]


func insert(id: int, pos: Vector3) -> void:
	var key := _cell_key(pos)
	if not _buckets.has(key):
		_buckets[key] = []
	var bucket: Array = _buckets[key]
	if not bucket.has(id):
		bucket.append(id)
	_id_to_key[id] = key


func remove(id: int) -> void:
	if not _id_to_key.has(id):
		return
	var key: String = _id_to_key[id]
	_id_to_key.erase(id)
	if _buckets.has(key):
		var bucket: Array = _buckets[key]
		bucket.erase(id)
		if bucket.is_empty():
			_buckets.erase(key)


func query_radius(center: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var seen: Dictionary = {}  # dedupe ids that could appear in multiple cells
	var min_cx := int(floor((center.x - radius) / CELL))
	var min_cy := int(floor((center.y - radius) / CELL))
	var min_cz := int(floor((center.z - radius) / CELL))
	var max_cx := int(ceil((center.x + radius) / CELL))
	var max_cy := int(ceil((center.y + radius) / CELL))
	var max_cz := int(ceil((center.z + radius) / CELL))
	for cx in range(min_cx, max_cx + 1):
		for cy in range(min_cy, max_cy + 1):
			for cz in range(min_cz, max_cz + 1):
				var key := "%d,%d,%d" % [cx, cy, cz]
				if not _buckets.has(key):
					continue
				for id in _buckets[key]:
					if seen.has(id):
						continue
					seen[id] = true
					result.append(id)
	return result
