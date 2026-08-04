# tests/unit/test_patrol_ai.gd
# GUT tests for E08 GuardBrain (src/game/patrol_ai.gd) — Sprint 1, Batch C.
#
# Hook coverage (batchc-impl-spec §8): H1 H2 H3 H4 H6 H7 H8 H9 H10 H11 H18.
#   H5 (test_exposure_grace_1_2s) lives in tests/unit/test_step_commit.gd because
#   that file owned the ExposureGuardStub it replaces — see the N-3-style rewrite
#   note there. Do NOT create a second H5 here.
#
# Naming warning N-1 (spec §8.1): `test_suspicion_changed_carries_tier` below is
#   NOT a duplicate of `test_suspicion_changed_carries_tier_parameter` in
#   tests/unit/test_event_bus.gd:84. That one is a VOCABULARY test (E01-S9: the
#   signal can carry 3 args). This one is a SEMANTIC test (E08-S6: the emitter
#   computes the correct tier value).
# Naming warning N-2 (spec §8.1): `test_suspicion_accumulates_from_sound_event`
#   is the E08 CONSUMER-side test. The E06 producer-side formula is already
#   covered by test_sound_propagation.gd:139 `test_suspicion_from_sound_distance`
#   (Batch B). Do not rebuild that name here.
#
# Node discipline: GuardBrain / EventBus / SoundPropagator are Nodes but are
#   deliberately NOT added to the scene tree — every tick in these tests is
#   driven manually through tick_real()/_decide() so the timing is deterministic.
#   GuardBrain._process() would otherwise inject wall-clock ticks and make the
#   assertions flaky. They are released with autofree() so the orphan count does
#   not regress (ADDCHILD-AUTOFREE-01 discipline, applied to non-tree nodes).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const GuardBrain = preload("res://src/game/patrol_ai.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const SoundPropagator = preload("res://src/game/sound_propagation.gd")
const SpatialHashGrid3D = preload("res://src/core/spatial_hash_grid.gd")


var _bus: EventBus
var _brain: GuardBrain

# Manual signal ledgers. Preferred over watch_signals here because several hooks
# assert EXACT emission counts (throttling / "exactly once" / "<=2 times"), and
# a ledger also lets us assert the D6 int-enum payload shape directly.
var _fsm_events: Array = []
var _sus_events: Array = []
var _exposure_events: Array = []
var _dirty_events: Array = []
var _sink_calls: int = 0
var _astar_calls: int = 0
var _astar_args: Array = []


func before_each() -> void:
	_bus = EventBus.new()
	autofree(_bus)
	_brain = GuardBrain.new()
	autofree(_brain)
	_brain.guard_id = 1
	_brain.set_event_bus(_bus)

	_fsm_events = []
	_sus_events = []
	_exposure_events = []
	_dirty_events = []
	_sink_calls = 0
	_astar_calls = 0
	_astar_args = []

	_bus.guard_fsm_changed.connect(_on_fsm)
	_bus.suspicion_changed.connect(_on_sus)
	_bus.exposure_detected.connect(_on_exposure)
	_bus.guard_transform_dirty.connect(_on_dirty)


func after_each() -> void:
	# autofree releases _bus / _brain AFTER this returns; drop handles only.
	Engine.time_scale = 1.0
	_bus = null
	_brain = null


# ---- ledger sinks -----------------------------------------------------------
func _on_fsm(guard_id: int, old: int, new: int) -> void:
	_fsm_events.append({"id": guard_id, "old": old, "new": new})


func _on_sus(guard_id: int, value: float, tier: int) -> void:
	_sus_events.append({"id": guard_id, "value": value, "tier": tier})


func _on_exposure(guard_id: int, target: Node) -> void:
	_exposure_events.append({"id": guard_id, "target": target})


func _on_dirty(guard_id: int) -> void:
	_dirty_events.append(guard_id)


func _count_sink() -> void:
	_sink_calls += 1


func _fake_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	_astar_calls += 1
	_astar_args.append({"from": from, "to": to})
	return PackedVector3Array([from, to])


# ---- helpers ----------------------------------------------------------------
func _tick(n: int, vis: float) -> void:
	# Drive n fixed decision steps at exactly TICK_DT, bypassing the real-time
	# accumulator so the arithmetic under test is exact.
	for i in range(n):
		_brain._pending_vision = vis
		_brain._decide(GuardBrain.TICK_DT)


