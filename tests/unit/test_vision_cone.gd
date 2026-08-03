# tests/unit/test_vision_cone.gd
# GUT unit tests for the real E05 VisionCone + E04 LightModel.
# Covers: vision-cone §2 visibility formula (InCone * LOS_clear * light factor),
#         with thresholds L_DARK=0.20 / L_BRIGHT=0.60 (from cover-shadow §2).
#
# The Phase 4 smoke stub (VisionConeStub) is removed; this test now preloads the
# real classes. compute_visibility tolerates a null query/light (headless), so
# the test only injects the shared LightModel (with a shadow box) it needs.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const VisionCone = preload("res://src/game/vision_cone.gd")
const LightModel = preload("res://src/game/light_model.gd")


var _vc: VisionCone
var _lm: LightModel
var _loom_count := 0


func before_each() -> void:
	_vc = VisionCone.new()
	_lm = LightModel.new()
	_vc.set_light_model(_lm)        # inject the demo light model
	_vc.observer_pos = Vector3.ZERO
	# NOTE: Godot's Vector3.FORWARD is (0,0,-1). Every target below is placed at
	# +Z, so the observer must LOOK at +Z (Vector3.BACK) for those targets to be
	# inside the cone. Using FORWARD here put every target 180deg BEHIND the
	# observer, so compute_visibility returned 0.0 at the angle gate before ever
	# reaching the LOS/light terms. Production wiring is consistent with BACK:
	# sprint0_bootstrap.gd sets observer_forward to (player - guard).normalized(),
	# i.e. a real direction vector toward the look target.
	_vc.observer_forward = Vector3.BACK
	watch_signals(_vc)
	_loom_count = 0
	_vc.vision_looming.connect(_count_loom)


func _count_loom(_g: int) -> void:
	_loom_count += 1


func after_each() -> void:
	_vc = null
	_lm = null


func test_target_in_light_pool_is_detected():
	# cover-shadow §2 + vision-cone §2: in cone, LOS visible, light pool -> 1.0
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 1.0, "cone + LOS + light pool must yield full visibility")


func test_target_in_shadow_is_invisible():
	# cover-shadow §2: shadow box -> L ~= 0.1 -> visibility ~= 0.0
	_lm.add_shadow_box(Vector3(0, 0, 5), 2.0)
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 0.0, "inside a shadow box the target must be effectively invisible")


func test_target_outside_cone_is_invisible():
	# vision-cone §2: outside the 35deg/14m cone -> 0.0
	var v := _vc.compute_visibility(Vector3(0, 20, 5))
	assert_eq(v, 0.0, "above/behind the cone must yield zero visibility")


func test_cone_constants_align_to_gdd():
	# E05-S1 / ADR-002 / G-03: cone geometry + tick-rate constants.
	assert_eq(VisionCone.HALF_ANGLE_DEG, 35.0, "half-angle must be 35deg")
	assert_eq(VisionCone.RANGE, 14.0, "range must be 14m (= grid cell, ADR-002)")
	assert_eq(VisionCone.TICK_HZ, 10.0, "tick must be 10Hz (G-03)")


func test_phase_offset_initialized_within_tick_window():
	# E05-S1 / G-03: per-guard phase offset so multiple guards don't fire same frame.
	add_child(_vc)  # triggers _ready -> _accum = randf() * (1.0 / TICK_HZ)
	assert_true(_vc._accum >= 0.0, "phase offset must be non-negative")
	assert_true(_vc._accum < 0.1, "phase offset must lie within one tick window (<0.1s)")


func test_no_light_model_assumes_full_light():
	# E05-S2 headless safety: without a light model, full light is assumed.
	_vc.set_light_model(null)
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 1.0, "in cone with no light model -> full visibility (headless safe)")


# =====================================================================
# Batch B — E05-S5 / S6 / S7 (Sprint 1, complete vision cone)
# All tests below are headless-safe: they drive the public/pure API directly
# (no add_child / no SceneTree / no rendering).
# =====================================================================

func test_vision_looming_emitted_at_edge():
	# E05-S5: player inside the 8deg rim warning band -> vision_looming fired
	# exactly once on entry (debounced, not every tick).
	var band := deg_to_rad(VisionCone.HALF_ANGLE_DEG - VisionCone.EDGE_MARGIN_DEG * 0.5)  # ~31deg, inside [27,35]
	_vc.player_pos = Vector3(sin(band), 0, cos(band)) * 5.0
	_vc._edge_warned = false
	_vc._tick_once()
	assert_signal_emitted(_vc, "vision_looming", "entering the rim band must emit vision_looming")
	assert_eq(_loom_count, 1, "tell fires once on entry, not per tick")
	# Staying in the band must NOT re-emit.
	_vc._tick_once()
	assert_eq(_loom_count, 1, "remaining in band must not re-emit")


