# tests/unit/test_sound_propagation.gd
# GUT unit tests for the real E06 SoundPropagator (Sprint 1).
# Covers:
#   - E06-S1 emit() + grid radius guard notification (O(guards in radius))
#   - E06-S2 footfall -> SoundPayload from player_step_committed (radius = E03 noise_radius)
#   - E06-S3 ring VFX FIFO cap at RING_CAP=8 (G-02)
#   - E06-S5 distance-attenuation formula sound_in_range = intensity*(1-dist/radius)
#
# All tests are headless-safe: they drive the pure-logic API directly. The only
# tree-dependent code (ring VFX mesh spawn) is gated behind _can_render() and is
# never executed here. No add_child / SceneTree required.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SoundPropagator = preload("res://src/game/sound_propagation.gd")
const SpatialHashGrid3D = preload("res://src/core/spatial_hash_grid.gd")
const EventBus = preload("res://src/core/event_bus.gd")


var _sp: SoundPropagator
var _bus: EventBus
var _grid: SpatialHashGrid3D
var _captured: Dictionary = {}


func before_each() -> void:
	_sp = SoundPropagator.new()
	_bus = EventBus.new()
	_grid = SpatialHashGrid3D.new()
	_sp.set_event_bus(_bus)
	_sp.set_grid(_grid)
	watch_signals(_bus)
	_captured = {}


func after_each() -> void:
	_sp = null
	_bus = null
	_grid = null


func _capture(p: Dictionary) -> void:
	_captured = p


func test_sound_emitted_notifies_guards_in_radius():
	# E06-S1: emit() queries the grid and notifies only guards within radius.
	# Guards at 3m and 12m are inside a 14m radius; 20m is outside (the grid
	# returns bounding-box candidates, so a precise distance filter is required).
	_grid.insert(1, Vector3(0, 0, 3))
	_grid.insert(2, Vector3(0, 0, 12))
	_grid.insert(3, Vector3(0, 0, 20))
	_sp.register_guard(1, Vector3(0, 0, 3))
	_sp.register_guard(2, Vector3(0, 0, 12))
	_sp.register_guard(3, Vector3(0, 0, 20))
	_bus.sound_emitted.connect(_capture)
	var payload := {
		"origin": Vector3.ZERO,
		"radius": 14.0,
		"intensity": 1.0,
		"source": SoundPropagator.SOURCE_FOOTFALL,
	}
	var result := _sp.emit(payload)
	assert_signal_emitted(_bus, "sound_emitted", "emit must broadcast sound_emitted")
	var targets: Array = result.get("target_guard_ids", [])
	assert_true(1 in targets, "guard at 3m must be notified")
	assert_true(2 in targets, "guard at 12m must be notified")
	assert_false(3 in targets, "guard at 20m is outside radius -> not notified")
	assert_eq(targets.size(), 2, "exactly the in-radius guards are notified")
	# The enriched payload is forwarded verbatim to E08.
	assert_eq(_captured.get("radius"), 14.0, "radius must reach E08 unchanged")
	assert_eq(_captured.get("source"), SoundPropagator.SOURCE_FOOTFALL, "source must reach E08")
	assert_eq(_captured.get("origin"), Vector3.ZERO, "origin must reach E08")


func test_sound_emit_cost_is_radius_local():
	# E06-S1 / G-03: an empty grid still emits (cost scales with guards in radius,
	# not with total guard count or frame rate).
	_bus.sound_emitted.connect(_capture)
	var result := _sp.emit({"origin": Vector3.ZERO, "radius": 5.0, "intensity": 0.6, "source": SoundPropagator.SOURCE_FOOTFALL})
	assert_signal_emitted(_bus, "sound_emitted")
	assert_eq(result.get("target_guard_ids", []).size(), 0, "no guards -> empty notify list")
	assert_eq(_captured.get("intensity"), 0.6, "intensity reaches E08")