func _force_state(state: int) -> void:
	# Jump straight to a state for table-driven assertions. Clears the ledger so
	# the following assertions only see the transition under test.
	_brain._set_fsm(state)
	_fsm_events = []


# =============================================================================
# H1 · E08-S1 — five-state FSM transition table (§3.1)
# =============================================================================
func test_fsm_transitions() -> void:
	# Baseline: a fresh brain patrols.
	assert_eq(_brain.get_state(), EventBus.GuardState.CALM,
		"a fresh GuardBrain must start in CALM (PATROL)")

	# CALM -> SUSPICIOUS at THR_SUSP (upward threshold).
	_brain.suspicion = GuardBrain.THR_SUSP
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.SUSPICIOUS,
		"S >= THR_SUSP(25) must move CALM -> SUSPICIOUS")

	# D6: the signal payload must be GuardState INTs, never strings.
	assert_eq(_fsm_events.size(), 1, "exactly one guard_fsm_changed for one transition")
	assert_eq(_fsm_events[0]["old"], EventBus.GuardState.CALM,
		"[D6] guard_fsm_changed.old must be an EventBus.GuardState int")
	assert_eq(_fsm_events[0]["new"], EventBus.GuardState.SUSPICIOUS,
		"[D6] guard_fsm_changed.new must be an EventBus.GuardState int")
	assert_eq(typeof(_fsm_events[0]["old"]), TYPE_INT,
		"[D6] guard_fsm_changed must carry ints (the old String domain is dead)")

	# SUSPICIOUS -> ALERT at THR_ALERT.
	_brain.suspicion = GuardBrain.THR_ALERT
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT,
		"S >= THR_ALERT(60) must move SUSPICIOUS -> ALERT")

	# ALERT -> SEARCH after LOST_TARGET_RT of vis <= STIM_EPS.
	var lost_ticks := int(round(GuardBrain.LOST_TARGET_RT / GuardBrain.TICK_DT))
	for i in range(lost_ticks - 1):
		_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT,
		"ALERT must hold until LOST_TARGET_RT(0.5s) of lost vision has elapsed")
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.SEARCH,
		"ALERT -> SEARCH after 0.5s with vis <= STIM_EPS")

	# SEARCH -> ALERT on re-acquire.
	_brain._step_fsm(1.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT,
		"SEARCH -> ALERT when vis > STIM_EPS (re-acquired)")

	# SEARCH -> RETURN when suspicion decays below THR_RETURN.
	for i in range(lost_ticks):
		_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.SEARCH, "back to SEARCH")
	_brain.suspicion = GuardBrain.THR_RETURN - 1.0
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN,
		"SEARCH -> RETURN when S < THR_RETURN(10)")

	# RETURN -> CALM after RETURN_SETTLE_RT.
	var settle_ticks := int(round(GuardBrain.RETURN_SETTLE_RT / GuardBrain.TICK_DT))
	for i in range(settle_ticks - 1):
		_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN,
		"RETURN must hold until RETURN_SETTLE_RT(1.0s)")
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.CALM,
		"RETURN -> CALM after 1.0s settle")

	# RETURN -> SUSPICIOUS (re-alarmed on the way home; interruption allowed).
	_force_state(EventBus.GuardState.RETURN)
	_brain.suspicion = GuardBrain.THR_SUSP + 5.0
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.SUSPICIOUS,
		"RETURN -> SUSPICIOUS when re-alarmed above THR_SUSP")

	# SUSPICIOUS -> RETURN (the ONLY downward path; no ALERT->SUSPICIOUS->CALM).
	_brain.suspicion = GuardBrain.THR_RETURN - 0.1
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN,
		"SUSPICIOUS -> RETURN when S < THR_RETURN (unified downward path)")


func test_fsm_cross_level_jump_emits_once() -> void:
	# H1 / discipline 3 (edge E9): 5 -> 65 in one tick must land on ALERT in ONE
	# hop and emit exactly ONE guard_fsm_changed (no synthetic intermediate).
	_brain.suspicion = 5.0
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.CALM, "still CALM at S=5")
	_fsm_events = []

	_brain.suspicion = 65.0
	_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT,
		"CALM -> ALERT must be a single hop when S crosses both thresholds")
	assert_eq(_fsm_events.size(), 1,
		"a cross-level jump must emit guard_fsm_changed exactly once (no intermediate state)")
	assert_eq(_fsm_events[0]["old"], EventBus.GuardState.CALM, "old must be CALM")
	assert_eq(_fsm_events[0]["new"], EventBus.GuardState.ALERT, "new must be ALERT")