func test_vision_looming_not_emitted_deep_inside_cone():
	# E05-S5: deep inside the cone (straight ahead) is NOT the rim -> no tell.
	_vc.player_pos = Vector3(0, 0, 5)   # angle 0deg, far from the rim
	_vc._edge_warned = false
	_vc._tick_once()
	assert_signal_not_emitted(_vc, "vision_looming", "deep-in-cone is not an edge tell")


func test_vision_looming_not_emitted_outside_cone():
	# E05-S5: outside the cone -> no tell.
	var out := deg_to_rad(VisionCone.HALF_ANGLE_DEG + 12.0)
	_vc.player_pos = Vector3(sin(out), 0, cos(out)) * 5.0
	_vc._edge_warned = false
	_vc._tick_once()
	assert_signal_not_emitted(_vc, "vision_looming", "outside the cone must not emit")


func test_vision_looming_rearms_after_leaving_band():
	# E05-S5: leaving the band re-arms the tell so a re-entry fires again.
	var rimm := deg_to_rad(VisionCone.HALF_ANGLE_DEG - VisionCone.EDGE_MARGIN_DEG * 0.5)
	var rim_pos := Vector3(sin(rimm), 0, cos(rimm)) * 5.0
	_vc.player_pos = rim_pos
	_vc._edge_warned = false
	_vc._tick_once()
	assert_eq(_loom_count, 1)
	# Leave the band.
	_vc.player_pos = Vector3(0, 0, 5.0)
	_vc._tick_once()
	assert_eq(_loom_count, 1, "still 1 after leaving")
	# Re-enter -> must fire again (re-armed).
	_vc.player_pos = rim_pos
	_vc._tick_once()
	assert_eq(_loom_count, 2, "re-entry re-arms the tell")


func test_visibility_multiplier_smoke():
	# E05-S6 / consistency-review C3: an external multiplier scales visibility.
	# In the light pool (no shadow box, no _light -> full light) base = 1.0.
	var base := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_almost_eq(base, 1.0, 0.0001, "light-pool base visibility must be 1.0")
	# Smoke x0.3.
	var v_smoke := _vc.compute_visibility(Vector3(0, 0, 5), VisionCone.VIS_MULT_SMOKE)
	assert_almost_eq(v_smoke, 0.3, 0.0001, "smoke multiplier must scale visibility to 0.3")
	# Cover x0.6.
	var v_cover := _vc.compute_visibility(Vector3(0, 0, 5), VisionCone.VIS_MULT_COVER)
	assert_almost_eq(v_cover, 0.6, 0.0001, "cover multiplier must scale visibility to 0.6")
	# Out-of-cone target stays 0 regardless of multiplier (multiplier only lowers).
	var v_out := _vc.compute_visibility(Vector3(0, 20, 5), 0.3)
	assert_eq(v_out, 0.0, "out-of-cone target must stay 0 under a multiplier")


func test_visibility_multiplier_only_lowers_not_invincible():
	# E05-S6 / R-03: a multiplier reduces visibility but never makes a seen
	# in-cone target fully invisible (except an explicit 0.0 multiplier).
	var seen := _vc.compute_visibility(Vector3(0, 0, 5), VisionCone.VIS_MULT_COVER)
	assert_true(seen > 0.0, "cover must NOT grant invisibility (R-03)")
	assert_true(seen < 1.0, "cover must lower visibility below full")
	# Explicit 0.0 multiplier fully suppresses (smoke so dense it's silent).
	var silent := _vc.compute_visibility(Vector3(0, 0, 5), 0.0)
	assert_eq(silent, 0.0, "only an explicit 0.0 multiplier zeroes visibility")


func test_cone_vfx_pulse_rate():
	# E05-S7 / V-02: pulse frequency capped at <=2Hz.
	assert_true(VisionCone.CONE_VFX_PULSE_HZ <= 2.0,
		"cone VFX pulse must be <= 2Hz (V-02)")
	# E05-S7 / C-03: brightness contrast between pulse extremes >= 3:1.
	var contrast := VisionCone.CONE_VFX_ALPHA_MAX / VisionCone.CONE_VFX_ALPHA_MIN
	assert_true(contrast >= 3.0,
		"cone VFX brightness contrast must be >= 3:1 (C-03), got %.2f" % contrast)
	# E05-S7 / C-04-C-05: the cone VFX is cold white (blue >= red), i.e. it does
	# NOT rely on a danger hue to communicate the threat.
	assert_true(VisionCone.CONE_VFX_COLOR.b >= VisionCone.CONE_VFX_COLOR.r,
		"cone VFX must be a cool tone (b>=r), not a hue-coded danger color (C-04/C-05)")
	assert_eq(VisionCone.CONE_VFX_COLOR, Color("#9FB8C9"),
		"cone VFX ground spot color must be cold white #9FB8C9")


func test_cone_vfx_not_built_headless():
	# E05-S7: attach_cone_vfx must be a no-op without a live scene tree, so the
	# class never crashes in headless GUT (rendering-only work is gated).
	var mesh := _vc.attach_cone_vfx()
	assert_null(mesh, "cone VFX mesh must not be built headless (rendering gated)")
