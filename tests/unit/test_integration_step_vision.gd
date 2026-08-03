# tests/unit/test_integration_step_vision.gd
# GUT integration tests: StepCommit -> EventBus -> VisionCone vocabulary
# (ADR-002 event-driven recompute; system-breakdown §2 signal contract).
#
# Covers: commit emits player_step_committed -> SoundPropagator -> bus.sound_emitted
# (canonical E06 path; StepCommit no longer emits sound_emitted directly, G1);
# visibility reflects light level (light pool ~1.0, shadow ~0.0); ghost_trail
# capped at MAX_GHOST=6; EventBus wiring carries the commit.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const StepCommit = preload("res://src/game/step_commit.gd")
const VisionCone = preload("res://src/game/vision_cone.gd")
const LightModel = preload("res://src/game/light_model.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const SoundPropagator = preload("res://src/game/sound_propagation.gd")


var _step: StepCommit
var _vc: VisionCone
var _lm: LightModel
var _bus: EventBus
var _sp: SoundPropagator
var _captured_sound: Dictionary = {}
var _last_visibility: float = -1.0
var _commit_count := 0


func before_each() -> void:
	_step = StepCommit.new()
	_lm = LightModel.new()
	_vc = VisionCone.new()
	_vc.set_light_model(_lm)
	_vc.observer_pos = Vector3.ZERO
	# Vector3.FORWARD is (0,0,-1); all targets below sit at +Z, so the observer
	# must look at +Z (Vector3.BACK) to have them inside the 35deg cone.
	_vc.observer_forward = Vector3.BACK
	_bus = EventBus.new()
	# add_child_autofree (NOT plain add_child): GUT frees these right after each
	# test, which takes them out of the tree and de-registers EventBus from group
	# "event_bus". Plain add_child leaked every fixture, so group membership grew
	# per test and get_first_node_in_group returned the FIRST (stale) bus
	# (ADDCHILD-AUTOFREE-01).
	add_child_autofree(_bus)
	add_child_autofree(_step)
	add_child_autofree(_vc)
	watch_signals(_step)
	watch_signals(_vc)
	watch_signals(_bus)
	# Wire the event vocabulary: commit -> bus -> (E06 sound / vision recompute).
	_step.player_step_committed.connect(_bus.player_step_committed.emit)
	# G1 (S1C-FIX-01): sound_emitted is owned solely by SoundPropagator, driven by
	# player_step_committed through the bus (not StepCommit's removed direct emit).
	# Wire a SoundPropagator so this integration test exercises the canonical path.
	_sp = SoundPropagator.new()
	_sp.set_event_bus(_bus)
	add_child_autofree(_sp)
	_bus.sound_emitted.connect(_on_sound)
	_vc.vision_stimulus.connect(_on_vision)
	_captured_sound = {}
	_last_visibility = -1.0
	_commit_count = 0


func after_each() -> void:
	_bus = null
	_step = null
	_vc = null
	_lm = null
	_sp = null


func _on_sound(p: Dictionary) -> void:
	_captured_sound = p


func _on_vision(_gid: int, _t: Node, v: float) -> void:
	_last_visibility = v


func test_commit_emits_sound_with_landing_payload():
	# E03-S4 / E03-S6 / E06-S2: commit -> player_step_committed -> SoundPropagator
	# -> bus.sound_emitted carries the landing point (origin) + noise radius.
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2), "STONE")
	assert_signal_emitted(_bus, "sound_emitted",
		"commit must drive sound_emitted via SoundPropagator (E06 / vision recompute)")
	assert_eq(_captured_sound.get("origin", null), Vector3(0, 0, 2),
		"sound payload must carry the landing position (origin)")
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
	_vc.observer_forward = Vector3.BACK
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 1.0, "cone + LOS + light pool must yield full visibility")


func test_visibility_in_shadow_is_zero():
	# E04-S1 / E05-S2: shadow box -> L ~= 0.1 -> visibility ~= 0.0.
	_lm.add_shadow_box(Vector3(0, 0, 5), 2.0)
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.BACK
	var v := _vc.compute_visibility(Vector3(0, 0, 5))
	assert_eq(v, 0.0, "target inside a shadow box must be effectively invisible")


func test_commit_landing_in_shadow_yields_zero_visibility():
	# Integration of E03-S4 + E04-S1 + E05-S2: a step committed into shadow
	# must leave the guard detecting nothing at the landing point.
	_lm.add_shadow_box(Vector3(0, 0, 3), 2.0)
	_vc.observer_pos = Vector3.ZERO
	_vc.observer_forward = Vector3.BACK
	_step.commit(Vector3.ZERO, Vector3(0, 0, 3), "STONE")
	assert_signal_emitted(_bus, "sound_emitted",
		"commit must fire sound via SoundPropagator (drives dirty recompute)")
	var v := _vc.compute_visibility(Vector3(0, 0, 3))
	assert_eq(v, 0.0, "landing inside shadow -> guard detects nothing")


func test_ghost_trail_capped_at_six():
	# E03-S6: ghost_trail must never exceed MAX_GHOST=6 even after many commits.
	for i in range(12):
		_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0 + float(i)), "STONE")
		_step.tick_real(0.13)   # clear real-time cooldown + return to IDLE
	assert_true(_step._ghost_trail.size() <= 6,
		"ghost_trail must never exceed MAX_GHOST=6 (got %d)" % _step._ghost_trail.size())