func test_fsm_threshold_jitter_does_not_thrash() -> void:
	# H1 / discipline 1+2: oscillating S across 25 twenty times must NOT produce
	# a burst of signals — 25/60 are UPWARD-only thresholds, so once SUSPICIOUS
	# is entered nothing walks back down until S < 10.
	for i in range(20):
		_brain.suspicion = 25.1 if i % 2 == 0 else 24.9
		_brain._step_fsm(0.0, GuardBrain.TICK_DT)
	assert_lte(_fsm_events.size(), 2,
		"24.9<->25.1 jitter x20 must emit guard_fsm_changed at most twice (got %d)"
			% _fsm_events.size())
	assert_eq(_brain.get_state(), EventBus.GuardState.SUSPICIOUS,
		"the guard must settle in SUSPICIOUS, not oscillate back to CALM")


# =============================================================================
# H2 · E08-S2 — continuous suspicion, thresholds 25/60/10 (§3.2)
# =============================================================================
func test_suspicion_thresholds() -> void:
	# vis=1.0 -> +KV*dt = +3.5 per tick. Budget table: 25 @ ~0.71s, 60 @ ~1.71s
	# (spec allows +/-1 tick, i.e. the first tick at or past the threshold).
	var ticks := 0
	while _brain.suspicion < GuardBrain.THR_SUSP and ticks < 100:
		_tick(1, 1.0)
		ticks += 1
	var t_susp := float(ticks) * GuardBrain.TICK_DT
	assert_between(t_susp, 0.61, 0.81,
		"vis=1.0 must reach THR_SUSP(25) at ~0.71s +/-1 tick (got %.2fs)" % t_susp)

	while _brain.suspicion < GuardBrain.THR_ALERT and ticks < 200:
		_tick(1, 1.0)
		ticks += 1
	var t_alert := float(ticks) * GuardBrain.TICK_DT
	assert_between(t_alert, 1.61, 1.81,
		"vis=1.0 must reach THR_ALERT(60) at ~1.71s +/-1 tick (got %.2fs)" % t_alert)

	# The [0,100] clamp is covered by test_suspicion_clamps_without_banking_overflow
	# below, which needs a shorter saturation window than this test can offer.


func test_suspicion_clamps_without_banking_overflow() -> void:
	# H2 / E1. Deliberately a separate test: a guard cannot sit saturated inside
	# ALERT for long, because E08-S4's 1.2s grace soft-fails and zeroes suspicion.
	# The saturation window below is therefore kept under GRACE_RT on purpose.
	_brain.suspicion = 99.0
	_tick(1, 1.0)                          # 99 + 3.5 = 102.5 -> must clamp
	assert_almost_eq(_brain.suspicion, 100.0, 0.0001,
		"suspicion must clamp at the 100 ceiling")
	_tick(5, 1.0)                          # 6 ticks = 0.6s, still < GRACE_RT(1.2)
	assert_almost_eq(_brain.suspicion, 100.0, 0.0001,
		"E1: further saturated ticks must be TRUNCATED, never banked")
	assert_lt(_brain.exposure_timer, GuardBrain.GRACE_RT,
		"guard rail: this test must stay inside the exposure grace window")

	# The real proof nothing was banked: decay 8/s from 100 reaches <=10 in
	# 90/8 = 11.25s. Had the six saturated ticks been stored (121 pts), the value
	# here would still read about 20.
	_tick(113, 0.0)
	assert_lte(_brain.suspicion, 10.0,
		"decay from a CLAMPED 100 must reach <=10 within 11.3s (got %.2f)"
			% _brain.suspicion)

	# Lower clamp: never negative.
	_tick(60, 0.0)
	assert_almost_eq(_brain.suspicion, 0.0, 0.0001,
		"suspicion must clamp at 0 and never go negative")


