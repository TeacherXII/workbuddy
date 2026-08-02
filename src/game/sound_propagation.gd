class_name SoundPropagator
extends Node

# ASHEN STEP — Sprint 1 (Phase 5), E06 sound-propagation.
# Owns SoundPayload emission + radius-grid guard notification + ring VFX cap.
#
# Wiring (E06-S2): subscribes to EventBus.player_step_committed and translates a
# footfall into a SoundPayload (radius = E03 noise_radius, intensity from gait).
# The canonical owner of `sound_emitted` is THIS class; the Sprint 0 path
# (StepCommit.sound_emitted -> bus, see sprint0_bootstrap.gd) is legacy and is
# flagged as a Batch A gap in the Batch B report (it double-emits and bypasses
# the grid/ring enrichment). It is NOT modified here.
#
# Headless-safe: every public entry point is pure logic. The only tree-dependent
# work is the ring VFX spawn, gated behind _can_render() (same pattern as
# footfall_vfx / step_commit).

const SpatialHashGrid3D = preload("res://src/core/spatial_hash_grid.gd")
const EventBus = preload("res://src/core/event_bus.gd")

# E06-S3: same-screen ring VFX cap (control-manifest G-02, FIFO eviction).
const RING_CAP := 8

# E06-S2: gait -> sound intensity (drives E08 suspicion with KS15 scaling).
const GAIT_INTENSITY := {
	"SNEAK": 0.3,
	"WALK": 0.6,
	"RUN": 1.0,
}

# SoundSource mirror (system-breakdown §2.3). E06-S4 (DECOY) is Batch D.
const SOURCE_FOOTFALL := "FOOTFALL"
const SOURCE_DECOY := "DECOY"
const SOURCE_TRAP := "TRAP"
const SOURCE_AMBIENT := "AMBIENT"

# Cold-white ring color (C-05: shape/size-coded, cool tone, not a danger hue).
const RING_COLOR := Color("#9FB8C9")

var _bus: EventBus = null
var _grid: SpatialHashGrid3D = null
# Guard id -> world position. The grid is the cheap spatial GATHER (ADR-002:
# O(1) bucket lookup), but query_radius returns bounding-box CANDIDATES, so the
# precise in-radius test needs real positions. The guard/AI system populates and
# updates this on guard_transform_dirty (Batch C); Batch B exposes the API and
# tests it. Without it, emit() cannot distance-filter.
var _guard_positions: Dictionary = {}
var _rings: Array = []          # active ring records (FIFO-capped at RING_CAP)
var _ring_seq := 0


func _ready() -> void:
	if _grid == null:
		_grid = SpatialHashGrid3D.new()
	_bind_bus()


func set_event_bus(bus: EventBus) -> void:
	_bus = bus


func set_grid(grid: SpatialHashGrid3D) -> void:
	_grid = grid


# --- Guard position registry (precise in-radius test; see _guard_positions). ---
func register_guard(id: int, pos: Vector3) -> void:
	_guard_positions[id] = pos


func update_guard(id: int, pos: Vector3) -> void:
	_guard_positions[id] = pos


func remove_guard(id: int) -> void:
	_guard_positions.erase(id)


# Connect gameplay-layer inputs. Called from _ready AND directly by headless tests
# (which don't trigger _ready), so guard against double-connect.
func _bind_bus() -> void:
	if _bus == null:
		return
	if not _bus.player_step_committed.is_connected(_on_player_step_committed):
		_bus.player_step_committed.connect(_on_player_step_committed)


# --- E06-S2: footfall -> SoundPayload. Radius is taken verbatim from E03's
# noise_radius (never recomputed/ inflated here, sound-propagation §2). ---
func _on_player_step_committed(payload: Dictionary) -> void:
	var origin: Vector3 = payload.get("to", Vector3.ZERO)
	var radius: float = float(payload.get("noise_radius", 0.0))
	var gait: String = payload.get("gait", "WALK")
	var intensity: float = float(GAIT_INTENSITY.get(gait, GAIT_INTENSITY["WALK"]))
	emit({
		"origin": origin,
		"radius": radius,
		"intensity": intensity,
		"source": SOURCE_FOOTFALL,
	})


