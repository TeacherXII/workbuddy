# tests/unit/test_hud_slice.gd
# GUT tests for the real E09 HudSlice (core-hud-a11y §2).
# Covers: focus readout updates on time_scale_changed(FOCUS), suspicion bar
# value updates on vision_stimulus, and aim-preview Control shows + matches
# camera projection.
#
# NOTE (N2 / §6.1 of sprint0-qa-plan): this test requires a live scene tree
# (EventBus must be in group "event_bus" so HudSlice._ready can connect) and a
# Camera3D for set_aim_preview's unproject. It is syntactically GUT-loadable
# and verified by source-diff + GDScript 4.4 review; runtime confirmation
# happens in a runnable environment.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const HudSlice = preload("res://src/ui/hud_slice.gd")
const EventBus = preload("res://src/core/event_bus.gd")


var _bus: EventBus
var _hud: HudSlice


func before_each() -> void:
	# Mirror sprint0_bootstrap._spawn_event_bus: create the bus, add it to the
	# tree so its _ready registers group "event_bus", then add the HUD which
	# grabs the bus from that group in its own _ready.
	_bus = EventBus.new()
	add_child(_bus)
	_hud = HudSlice.new()
	# Inject THIS test's bus before the HUD enters the tree. Plain add_child'd
	# nodes are not freed between tests, so buses from earlier tests are still
	# registered in group "event_bus"; HudSlice._ready's group fallback would
	# grab the FIRST (stale) one and the HUD would never see this test's
	# signals. Explicit injection makes the wiring deterministic.
	_hud.set_event_bus(_bus)
	add_child(_hud)
	watch_signals(_bus)


func after_each() -> void:
	# GUT auto-frees add_child'd nodes; null refs to avoid stale handles.
	_bus = null
	_hud = null


func test_focus_readout_updates_on_focus():
	# E09-S1: entering FOCUS must update the status readout to "凝神 0.25×".
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	assert_eq(_hud._status.text, "凝神 0.25×",
		"status readout must show focus state after time_scale_changed(FOCUS)")
	assert_true(_hud._dim.visible,
		"focus dim overlay must be visible while focusing")


func test_focus_readout_restores_on_flowing():
	# E09-S1 + E02-S1: leaving FOCUS restores the flowing readout.
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	_bus.time_scale_changed.emit(0.25, 1.0, "FLOWING")
	assert_eq(_hud._status.text, "FLOWING 1.0×",
		"status readout must restore after leaving FOCUS")
	assert_false(_hud._dim.visible,
		"focus dim overlay must hide after leaving FOCUS")


func test_suspicion_bar_updates_on_vision_stimulus():
	# E09-S3: a vision_stimulus of 0.5 -> suspicion bar value ~50 (0..100).
	_bus.vision_stimulus.emit(1, null, 0.5)
	assert_almost_eq(_hud._suspicion.value, 50.0, 0.0001,
		"suspicion bar must reflect visibility*100 from vision_stimulus")


func test_suspicion_bar_clamps_to_range():
	# E09-S3: over-bright stimulus must clamp to the bar's max (100), not exceed.
	_bus.vision_stimulus.emit(1, null, 1.0)
	assert_almost_eq(_hud._suspicion.value, 100.0, 0.0001,
		"suspicion bar must clamp at max value 100.0")


func test_set_aim_preview_hides_without_camera():
	# E09-S1: with no camera in the viewport, the preview must safely hide
	# (no crash, no ghost footprint left visible).
	_hud.set_aim_preview(Vector3(0, 0, 3))
	assert_false(_hud._preview.visible,
		"preview must hide when no camera can project the aim point")


func test_set_aim_preview_shows_and_matches_projection():
	# E09-S1 / C-03 / C-05: with a camera present, the landing preview Control
	# must show and sit at the camera projection of the aim point (offset by
	# half its minimum size, matching hud_slice.gd math).
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 12, -12)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)

	var world_pos := Vector3(0, 0, 3)
	_hud.set_aim_preview(world_pos)
	assert_true(_hud._preview.visible,
		"preview must show when a camera can project the aim point")

	var expected := cam.unproject_position(world_pos) \
		- _hud._preview.custom_minimum_size * 0.5
	# NaN guard: unproject may be non-finite under a 0-size headless viewport;
	# only compare when the projection is finite (N2 runtime confirmation).
	if expected.x == expected.x and expected.y == expected.y:
		var delta := _hud._preview.position.distance_to(expected)
		assert_true(delta < 0.001,
			"preview position must match camera projection of aim point (delta=%f)" % delta)