func test_suspicion_stimulus_suppresses_decay() -> void:
	# H3 / E4: accumulation and decay are MUTUALLY EXCLUSIVE within a tick.
	_brain.suspicion = 50.0
	_tick(1, 0.01)          # 0.01 > STIM_EPS -> stimulus, no decay
	var expected := 50.0 + GuardBrain.KV * 0.01 * GuardBrain.TICK_DT
	assert_almost_eq(_brain.suspicion, expected, 0.0001,
		"a tick with vis > STIM_EPS must NOT subtract decay")
	assert_gt(_brain.suspicion, 50.0,
		"a stimulated tick must be net-positive, not net-negative")

	# E3: 1e-7 is float noise, NOT a stimulus — decay must still apply, otherwise
	# the guard "holds a grudge" forever.
	_brain.suspicion = 50.0
	_tick(1, 1e-7)
	assert_lt(_brain.suspicion, 50.0,
		"vis=1e-7 is below STIM_EPS(0.001) and must still decay (E3: no eternal grudge)")
	var expected_noise := 50.0 + GuardBrain.KV * 1e-7 * GuardBrain.TICK_DT \
		- GuardBrain.DECAY * GuardBrain.TICK_DT
	assert_almost_eq(_brain.suspicion, expected_noise, 0.0001,
		"decay must be exactly DECAY*dt when the stimulus is sub-epsilon")


# =============================================================================
# H4 · E08-S3 — 10Hz throttled decisions (@ci:G-04)
# =============================================================================
func test_fsm_tick_le_10hz() -> void:
	# 2.0s of real time fed one 60fps frame at a time -> exactly 20 decisions.
	for i in range(120):
		_brain.tick_real(1.0 / 60.0)
	assert_between(_brain.decision_count, 10, 20,
		"2.0s of real time must yield 10..20 decisions at DECISION_HZ=10 (got %d)"
			% _brain.decision_count)

	# T-02 / ADR-003: the decision clock is REAL time. Slowing the engine must
	# not change the count for the same amount of real time. (+/-1 tick of slack
	# for float accumulation of 1/60 steps, not for any time_scale coupling.)
	var baseline := _brain.decision_count
	Engine.time_scale = 0.25
	for i in range(120):
		_brain.tick_real(1.0 / 60.0)
	Engine.time_scale = 1.0
	var scaled_delta := _brain.decision_count - baseline
	assert_between(scaled_delta, baseline - 1, baseline + 1,
		"Engine.time_scale must NOT scale the decision clock (T-02/ADR-003): "
			+ "got %d decisions at 0.25x vs %d at 1.0x" % [scaled_delta, baseline])

	# E5: one enormous frame must catch up at most MAX_CATCHUP_TICKS and then
	# DROP the backlog (no compensation spiral).
	var before := _brain.decision_count
	_brain.tick_real(0.5)
	assert_eq(_brain.decision_count - before, GuardBrain.MAX_CATCHUP_TICKS,
		"a 0.5s frame must run exactly MAX_CATCHUP_TICKS(3) catch-up decisions")
	var after_catchup := _brain.decision_count
	_brain.tick_real(0.0)
	assert_eq(_brain.decision_count, after_catchup,
		"the dropped backlog must not leak into the next frame (accumulator reset)")


# =============================================================================
# H6 · E08-S4 — soft fail invokes the D9 checkpoint seam exactly once
# =============================================================================
func test_soft_fail_invokes_checkpoint_sink_once() -> void:
	_brain.set_checkpoint_sink(_count_sink)
	_brain._set_fsm(EventBus.GuardState.ALERT)
	_brain.suspicion = 80.0
	_brain.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT

	_brain._pending_target = null
	_tick(1, 1.0)                        # crosses GRACE_RT -> soft fail
	assert_eq(_sink_calls, 1, "soft fail must call the checkpoint sink exactly once")
	assert_eq(_exposure_events.size(), 1, "soft fail must emit exposure_detected exactly once")
	assert_almost_eq(_brain.suspicion, 0.0, 0.0001, "soft fail must reset suspicion to 0")
	assert_almost_eq(_brain.exposure_timer, 0.0, 0.0001, "soft fail must reset the exposure timer")
	assert_eq(_brain.last_known, Vector3.ZERO, "soft fail must clear last_known")
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN,
		"soft fail must force the FSM to RETURN")


