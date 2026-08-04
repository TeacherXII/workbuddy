# tests/unit/test_light_model.gd
# GUT unit tests for the real E04 LightModel (cover-shadow §2 threshold API).
# Covers: L_DARK/L_BRIGHT exposure, get_light_level (shadow box ~0.1 / light
# pool ~1.0), light_sensitivity linear ramp between thresholds, light_state
# events (E04-S4), dirty-cell recompute (E04-S7), and the E04-S5 extinction
# ramp budget (H22 / H23 / N-10).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const LightModel = preload("res://src/game/light_model.gd")


# E04-S5 / N-10 spy: counts mark_cell_dirty calls so the test can prove the
# extinction ramp triggers exactly ONE recompute for the whole cutscene, not one
# per visual frame (0.30s x 60fps = 18 recomputes would violate ADR-002).
class SpyLightModel extends LightModel:
	var dirty_calls: int = 0

	func mark_cell_dirty(cell: Vector3i) -> void:
		dirty_calls += 1
		super(cell)


var _lm: LightModel
var _ramp_ticks: Array = []


func before_each() -> void:
	_lm = LightModel.new()
	watch_signals(_lm)
	_ramp_ticks = []


func after_each() -> void:
	Engine.time_scale = 1.0
	_lm = null


func _on_ramp_tick(density_delta: float, progress: float) -> void:
	_ramp_ticks.append({"delta": density_delta, "progress": progress})


func _peak_delta() -> float:
	var peak := 0.0
	for t in _ramp_ticks:
		peak = maxf(peak, float(t["delta"]))
	return peak


func test_thresholds_exposed_as_constants():
	# E04-S2: thresholds are owned by LightModel, never hardcoded downstream.
	assert_eq(LightModel.L_DARK, 0.20,
		"L_DARK threshold must be 0.20 (cover-shadow §2 / E04-S2)")
	assert_eq(LightModel.L_BRIGHT, 0.60,
		"L_BRIGHT threshold must be 0.60 (cover-shadow §2 / E04-S2)")


func test_light_level_in_shadow_box_is_dark():
	# E04-S1 / cover-shadow §2: inside a shadow box -> dark (~0.1).
	_lm.add_shadow_box(Vector3(3, 0, 3), 2.0)
	var l := _lm.get_light_level(Vector3(3, 0, 3))
	assert_almost_eq(l, 0.1, 0.0001,
		"inside a shadow box get_light_level must be ~0.1 (dark)")


func test_light_level_outside_shadow_is_bright():
	# E04-S1 / cover-shadow §2: outside any shadow box -> light pool (~1.0).
	_lm.add_shadow_box(Vector3(3, 0, 3), 2.0)
	var l := _lm.get_light_level(Vector3(0, 0, 0))
	assert_almost_eq(l, 1.0, 0.0001,
		"outside any shadow box get_light_level must be ~1.0 (light pool)")


func test_sensitivity_below_dark_is_zero():
	# vision-cone §2: L <= L_DARK -> visibility 0.0.
	assert_eq(_lm.light_sensitivity(0.20), 0.0,
		"at L_DARK sensitivity must be 0.0")
	assert_eq(_lm.light_sensitivity(0.10), 0.0,
		"well below L_DARK sensitivity must be 0.0")


func test_sensitivity_above_bright_is_one():
	# vision-cone §2: L >= L_BRIGHT -> visibility 1.0 (light pool必检测).
	assert_eq(_lm.light_sensitivity(0.60), 1.0,
		"at L_BRIGHT sensitivity must be 1.0")
	assert_eq(_lm.light_sensitivity(0.90), 1.0,
		"well above L_BRIGHT sensitivity must be 1.0")


func test_sensitivity_linear_between_thresholds():
	# vision-cone §2: sensitivity = (L - L_DARK) / (L_BRIGHT - L_DARK).
	# (0.40 - 0.20) / (0.60 - 0.20) = 0.5
	assert_almost_eq(_lm.light_sensitivity(0.40), 0.5, 0.0001,
		"midpoint must be linear 0.5")
	# (0.30 - 0.20) / 0.40 = 0.25
	assert_almost_eq(_lm.light_sensitivity(0.30), 0.25, 0.0001,
		"quarter point must be linear 0.25")


const EventBus = preload("res://src/core/event_bus.gd")


