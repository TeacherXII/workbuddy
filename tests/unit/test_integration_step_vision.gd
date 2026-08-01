# tests/unit/test_integration_step_vision.gd
# GUT integration tests: StepCommit -> EventBus -> VisionCone vocabulary
# (ADR-002 event-driven recompute; system-breakdown §2 signal contract).
#
# Covers: commit emits player_step_committed + sound_emitted (driving E06 /
# vision recompute); visibility reflects light level (light pool ~1.0, shadow
# ~0.0); ghost_trail capped at MAX_GHOST=6; EventBus wiring carries the commit.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const StepCommit = preload("res://src/game/step_commit.gd")
const VisionCone = preload("res://src/game/vision_cone.gd")
const LightModel = preload("res://src/game/light_model.gd")
const EventBus = preload("res://src/core/event_bus.gd")


var _step: StepCommit
var _vc: VisionCone
var _lm: LightModel
var _bus: EventBus
var _captured_sound: Dictionary = {}
var _last_visibility: float = -1.0
var _commit_count := 0


func before_each() -> void:
	_step = StepCommit.new()
	_lm = LightModel.new()
	_vc = VisionCone.new()
	_vc.set_light_model(_lm)
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.FORWARD
	_bus = EventBus.new()
	add_child(_bus)
	add_child(_step)
	add_child(_vc)
	watch_signals(_step)
	watch_signals(_vc)
	watch_signals(_bus)
	# Wire the event vocabulary: commit -> bus -> (E06 sound / vision recompute).
	_step.player_step_committed.connect(_bus.player_step_committed.emit)
	_step.sound_emitted.connect(_on_sound)
	_vc.vision_stimulus.connect(_on_vision)
	_captured_sound = {}
	_last_visibility = -1.0
	_commit_count = 0


func after_each() -> void:
	_bus = null
	_step = null
	_vc = null
	_lm = null


func _on_sound(p: Dictionary) -> void:
	_captured_sound = p


func _on_vision(_gid: int, _t: Node, v: float) -> void:
	_last_visibility = v


func test_commit_emits_sound_with_landing_payload():
	# E03-S4 / E03-S6: commit drives footfall -> sound_emitted carries landing
	# point + noise radius (consumed by E06 + as dirty trigger for vision).
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2), "STONE")
	assert_signal_emitted(_step, "sound_emitted",
		"commit must emit sound_emitted (drives E06 / vision recompute)")
	assert_eq(_captured_sound.get("pos", null), Vector3(0, 0, 2),
		"sound payload must carry the landing position")
	assert_true(_captured_sound.has("radius"),
		"sound payload must carry the noise radius")


func test_event_bus_wiring_carries_step_commit():
	# ADR-002 / system-breakdown §2: StepCommit -> EventBus vocabulary contract.
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2), "STONE")
	assert_signal_emitted(_bus, "player_step_committed",
		"StepCommit must forward player_step_committed onto the EventBus")


func test_visibility_in_light_pool_is_full():
	# E04-S1 / E05-S2: in cone, LOS clear, light pool -> full visibility 1.0.
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.FORWARD
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 1.0, "cone + LOS + light pool must yield full visibility")


func test_visibility_in_shadow_is_zero():
	# E04-S1 / E05-S2: shadow box -> L ~= 0.1 -> visibility ~= 0.0.
	_lm.add_shadow_box(Vector3(0, 0, 5), 2.0)
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.FORWARD
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 0.0, "target inside a shadow box must be effectively invisible")


func test_commit_landing_in_shadow_yields_zero_visibility():
	# Integration of E03-S4 + E04-S1 + E05-S2: a step committed into shadow
	# must leave the guard detecting nothing at the landing point.
	_lm.add_shadow_box(Vector3(0, 0, 3), 2.0)
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.FORWARD
	_step.commit(Vector3.ZERO, Vector3(0, 0, 3), "STONE")
	assert_signal_emitted(_step, "sound_emitted",
		"commit must fire (drives dirty recompute)")
	var v := _vc.compute_visibility(Vector3(0, 0, 3))
	assert_eq(v, 0.0, "landing inside shadow -> guard detects nothing")


func test_ghost_trail_capped_at_six():
	# E03-S6: ghost_trail must never exceed MAX_GHOST=6 even after many commits.
	for i in range(12):
		_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0 + float(i)), "STONE")
		_step.tick_real(0.13)   # clear real-time cooldown + return to IDLE
	assert_true(_step.ghost_trail.size() <= 6,
		"ghost_trail must never exceed MAX_GHOST=6 (got %d)" % _step.ghost_trail.size())
