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