func test_get_cover_blocks_los():
	# E04-S3: get_cover returns true for a spot adjacent to an occluder (in its
	# penumbra -> LOS-interruption candidate) and false for open space.
	# Cover is NOT invincibility (C-03 / G-03): it only lowers visibility + offers
	# a LOS break, confirmed by the vision cone via has_line_of_sight (E05-S6).
	_lm.add_cover_box(Vector3(3, 0, 3), 2.0)
	# point on the occluder edge -> within solid radius -> cover
	assert_true(_lm.get_cover(Vector3(3, 0, 1)),
		"point on occluder edge must read as cover")
	# point in the penumbra band (distance 1.5 <= radius+penumbra=3.0) -> cover
	assert_true(_lm.get_cover(Vector3(3, 0, 4.5)),
		"point in penumbra band must read as cover")
	# open point far from any occluder -> no cover
	assert_false(_lm.get_cover(Vector3(0, 0, 0)),
		"open point must not read as cover")


func test_light_state_changed_emitted_with_state():
	# E04-S4: changing a light's state updates the LightState dict and emits
	# light_state_changed(light_id, state) with the §2 signature.
	assert_eq(_lm.get_light_state(1), EventBus.LightState.LIT,
		"default light state must be LIT")
	_lm.set_light_state(1, EventBus.LightState.EXTINGUISHED)
	assert_signal_emitted_with_parameters(_lm, "light_state_changed",
		[1, EventBus.LightState.EXTINGUISHED],
		"light_state_changed must emit with (light_id, state)")
	assert_eq(_lm.get_light_state(1), EventBus.LightState.EXTINGUISHED,
		"LightState dict must update on change")
	_lm.toggle_light(1)
	assert_eq(_lm.get_light_state(1), EventBus.LightState.LIT,
		"toggle must restore LIT")


func test_light_change_recomputes_only_dirty_cell():
	# E04-S7: a light change only recomputes LightLevel for targets inside the
	# affected cell (O(cell), not the whole grid). Cell sizing = SpatialHashGrid3D.CELL.
	# Two cells: origin cell (0,0,0) and a cell ~20m away (1,0,0).
	_lm.register_target(1, Vector3(0, 0, 0))    # cell (0,0,0)
	_lm.register_target(2, Vector3(20, 0, 0))   # cell (1,0,0)
	_lm.register_light(10, Vector3(0, 0, 0))    # light inside cell (0,0,0)
	_lm.set_light_state(10, EventBus.LightState.EXTINGUISHED)
	# only target 1 (dirty cell) should be recomputed; target 2 untouched.
	assert_eq(_lm.get_recomputed_targets(), [1],
		"only the dirty cell's target must be recomputed")
	assert_false(2 in _lm.get_recomputed_targets(),
		"target in another cell must NOT be recomputed")
	# a distant light change must recompute the other cell, not the first.
	_lm.register_light(11, Vector3(20, 0, 0))
	_lm.set_light_state(11, EventBus.LightState.EXTINGUISHED)
	assert_eq(_lm.get_recomputed_targets(), [2],
		"a light in the second cell recomputes only that cell's target")


# ===================== E04-S5 extinction cutscene (H22 / H23 / N-10) =====================

func test_light_toggle_ramp_within_budget() -> void:
	# @ci:R-05 — the extinction fog ramp must stay within budget:
	# peak additive delta <= 0.12, lifetime <= 0.4s, returns to 0 after t>1,
	# density_at clamps base to the R-04 ceiling, and vignette must NOT be linear.
	var peak := 0.0
	for i in range(0, 101):
		var t := float(i) / 100.0
		peak = maxf(peak, LightModel.fog_ramp_delta(t))
	assert_lte(peak, LightModel.FOG_RAMP_PEAK,
		"R-05: fog ramp peak (additive above base) must be <= 0.12")
	assert_lte(LightModel.FOG_RAMP_PEAK, peak + 0.0001,
		"R-05: the FOG_RAMP_PEAK constant must actually equal the sampled peak (sanity; not a dead value)")
	assert_lte(LightModel.FOG_RAMP_RT, LightModel.FOG_RAMP_MAX_RT,
		"R-05: chosen lifetime 0.30s <= hard ceiling 0.40s")

	# Edge ③: t > 1 must collapse delta to 0 (no permanent thick fog on a dt spike).
	assert_almost_eq(LightModel.fog_ramp_delta(1.5), 0.0, 0.0001,
		"R-05/edge③: delta must be 0 once t > 1 (sin(PI)=0)")

	# Edge ②: a base density above the R-04 ceiling is clamped to 0.05 BEFORE adding.
	var dense := LightModel.fog_density_at(0.5, 0.9)
	assert_almost_eq(dense, LightModel.FOG_BASE_MAX + LightModel.fog_ramp_delta(0.5), 0.0001,
		"R-04/edge②: base clamped to FOG_BASE_MAX before adding the ramp delta")

	# V-06: vignette transition must be eased, NEVER a hard linear step.
	assert_ne(LightModel.VIGNETTE_TRANS, Tween.TRANS_LINEAR,
		"V-06: transition must be eased (TRANS_SINE), never TRANS_LINEAR (hard cut)")


