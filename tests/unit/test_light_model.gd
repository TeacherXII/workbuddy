# tests/unit/test_light_model.gd
# GUT unit tests for the real E04 LightModel (cover-shadow §2 threshold API).
# Covers: L_DARK/L_BRIGHT exposure, get_light_level (shadow box ~0.1 / light
# pool ~1.0), and light_sensitivity linear ramp between thresholds.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const LightModel = preload("res://src/game/light_model.gd")


var _lm: LightModel


func before_each() -> void:
	_lm = LightModel.new()
	watch_signals(_lm)


func after_each() -> void:
	_lm = null


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