func test_footfall_emits_sound_with_radius():
	# E06-S2: a player_step_committed (carrying E03 noise_radius) is translated
	# into a FOOTFALL SoundPayload with that radius (never recomputed here).
	_sp._bind_bus()
	_bus.sound_emitted.connect(_capture)
	var step := {
		"from": Vector3.ZERO,
		"to": Vector3(0, 0, 3),
		"surface": "STONE",
		"gait": "WALK",
		"noise_radius": 5.0,   # WALK+STONE from E03
	}
	_bus.player_step_committed.emit(step)
	assert_signal_emitted(_bus, "sound_emitted", "footfall must emit sound_emitted")
	assert_eq(_captured.get("radius"), 5.0, "radius must equal E03 noise_radius (5.0)")
	assert_eq(_captured.get("origin"), Vector3(0, 0, 3), "origin must equal the landing point")
	assert_eq(_captured.get("source"), SoundPropagator.SOURCE_FOOTFALL, "source must be FOOTFALL")
	assert_eq(_captured.get("intensity"), SoundPropagator.GAIT_INTENSITY["WALK"],
		"intensity must be gait-derived (WALK=0.6)")


func test_footfall_intensity_derived_from_gait():
	# E06-S2: intensity follows gait (SNEAK quieter, RUN louder) but radius is
	# always the E03-provided value.
	_sp._bind_bus()
	_bus.sound_emitted.connect(_capture)
	_bus.player_step_committed.emit({"to": Vector3.ZERO, "gait": "SNEAK", "noise_radius": 2.5})
	assert_eq(_captured.get("intensity"), 0.3, "SNEAK -> 0.3")
	_bus.player_step_committed.emit({"to": Vector3.ZERO, "gait": "RUN", "noise_radius": 10.0})
	assert_eq(_captured.get("intensity"), 1.0, "RUN -> 1.0")


func test_ring_vfx_capped_at_eight():
	# E06-S3 / G-02: requesting >8 rings keeps at most 8 alive (FIFO eviction).
	for i in range(10):
		_sp.request_ring(Vector3(float(i), 0, 0), 5.0, SoundPropagator.SOURCE_FOOTFALL)
	assert_eq(_sp._rings.size(), SoundPropagator.RING_CAP, "active rings must cap at RING_CAP")
	assert_eq(_sp._rings.size(), 8, "must be exactly 8")
	# FIFO: oldest two (seq 1,2) evicted; first surviving is seq 3, newest is 10.
	assert_eq(_sp._rings[0]["seq"], 3, "FIFO must evict the oldest ring first")
	assert_eq(_sp._rings[7]["seq"], 10, "newest ring must be retained")
	assert_false(_sp.is_over_ring_budget(), "budget is enforced, never exceeded")


func test_ring_vfx_not_built_headless():
	# E06-S3: ring visuals are gated; headless request only updates accounting.
	_sp.request_ring(Vector3.ZERO, 5.0, SoundPropagator.SOURCE_FOOTFALL)
	assert_eq(_sp._rings.size(), 1, "ring accounting records the request headless")
	# No rendering assertion needed: _can_render() is false without a tree.


func test_suspicion_from_sound_distance():
	# E06-S5 (stub): sound_in_range = intensity * (1 - dist/radius). Full E08
	# integration (accumulating suspicion) is Batch C.
	var I := 1.0
	var R := 10.0
	assert_almost_eq(_sp.suspicion_from_distance(I, 0.0, R), 1.0, 0.0001, "at origin -> full intensity")
	assert_almost_eq(_sp.suspicion_from_distance(I, R, R), 0.0, 0.0001, "at radius -> zero")
	assert_almost_eq(_sp.suspicion_from_distance(I, R * 0.5, R), 0.5, 0.0001, "mid -> half")
	assert_almost_eq(_sp.suspicion_from_distance(I, R * 1.5, R), 0.0, 0.0001, "beyond radius -> zero")
	# Gait-derived intensity maps sensibly.
	assert_almost_eq(_sp.suspicion_from_distance(0.6, 0.0, R), 0.6, 0.0001, "WALK intensity 0.6")
	assert_almost_eq(_sp.suspicion_from_distance(0.3, R * 0.5, R), 0.15, 0.0001,
		"SNEAK half-range -> 0.3 * 0.5 = 0.15")


func test_suspicion_from_sound_distance_zero_radius_safe():
	# E06-S5: a degenerate (zero) radius must not divide-by-zero.
	assert_eq(_sp.suspicion_from_distance(1.0, 0.0, 0.0), 0.0, "zero radius -> no sound")