func test_soft_fail_without_sink_does_not_crash() -> void:
	# D9 seam (1): an un-injected Callable must be a safe no-op, not a crash.
	_brain._set_fsm(EventBus.GuardState.ALERT)
	_brain.suspicion = 80.0
	_brain.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT
	_tick(1, 1.0)
	assert_eq(_exposure_events.size(), 1,
		"soft fail must still fire exposure_detected when no checkpoint sink is injected")
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN, "and still force RETURN")


# =============================================================================
# H7 · E08-S5 — A* requested on state transitions only (@ci:G-05)
# =============================================================================
func test_astar_only_on_transition() -> void:
	_brain.set_path_provider(_fake_path)

	# Step 1: entering ALERT triggers exactly one path request.
	_brain.suspicion = 65.0
	_tick(1, 1.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT, "S=65 -> ALERT on the first tick")
	assert_eq(_astar_calls, 1, "entering ALERT must request the path exactly once")

	# Step 2: 20 more ticks inside ALERT must NOT re-request the path (G-05: the
	# cache holds; A* is never a per-frame cost).
	# NOTE the interaction with E08-S4: the guard CANNOT stay ALERT + continuously
	# visible for 20 ticks — the 1.2s grace would soft-fail at tick 12 and knock
	# it into RETURN. So the player "peeks": 4 visible ticks then 1 occluded tick,
	# which resets exposure_timer while keeping _lost_timer under
	# LOST_TARGET_RT(0.5s). That holds ALERT indefinitely and is exactly the
	# realistic sustained-pursuit case G-05 is about.
	for cycle in range(4):
		_tick(4, 1.0)
		_tick(1, 0.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT, "must still be ALERT")
	assert_eq(_astar_calls, 1, "20 ticks inside ALERT must not re-request the path (G-05)")

	# Step 3: ALERT -> SEARCH re-dirties the cache.
	var lost_ticks := int(round(GuardBrain.LOST_TARGET_RT / GuardBrain.TICK_DT))
	_tick(lost_ticks, 0.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.SEARCH, "lost target -> SEARCH")
	assert_eq(_astar_calls, 2, "entering SEARCH must request the path a second time")

	# Step 4: fall all the way back to CALM, then re-alert -> third request.
	_brain.suspicion = 0.0
	_tick(1, 0.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.RETURN, "S<10 -> RETURN")
	var settle_ticks := int(round(GuardBrain.RETURN_SETTLE_RT / GuardBrain.TICK_DT))
	_tick(settle_ticks, 0.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.CALM, "RETURN settles to CALM")
	assert_eq(_astar_calls, 2, "RETURN/CALM must not request a path")

	_brain.suspicion = 65.0
	_tick(1, 1.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT, "re-alerted")
	assert_eq(_astar_calls, 3, "re-entering ALERT must request the path a third time")
	assert_eq(_brain.get_cached_path().size(), 2, "the cached path must be readable")


func test_astar_without_provider_does_not_crash() -> void:
	# D9 seam (2): no NavServer in Sprint 1 -> the seam must degrade to a no-op.
	_brain.suspicion = 65.0
	_tick(1, 1.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT, "FSM still advances")
	assert_eq(_brain.get_cached_path().size(), 0, "no provider -> empty cached path, no crash")


# =============================================================================
# H8 · E08-S6 — suspicion_changed carries the correct tier
#   ⚠ N-1: NOT the same as test_event_bus.gd:84
#          `test_suspicion_changed_carries_tier_parameter` (vocabulary-level).
#          This one is semantic: does the EMITTER compute the right tier?
# =============================================================================
func test_suspicion_changed_carries_tier() -> void:
	assert_eq(_brain.compute_tier(24.9, EventBus.GuardState.CALM), EventBus.SusTier.CALM,
		"24.9 must map to CALM")
	assert_eq(_brain.compute_tier(25.0, EventBus.GuardState.SUSPICIOUS), EventBus.SusTier.SUSPICIOUS,
		"25.0 must map to SUSPICIOUS (inclusive threshold)")
	assert_eq(_brain.compute_tier(59.9, EventBus.GuardState.SUSPICIOUS), EventBus.SusTier.SUSPICIOUS,
		"59.9 must still be SUSPICIOUS")
	assert_eq(_brain.compute_tier(60.0, EventBus.GuardState.ALERT), EventBus.SusTier.ALERT,
		"60.0 must map to ALERT (inclusive threshold)")

	# FSM override: SEARCH wins over the value band (system-breakdown §2.3).
	assert_eq(_brain.compute_tier(95.0, EventBus.GuardState.SEARCH), EventBus.SusTier.SEARCH,
		"fsm==SEARCH must override the value band with SusTier.SEARCH")

	# E10: RETURN has no tier of its own; S<10 lands it in CALM by value.
	assert_eq(_brain.compute_tier(5.0, EventBus.GuardState.RETURN), EventBus.SusTier.CALM,
		"RETURN with S<10 must report CALM (no special case needed)")

	# End-to-end: the emitted signal must carry that same tier.
	_brain.suspicion = 0.0
	_tick(1, 1.0)
	assert_gt(_sus_events.size(), 0, "suspicion_changed must be emitted")
	var last: Dictionary = _sus_events[-1]
	assert_eq(last["tier"], _brain.compute_tier(_brain.suspicion, _brain.get_state()),
		"the emitted tier must equal compute_tier(value, fsm)")
	assert_eq(last["id"], _brain.guard_id, "the emitted guard_id must be this guard")