# --- E06-S1: emit a sound event; notify guards in radius via the grid. ---
# Returns the enriched SoundPayload so callers/tests can inspect it. Cost is
# O(guards in radius) — one grid query + one bus broadcast + a ring request.
func emit(payload: Dictionary) -> Dictionary:
	var origin: Vector3 = payload.get("origin", Vector3.ZERO)
	var radius: float = float(payload.get("radius", 0.0))
	var intensity: float = float(payload.get("intensity", 0.0))
	var source: String = payload.get("source", SOURCE_FOOTFALL)
	var enriched := {
		"origin": origin,
		"radius": radius,
		"intensity": intensity,
		"source": source,
	}
	# E06-S1: grid query -> candidate guard ids, then precise in-radius filter
	# (query_radius returns bounding-box candidates; ADR-002 leaves the exact
	# distance test to the caller). Cost stays O(candidates in radius box).
	var targets: Array = []
	if _grid != null:
		var candidates: Array = _grid.query_radius(origin, radius)
		for gid in candidates:
			if _guard_positions.has(gid):
				var gp: Vector3 = _guard_positions[gid]
				if origin.distance_to(gp) <= radius:
					targets.append(gid)
	enriched["target_guard_ids"] = targets
	# Player-readable wave (FIFO-capped, E06-S3).
	request_ring(origin, radius, source)
	# Broadcast to E08 (which computes per-guard distance attenuation, E06-S5).
	if _bus != null:
		_bus.sound_emitted.emit(enriched)
	return enriched


# --- E06-S3: ring VFX request with FIFO cap. Pure accounting; the visual spawn
# is gated behind _can_render(). Headless tests drive this directly. ---
func request_ring(origin: Vector3, radius: float, source: String) -> void:
	_ring_seq += 1
	var rec := {
		"seq": _ring_seq,
		"origin": origin,
		"radius": radius,
		"source": source,
		"created_ms": Time.get_ticks_msec(),
	}
	_rings.append(rec)
	while _rings.size() > RING_CAP:
		var old: Dictionary = _rings.pop_front()
		_destroy_ring_visual(old)
	if _can_render():
		_spawn_ring_visual(rec)


# True when the active ring set exceeds the G-02 budget (used by the Batch D
# CI assertion, §7). The cap is enforced above, so this is normally false.
func is_over_ring_budget() -> bool:
	return _rings.size() > RING_CAP


func _spawn_ring_visual(rec: Dictionary) -> void:
	# Rendering-only: a flat ring that expands + fades (Tween, self-destruct).
	# Synced to time_scale (T-04). Guarded by _can_render(); never runs headless.
	var ring := MeshInstance3D.new()
	ring.mesh = CylinderMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emissive_enabled = true
	mat.emissive_color = RING_COLOR
	mat.emissive_intensity = 0.25
	var col := RING_COLOR
	col.a = 0.25
	mat.albedo_color = col
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.5, 0.02, 0.5)
	ring.position = rec["origin"]
	add_child(ring)
	# Expand to the sound radius and fade out, then self-destruct (keeps the
	# G-02 budget honest without manual GC).
	var tween := create_tween()
	tween.set_speed_scale(Engine.time_scale if Engine.time_scale > 0.0 else 1.0)
	var r := float(rec["radius"])
	tween.tween_property(ring, "scale", Vector3(r, 0.02, r), 0.6)
	# Fade the whole albedo color to transparent (safe Color tween) + drop the
	# emissive intensity (safe float tween), in parallel, then self-destruct.
	var faded := RING_COLOR
	faded.a = 0.0
	tween.parallel().tween_property(mat, "albedo_color", faded, 0.6)
	tween.parallel().tween_property(mat, "emissive_intensity", 0.0, 0.6)
	tween.tween_callback(ring.queue_free)


func _destroy_ring_visual(_rec: Dictionary) -> void:
	# No-op when no visual was spawned (headless). Live visuals self-destruct.
	pass


# --- E06-S5: distance attenuation formula (stub). Full E08 integration
# (accumulating suspicion from sound_emitted) is Batch C; this validates the
# formula sound_in_range = intensity * (1 - dist/radius), clamped to [0, intensity].
func suspicion_from_distance(intensity: float, dist: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var d := max(0.0, dist)
	var factor := 1.0 - (d / radius)
	return max(0.0, intensity * factor)


func _can_render() -> bool:
	return Engine.get_main_loop() != null and is_inside_tree()