func test_light_ramp_single_recompute() -> void:
	# ★ N-10 guard: the extinction ramp must NOT re-enter mark_cell_dirty.
	# toggle_light() flips state + recomputes the dirty cell exactly ONCE;
	# the entire visual ramp (every update_ramp frame) must add ZERO recomputes.
	var spy: SpyLightModel = autofree(SpyLightModel.new())
	watch_signals(spy)
	spy.register_light(10, Vector3(0, 0, 0))
	spy.register_target(1, Vector3(0, 0, 0))
	spy.fog_ramp_tick.connect(_on_ramp_tick)

	# Toggle OFF -> set_light_state recomputes the dirty cell (1 call) + begins ramp.
	spy.toggle_light(10)
	assert_eq(spy.get_light_state(10), EventBus.LightState.EXTINGUISHED)
	assert_eq(spy.dirty_calls, 1,
		"N-10: exactly ONE mark_cell_dirty from the toggle (state flip)")
	assert_true(spy.is_ramp_active(), "the extinction ramp should be active after toggle")

	# Simulate several visual frames during the ramp. No mark_cell_dirty may occur.
	for i in range(5):
		spy.update_ramp()
	assert_eq(spy.dirty_calls, 1,
		"N-10: the extinction ramp must NOT trigger any further mark_cell_dirty")
	assert_lte(_peak_delta(), LightModel.FOG_RAMP_PEAK,
		"N-10: every per-frame fog delta stays within the R-05 peak during the ramp")

	# Edge ④: ramp progress is real-clock driven; Engine.time_scale must NOT
	# affect it. Backdate the start and confirm update_ramp reaches t>=1.0.
	Engine.time_scale = 0.1   # if the ramp wrongly used scaled time, this would stall it
	spy._ramp_start_rt = Time.get_ticks_msec() / 1000.0 - LightModel.FOG_RAMP_RT - 0.05
	spy.update_ramp()
	assert_false(spy.is_ramp_active(),
		"R-04/edge④: ramp completes via real clock despite Engine.time_scale = 0.1")

	# R-02 x V-06: the realtime light is released at ramp END, not at t==0.
	assert_eq(spy.get_released_lights(), [10],
		"R-02 x V-06: realtime light released at ramp END (t>=1.0), not start [N-10]")
	# Crucially the ramp never recomputed the cell again (only the toggle did).
	assert_eq(spy.dirty_calls, 1,
		"N-10: after the full ramp, mark_cell_dirty is STILL exactly 1")

	# Edge ①: toggling again DURING a cutscene must RESET, not叠加 (a second sin
	# would peak at 0.24 and blow R-05). Reset keeps a single ramp -> peak <= 0.12.
	# (Uses a SEPARATE spy: each real toggle legitimately recomputes its dirty cell,
	#  so we assert the RAMP property here, not the dirty count.)
	var spy2: SpyLightModel = autofree(SpyLightModel.new())
	watch_signals(spy2)
	spy2.register_light(20, Vector3(5, 0, 5))
	spy2.toggle_light(20)   # begin ramp
	spy2.toggle_light(20)   # back to LIT (no ramp begin on re-light)
	spy2.toggle_light(20)   # re-extinguish -> ramp re-begins (reset, not stacked)
	assert_true(spy2.is_ramp_active(), "second extinguish re-begins the ramp (reset)")
	var reset_peak := 0.0
	for i in range(0, 11):
		var t := float(i) / 10.0
		reset_peak = maxf(reset_peak, LightModel.fog_ramp_delta(t))
	assert_lte(reset_peak, LightModel.FOG_RAMP_PEAK,
		"N-10/edge①: reset ramp still single-peak <= FOG_RAMP_PEAK (no叠加)")