# =============================================================================
# H9 · E08-S6 — all four signals, with their throttles
# =============================================================================
func test_guard_signals_emitted() -> void:
	# (a) suspicion_changed is throttled by SUS_EMIT_EPS(0.5) unless tier changes.
	# vis=0.1 -> +0.35/tick, so consecutive ticks stay under the epsilon.
	_tick(1, 0.1)
	assert_eq(_sus_events.size(), 1, "the first tick always emits (no previous value)")
	_tick(1, 0.1)
	assert_eq(_sus_events.size(), 1,
		"a +0.35 delta is below SUS_EMIT_EPS(0.5) and must be throttled")
	_tick(1, 0.1)
	assert_eq(_sus_events.size(), 2,
		"the accumulated +0.70 delta crosses SUS_EMIT_EPS and must emit")

	# (b) guard_fsm_changed fires only on a real change.
	_fsm_events = []
	_brain._set_fsm(_brain.get_state())
	assert_eq(_fsm_events.size(), 0, "setting the SAME state must not emit guard_fsm_changed")
	_brain._set_fsm(EventBus.GuardState.ALERT)
	assert_eq(_fsm_events.size(), 1, "a real state change must emit exactly once")

	# (c) guard_transform_dirty respects XFORM_POS_EPS / XFORM_YAW_EPS_DEG.
	_dirty_events = []
	_brain.set_transform_state(Vector3(GuardBrain.XFORM_POS_EPS - 0.1, 0, 0), 0.0)
	_tick(1, 1.0)
	assert_eq(_dirty_events.size(), 0,
		"a sub-threshold move (<0.5m) must not mark the transform dirty")
	_brain.set_transform_state(Vector3(GuardBrain.XFORM_POS_EPS + 0.1, 0, 0), 0.0)
	_tick(1, 1.0)
	assert_eq(_dirty_events.size(), 1, "a >0.5m move must mark the transform dirty once")

	_dirty_events = []
	var pos: Vector3 = Vector3(GuardBrain.XFORM_POS_EPS + 0.1, 0, 0)
	_brain.set_transform_state(pos, deg_to_rad(GuardBrain.XFORM_YAW_EPS_DEG - 1.0))
	_tick(1, 1.0)
	assert_eq(_dirty_events.size(), 0, "a <5deg turn must not mark the transform dirty")
	_brain.set_transform_state(pos, deg_to_rad(GuardBrain.XFORM_YAW_EPS_DEG + 1.0))
	_tick(1, 1.0)
	assert_eq(_dirty_events.size(), 1, "a >5deg turn must mark the transform dirty once")

	# (d) exposure_detected fires exactly once per soft fail.
	_exposure_events = []
	_brain._set_fsm(EventBus.GuardState.ALERT)
	_brain.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT
	_tick(1, 1.0)
	assert_eq(_exposure_events.size(), 1, "exactly one exposure_detected per soft fail")
	_tick(20, 1.0)
	assert_eq(_exposure_events.size(), 1,
		"the reset must prevent a second exposure_detected from the same event")


