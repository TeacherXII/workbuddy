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

# SoundSource mirror (system-breakdown §2.3).
const SOURCE_FOOTFALL := "FOOTFALL"
const SOURCE_DECOY := "DECOY"
const SOURCE_TRAP := "TRAP"
const SOURCE_AMBIENT := "AMBIENT"

# ── E06-S4 (Batch D) DECOY constants ─────────────────────────────────────────
const DECOY_RADIUS := 8.0        # m  interactables.md §2 "radius~8m"
                                 #    [D11-A] CONSTANT — no SURFACE_FACTOR
                                 #    modulation in Sprint 1. Revisit with the
                                 #    E07 throwable entity (Sprint 2).
const DECOY_INTENSITY := 1.0     # -  normalised loudness [0,1]. DECOY is a
                                 #    full-loudness event (contrast: footfall
                                 #    intensity is gait/surface-modulated). Do
                                 #    NOT raise above 1.0 — that breaks the
                                 #    [0,1] contract shared with footfall and
                                 #    pollutes suspicion_from_distance.

# Cold-white ring color (C-05: shape/size-coded, cool tone, not a danger hue).
const RING_COLOR := Color("#9FB8C9")
# E09-S3: normal vs "focus readable" ring alpha.
const RING_ALPHA_BASE := 0.25
const RING_ALPHA_BOOST := 0.45

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
var _readability_boost := false


func _ready() -> void:
	if _grid == null:
		_grid = SpatialHashGrid3D.new()
	_bind_bus()


func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_bind_bus()


func set_grid(grid: SpatialHashGrid3D) -> void:
	_grid = grid


# E09-S3: readability orchestration (duck-typed; HudSlice only calls this and
# never touches our material). Boost lifts the ring one alpha step.
func set_readability_boost(on: bool) -> void:
	_readability_boost = on


func ring_alpha() -> float:
	return RING_ALPHA_BOOST if _readability_boost else RING_ALPHA_BASE


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
	if not _bus.decoy_landed.is_connected(_on_decoy_landed):
		_bus.decoy_landed.connect(_on_decoy_landed)


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


# --- E06-S4: decoy -> SoundPayload. -----------------------------------------
# DECOY is a SIGNAL-LEVEL sound source in Sprint 1: the physical throwable
# entity (E07) is deferred to Sprint 2 (plan D2), so anything that can emit
# EventBus.decoy_landed produces a real sound ring today.
func _on_decoy_landed(pos: Vector3, surface: String, radius: float) -> void:
	# [D11-A] `surface` is forwarded for foley / subtitle variant selection ONLY.
	# It MUST NOT participate in the radius computation — see the reverse
	# evidence in test_sound_propagation.gd::test_decoy_surface_is_foley_only.
	#
	# Edge (1): a non-positive radius (uninitialised sender, bad level data)
	# falls back to the nominal radius. Emitting a 0m ring would be a silent dud
	# — the player hears the throw but no guard can ever be in range.
	var r: float = radius if radius > 0.0 else DECOY_RADIUS
	emit({
		"origin": pos,
		"radius": r,
		"intensity": DECOY_INTENSITY,
		"source": SOURCE_DECOY,
		"surface": surface,       # read-only passenger; never enters a formula
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
	# [D11-A] Optional foley/subtitle passenger (E06-S4). enriched is rebuilt
	# from a fixed key set above, so an un-forwarded `surface` would be silently
	# dropped here and the parameter would become dead on arrival. It is copied
	# verbatim and is never read by any numeric path in this class.
	if payload.has("surface"):
		enriched["surface"] = payload["surface"]
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
	mat.emissive_intensity = ring_alpha()
	var col := RING_COLOR
	col.a = ring_alpha()
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
	var d: float = max(0.0, dist)
	var factor: float = 1.0 - (d / radius)
	return max(0.0, intensity * factor)


func _can_render() -> bool:
	return Engine.get_main_loop() != null and is_inside_tree()
