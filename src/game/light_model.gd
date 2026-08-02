class_name LightModel
extends RefCounted

# ASHEN STEP — Sprint 1. E04 cover-shadow (get_cover + light_state_changed +
# event-driven dirty-cell recompute). The public API (get_light_level /
# light_sensitivity / get_cover) is stable so the vision cone and AI consume it
# unchanged; the mock internals grow to support light-state events (ADR-004).

const L_DARK := 0.20
const L_BRIGHT := 0.60

const EventBus = preload("res://src/core/event_bus.gd")
const SpatialHashGrid3D = preload("res://src/core/spatial_hash_grid.gd")

# E04-S3: adjacency band (m) around an occluder where a spot counts as "cover"
# (in the penumbra -> LOS-interruption candidate).
const COVER_PENUMBRA := 1.0

var _shadow_boxes: Array = []   # each: {"center": Vector3, "radius": float}

# --- LightState registry (E04-S4) ---
# LightModel owns the authoritative per-light state and emits light_state_changed
# with the §2 signature (light_id:int, state:LightState). The EventBus carries
# the same signal cross-system; this local signal mirrors it so the model can be
# driven/tested without a scene tree (Sprint 0 StepCommit/VisionCone pattern).
signal light_state_changed(light_id: int, state: int)

var _light_states: Dictionary = {}   # light_id -> LightState (int)
var _lights: Dictionary = {}         # light_id -> Vector3 (position)

# --- Target registry + dirty-cell recompute (E04-S7) ---
# Entities (guards/player) that consume a LightLevel. On a light/cover change we
# recompute LightLevel ONLY for targets inside the affected cell (O(cell), not
# O(all)) per ADR-002 / G-03. Cell sizing is locked to SpatialHashGrid3D.CELL.
var _targets: Dictionary = {}            # target_id -> Vector3
var _targets_by_cell: Dictionary = {}    # "cx,cy,cz" -> Array[int] target ids
var _light_cache: Dictionary = {}        # target_id -> float (last computed level)
var _last_recomputed: Array = []         # target_ids recomputed in last dirty pass

var _cover_boxes: Array = []   # each: {"center": Vector3, "radius": float}


# ===================== Shadow / light level (Sprint 0) =====================

func add_shadow_box(center: Vector3, radius: float) -> void:
	_shadow_boxes.append({"center": center, "radius": radius})


func get_light_level(point: Vector3) -> float:
	for box in _shadow_boxes:
		var c: Vector3 = box["center"]
		var r: float = box["radius"]
		if point.distance_to(c) <= r:
			return 0.1   # inside a shadow box -> dark
	return 1.0          # light pool


func light_sensitivity(level: float) -> float:
	if level >= L_BRIGHT:
		return 1.0
	if level <= L_DARK:
		return 0.0
	return (level - L_DARK) / (L_BRIGHT - L_DARK)


# ============================ E04-S3 get_cover ============================

func add_cover_box(center: Vector3, radius: float) -> void:
	# Register an occluder (wall / pillar / large prop). `radius` is the solid
	# footprint; the cover penumbra extends COVER_PENUMBRA beyond it.
	_cover_boxes.append({"center": center, "radius": radius})


func get_cover(pos: Vector3) -> bool:
	# Cover = a spot adjacent to an occluder (within its penumbra band). Such a
	# spot is a LOS-INTERRUPTION CANDIDATE: a guard's line of sight to `pos`
	# passes behind/through the occluder. This ONLY lowers visibility + offers a
	# LOS break (enforced by E05 via SpatialQueryWrapper.has_line_of_sight + a
	# visibility multiplier) -- it does NOT make the target invisible
	# (cover != invincibility; C-03 / G-03). The real LOS test is delegated to
	# the vision cone (E05-S6); here we pre-check geometric adjacency so the
	# query is cheap and non-per-frame.
	for box in _cover_boxes:
		var c: Vector3 = box["center"]
		var r: float = box["radius"]
		if pos.distance_to(c) <= r + COVER_PENUMBRA:
			return true
	return false


# ====================== E04-S4 light_state_changed ========================

func register_light(light_id: int, pos: Vector3) -> void:
	_lights[light_id] = pos


func get_light_state(light_id: int) -> int:
	return _light_states.get(light_id, EventBus.LightState.LIT)


func set_light_state(light_id: int, state: int) -> void:
	_light_states[light_id] = state
	# E04-S7: on a light change, only recompute the cell containing this light
	# (O(cell), not the whole grid). No-op if the light has no registered pos.
	if _lights.has(light_id):
		mark_cell_dirty(_cell_of(_lights[light_id]))
	light_state_changed.emit(light_id, state)


func toggle_light(light_id: int) -> void:
	var cur := get_light_state(light_id)
	var next: int = EventBus.LightState.EXTINGUISHED
	if cur == EventBus.LightState.EXTINGUISHED:
		next = EventBus.LightState.LIT
	set_light_state(light_id, next)


# ======================= E04-S7 dirty-cell recompute =======================

func register_target(target_id: int, pos: Vector3) -> void:
	# Track an entity that consumes a LightLevel, bucketed by grid cell.
	_targets[target_id] = pos
	var key := _cell_key(pos)
	if not _targets_by_cell.has(key):
		_targets_by_cell[key] = []
	_targets_by_cell[key].append(target_id)


func mark_cell_dirty(cell: Vector3i) -> void:
	# Recompute LightLevel only for targets inside `cell`. Driven by
	# light_state_changed (this model) and, in the full wiring, by
	# EventBus.cover_state_changed -> this method (consumer side, E05).
	_last_recomputed = []
	var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
	if not _targets_by_cell.has(key):
		return
	for tid in _targets_by_cell[key]:
		_light_cache[tid] = get_light_level(_targets[tid])
		_last_recomputed.append(tid)


func get_recomputed_targets() -> Array:
	return _last_recomputed


func get_cached_light_level(target_id: int) -> float:
	return _light_cache.get(target_id, -1.0)


# --- cell helpers (locked to SpatialHashGrid3D.CELL, ADR-002) ---

func _cell_of(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / SpatialHashGrid3D.CELL)),
		int(floor(pos.y / SpatialHashGrid3D.CELL)),
		int(floor(pos.z / SpatialHashGrid3D.CELL))
	)


func _cell_key(pos: Vector3) -> String:
	var c := _cell_of(pos)
	return "%d,%d,%d" % [c.x, c.y, c.z]