# =============================================================================
# H10 · E08-S6 — ★ LANDMINE 2: guard position must reach SoundPropagator (W1)
# =============================================================================
func test_guard_position_synced_to_sound_system() -> void:
	var sound := SoundPropagator.new()
	autofree(sound)
	sound.set_event_bus(_bus)
	var grid := SpatialHashGrid3D.new()
	sound.set_grid(grid)

	_brain.set_transform_state(Vector3.ZERO, 0.0)
	_brain.set_sound_system(sound)

	# (1) First-frame registration: the guard must be known BEFORE it ever moves.
	# Without this, _guard_positions stays empty, emit() can never distance-filter,
	# and E06-S5 dies silently while the unit tests stay green.
	assert_true(sound._guard_positions.has(_brain.guard_id),
		"★W1: set_sound_system must register_guard immediately (not on first move)")
	assert_eq(sound._guard_positions[_brain.guard_id], Vector3.ZERO,
		"the registered position must be the guard's current position")

	# The grid membership is the level/spawner's job (SoundPropagator.set_grid is
	# the seam); Sprint 1 has no spawner, so the test plays that role.
	grid.insert(_brain.guard_id, Vector3(10, 0, 0))

	# Before the move the guard is 10m from the sound, outside a 5m radius.
	var far_payload := sound.emit({
		"origin": Vector3(10, 0, 0), "radius": 5.0,
		"intensity": 1.0, "source": SoundPropagator.SOURCE_FOOTFALL,
	})
	assert_false(far_payload["target_guard_ids"].has(_brain.guard_id),
		"a guard 10m away must NOT be inside a 5m sound radius")

	# (2) Move past XFORM_POS_EPS and tick -> update_guard must back-fill.
	_brain.set_transform_state(Vector3(10, 0, 0), 0.0)
	_tick(1, 0.0)
	assert_eq(sound._guard_positions[_brain.guard_id], Vector3(10, 0, 0),
		"★W1: a >0.5m move must push the new position into SoundPropagator")

	# (3) The end-to-end proof: emit() can now distance-filter this guard in.
	var near_payload := sound.emit({
		"origin": Vector3(10, 0, 0), "radius": 5.0,
		"intensity": 1.0, "source": SoundPropagator.SOURCE_FOOTFALL,
	})
	assert_true(near_payload["target_guard_ids"].has(_brain.guard_id),
		"★W1: emit() must now collect this guard into target_guard_ids")


# =============================================================================
# H11 · E08-S8 — posture readability is shape/word coded, never color (C-05)
# =============================================================================
func test_guard_posture_non_color() -> void:
	var states := [
		EventBus.GuardState.CALM, EventBus.GuardState.SUSPICIOUS,
		EventBus.GuardState.ALERT, EventBus.GuardState.SEARCH,
		EventBus.GuardState.RETURN,
	]
	var seen := {}
	for s in states:
		_brain._set_fsm(s)
		var p: String = _brain.get_posture()
		assert_ne(p, "", "state %d must map to a non-empty posture" % s)
		assert_false(p.contains("#"),
			"posture '%s' must not encode a color value (C-05 non-color readability)" % p)
		assert_false(seen.has(p), "posture '%s' must be unique per state" % p)
		seen[p] = true
	assert_eq(seen.size(), 5, "all five GuardState members must map 1:1 to a posture")
	assert_eq(GuardBrain.POSTURE.size(), 5,
		"the POSTURE table must cover exactly the five GuardState members")


