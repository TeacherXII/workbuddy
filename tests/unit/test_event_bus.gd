# tests/unit/test_event_bus.gd
# GUT unit tests for E01-S9 event vocabulary reconciliation against
# design/gdd/system-breakdown.md §2 (13 signals + shared-type enums).
#
# Pure logic: EventBus.new() is a Node created WITHOUT a scene tree; signals work
# on any Object, so no add_child / main loop is required. Headless-safe.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const EventBus = preload("res://src/core/event_bus.gd")


var _bus: EventBus


func before_each() -> void:
	_bus = EventBus.new()
	watch_signals(_bus)


func after_each() -> void:
	_bus = null


func test_event_vocabulary_complete():
	# E01-S9: all 13 §2 signals are declared on the bus.
	var expected := [
		"time_scale_changed",
		"guard_transform_dirty",
		"light_state_changed",
		"cover_state_changed",
		"player_step_committed",
		"decoy_landed",
		"sound_emitted",
		"vision_stimulus",
		"vision_looming",
		"suspicion_changed",
		"guard_fsm_changed",
		"exposure_detected",
		"interactable_triggered",
	]
	var declared := 0
	for sig in expected:
		assert_true(_bus.has_signal(sig), "EventBus must declare signal '%s'" % sig)
		if _bus.has_signal(sig):
			declared += 1
	assert_eq(declared, 13, "all 13 §2 signals must be declared on the bus")


func test_all_signals_can_connect_and_emit():
	# E01-S9: every signal is connectable + emit-able with its §2 signature.
	# (watch_signals already spies on all signals; we emit each and assert.)
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	_bus.guard_transform_dirty.emit(1)
	_bus.light_state_changed.emit(7, EventBus.LightState.EXTINGUISHED)
	_bus.cover_state_changed.emit(Vector3i(1, 0, 2))
	_bus.player_step_committed.emit({"to": Vector3.ZERO})
	_bus.decoy_landed.emit(Vector3(0, 0, 1))
	_bus.sound_emitted.emit({"radius": 3.0})
	_bus.vision_stimulus.emit(1, null, 0.8)
	_bus.vision_looming.emit(1)
	_bus.suspicion_changed.emit(1, 42.0, EventBus.SusTier.SUSPICIOUS)
	# [D6, Batch C] guard_fsm_changed now carries EventBus.GuardState ints,
	# not key strings. [D8] interactable_triggered is now 3-arg with an
	# InteractableType + payload Dictionary.
	_bus.guard_fsm_changed.emit(1, EventBus.GuardState.CALM,
		EventBus.GuardState.SUSPICIOUS)
	_bus.exposure_detected.emit(1, null)
	_bus.interactable_triggered.emit(1, EventBus.InteractableType.TRAP,
		{"charges": 2})

	assert_signal_emitted(_bus, "time_scale_changed")
	assert_signal_emitted(_bus, "guard_transform_dirty")
	assert_signal_emitted(_bus, "light_state_changed")
	assert_signal_emitted(_bus, "cover_state_changed")
	assert_signal_emitted(_bus, "player_step_committed")
	assert_signal_emitted(_bus, "decoy_landed")
	assert_signal_emitted(_bus, "sound_emitted")
	assert_signal_emitted(_bus, "vision_stimulus")
	assert_signal_emitted(_bus, "vision_looming")
	assert_signal_emitted(_bus, "suspicion_changed")
	assert_signal_emitted(_bus, "guard_fsm_changed")
	assert_signal_emitted(_bus, "exposure_detected")
	assert_signal_emitted(_bus, "interactable_triggered")


func test_suspicion_changed_carries_tier_parameter():
	# E01-S9 drift ②: the 3rd arg (tier) must be present and emit-able.
	_bus.suspicion_changed.emit(3, 70.0, EventBus.SusTier.ALERT)
	assert_signal_emitted_with_parameters(_bus, "suspicion_changed",
		[3, 70.0, EventBus.SusTier.ALERT])


func test_light_state_changed_uses_lightstate_enum():
	# E01-S9 drift ①: signature is (light_id:int, state:LightState), not (point, level).
	_bus.light_state_changed.emit(5, EventBus.LightState.LIT)
	assert_signal_emitted_with_parameters(_bus, "light_state_changed",
		[5, EventBus.LightState.LIT])
