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


func before_each() -> void:
	_vc = VisionCone.new()
	_lm = LightModel.new()
	_vc.set_light_model(_lm)        # inject the demo light model
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.FORWARD
	watch_signals(_vc)


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