# =============================================================================
# H18 · E06-S5 — sound raises suspicion by distance, as an IMPULSE (D5)
#   ⚠ N-2: the producer-side formula is covered by test_sound_propagation.gd.
# =============================================================================
func test_suspicion_accumulates_from_sound_event() -> void:
	var sound := SoundPropagator.new()
	autofree(sound)
	_brain.set_transform_state(Vector3.ZERO, 0.0)
	_brain.set_sound_system(sound)

	# (a) One full-strength event at distance 0 -> falloff 1.0 -> S += KS(15).
	# ★ D5: an IMPULSE. It must NOT be multiplied by dt (that would give 1.5).
	_brain._on_sound_emitted({
		"origin": Vector3.ZERO, "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [_brain.guard_id],
	})
	_tick(1, 0.0)
	assert_almost_eq(_brain.suspicion, GuardBrain.KS, 0.0001,
		"[D5] a full-strength sound must add exactly KS(15) points, NOT KS*dt(1.5)")

	# (b) E2: three events in the SAME tick take the MAX falloff and count once.
	_brain.suspicion = 0.0
	for f in [0.25, 1.0, 0.5]:
		_brain._on_sound_emitted({
			"origin": Vector3(0, 0, 10.0 * (1.0 - f)), "radius": 10.0, "intensity": 1.0,
			"target_guard_ids": [_brain.guard_id],
		})
	_tick(1, 0.0)
	assert_almost_eq(_brain.suspicion, GuardBrain.KS, 0.0001,
		"E2: 3 sounds in one tick must contribute max(falloff) ONCE, not the sum")

	# (c) dist >= radius contributes nothing, and the tick decays as if silent.
	_brain.suspicion = 50.0
	_brain._on_sound_emitted({
		"origin": Vector3(0, 0, 20.0), "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [_brain.guard_id],
	})
	_tick(1, 0.0)
	assert_almost_eq(_brain.suspicion, 50.0 - GuardBrain.DECAY * GuardBrain.TICK_DT, 0.0001,
		"a sound at dist >= radius must contribute 0 and must not suppress decay")

	# (d) Events that do not name this guard are ignored entirely.
	_brain.suspicion = 0.0
	_brain._on_sound_emitted({
		"origin": Vector3.ZERO, "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [_brain.guard_id + 99],
	})
	_tick(1, 0.0)
	assert_almost_eq(_brain.suspicion, 0.0, 0.0001,
		"a sound addressed to other guards must not raise this guard's suspicion")


func test_last_known_priority_sound_then_vision() -> void:
	# §3.12 write priority: vision (real target position) > sound origin > keep.
	var sound := SoundPropagator.new()
	autofree(sound)
	_brain.set_transform_state(Vector3.ZERO, 0.0)
	_brain.set_sound_system(sound)

	# (2) no vision + a sound event -> last_known = payload.origin
	_brain._on_sound_emitted({
		"origin": Vector3(3, 0, 4), "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [_brain.guard_id],
	})
	_tick(1, 0.0)
	assert_eq(_brain.last_known, Vector3(3, 0, 4),
		"with no vision, last_known must take the sound origin")

	# (1) vision wins over sound
	_brain.set_target_position(Vector3(9, 0, 9))
	_brain._on_sound_emitted({
		"origin": Vector3(3, 0, 4), "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [_brain.guard_id],
	})
	_tick(1, 1.0)
	assert_eq(_brain.last_known, Vector3(9, 0, 9),
		"vision must outrank sound as the last_known source")

	# (3) neither -> the previous value is preserved
	_tick(1, 0.0)
	assert_eq(_brain.last_known, Vector3(9, 0, 9),
		"with neither stimulus, last_known must be preserved (not cleared)")


func test_sound_only_alert_falls_through_to_search() -> void:
	# Edge E7: pure sound can push S past 60, but the guard must not "draw steel
	# at thin air" — with no vision it drops to SEARCH within LOST_TARGET_RT and
	# heads for the last sound origin.
	var sound := SoundPropagator.new()
	autofree(sound)
	_brain.set_transform_state(Vector3.ZERO, 0.0)
	_brain.set_sound_system(sound)

	# falloff at 6m inside a 10m radius = 0.4 -> KS(15) * 0.4 = +6.0 per impulse,
	# so 11 impulses clear THR_ALERT(60) with margin.
	for i in range(11):
		_brain._on_sound_emitted({
			"origin": Vector3(6, 0, 0), "radius": 10.0, "intensity": 1.0,
			"target_guard_ids": [_brain.guard_id],
		})
		_tick(1, 0.0)
	assert_gte(_brain.suspicion, GuardBrain.THR_ALERT,
		"repeated full-strength sound impulses must push S past THR_ALERT(60)")
	assert_eq(_brain.get_state(), EventBus.GuardState.ALERT, "sound alone can reach ALERT")

	var lost_ticks := int(round(GuardBrain.LOST_TARGET_RT / GuardBrain.TICK_DT))
	_tick(lost_ticks, 0.0)
	assert_eq(_brain.get_state(), EventBus.GuardState.SEARCH,
		"E7: with no vision the guard must fall through ALERT -> SEARCH")
	assert_eq(_brain.last_known, Vector3(6, 0, 0),
		"E7: last_known must point at the sound origin, not at nothing")
