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
	# Test hygiene: EventBus is a Node created OUTSIDE the scene tree, so nothing
	# reaps it — `_bus = null` alone leaks one orphan PER TEST (orphan count grew
	# linearly with the test count in this file). autofree() hands it to GUT's
	# per-test reaper. add_child_autofree() is not used because these tests are
	# deliberately tree-free (see file header).
	_bus = autofree(EventBus.new())
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
	# [E06-S4, D11-A] decoy_landed is 3-arg (pos, surface, radius). A short
	# emit() here would raise "Error calling from signal" at runtime WITHOUT
	# failing any assert_signal_emitted — that is the N-8 false-green. The
	# full-parameter assertion below plus test_decoy_landed_signature_contract
	# are the two mechanisms that keep this honest.
	_bus.decoy_landed.emit(Vector3(0, 0, 1), "STONE", 8.0)
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
	# ★ N-8 mechanism ②: assert_signal_emitted only proves "it fired"; a 1-arg
	# emit against a 3-arg signal ALSO passes it (GUT's signal watcher is
	# variadic and does not check arity — addons/gut/signal_watcher.gd:77-97).
	# Assert the whole parameter tuple instead.
	assert_signal_emitted_with_parameters(
		_bus, "decoy_landed", [Vector3(0, 0, 1), "STONE", 8.0])
	var decoy_params: Array = get_signal_parameters(_bus, "decoy_landed")
	assert_eq(decoy_params.size(), 3,
		"emitted arg tuple must carry all 3 params (N-8 guard)")
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


func test_decoy_landed_signature_contract() -> void:
	# ★★ N-8 PRIMARY DEFENCE ★★  [E06-S4, D11-A / M-1]
	# Contract test: asserts the DECLARED shape of the signal (arity + order +
	# types) directly. It never emits, so it is immune to GUT's variadic
	# signal_watcher (addons/gut/signal_watcher.gd:122 connects every signal to
	# one variadic callback; :77-97 collects args WITHOUT checking arity — so a
	# 1-arg emit against a 3-arg signal still passes assert_signal_emitted while
	# the engine only push_error()s, which is not a test failure).
	# If anyone changes decoy_landed's signature without updating this test,
	# this test MUST go RED.
	var found: Dictionary = {}
	for sig in _bus.get_signal_list():
		if sig["name"] == "decoy_landed":
			found = sig
			break
	assert_false(found.is_empty(), "decoy_landed signal must exist on EventBus")
	if found.is_empty():
		return

	var args: Array = found["args"]
	# ① arity must be exactly 3 — this alone locks out the N-8 1-arg emit case.
	assert_eq(args.size(), 3,
		"decoy_landed arity must be 3 (pos, surface, radius); got %d" % args.size())
	if args.size() != 3:
		return
	# ② parameter names (guards against the order being swapped).
	assert_eq(args[0]["name"], "pos")
	assert_eq(args[1]["name"], "surface")
	assert_eq(args[2]["name"], "radius")
	# ③ parameter types (M-1: surface is String; the doc-level `Surface` type
	#    has no GDScript counterpart).
	assert_eq(args[0]["type"], TYPE_VECTOR3, "pos must be Vector3")
	assert_eq(args[1]["type"], TYPE_STRING,
		"surface must be String (doc-level `Surface` has no GDScript counterpart)")
	assert_eq(args[2]["type"], TYPE_FLOAT, "radius must be float (metres)")


func test_light_state_changed_uses_lightstate_enum():
	# E01-S9 drift ①: signature is (light_id:int, state:LightState), not (point, level).
	_bus.light_state_changed.emit(5, EventBus.LightState.LIT)
	assert_signal_emitted_with_parameters(_bus, "light_state_changed",
		[5, EventBus.LightState.LIT])
