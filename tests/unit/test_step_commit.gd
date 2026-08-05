# tests/unit/test_step_commit.gd
# GUT unit tests for the real E03 StepCommit + E02 TimeController.
# Covers: stealth-step-commit (landing point + noise radius budget) and
# rtwp-time-model (focus -> 0.25, real-time cooldown per ADR-003).
#
# E08-S4 UPDATE (Sprint 1, Batch C): the ExposureGuardStub that used to live here
# is GONE. It was the last remaining stub in the suite, standing in for
# GuardBrain's exposure timer while E08 was unimplemented. src/game/patrol_ai.gd
# now ships, so test_exposure_grace_1_2s below drives the REAL GuardBrain and the
# 1.2s grace window is verified against production code instead of a lookalike.
# Every system in this file now uses its real class via preload.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const StepCommit = preload("res://src/game/step_commit.gd")
const TimeController = preload("res://src/core/time_controller.gd")
const GuardBrain = preload("res://src/game/patrol_ai.gd")
const EventBus = preload("res://src/core/event_bus.gd")


var _step: StepCommit
var _time: TimeController
var _bus: EventBus
var _exp: GuardBrain
var _captured_step: Dictionary = {}
var _commit_count: int = 0


func before_each() -> void:
	_step = StepCommit.new()
	# StepCommit is a Node and is deliberately kept OUT of the tree (the VFX path
	# must stay gated), but it still has to be released or every test in this
	# file leaks one node. Same ADDCHILD-AUTOFREE-01 discipline as _time below,
	# just via autofree() instead of add_child_autofree().
	autofree(_step)
	_time = TimeController.new()
	# In tree so enter_focus/exit_focus tweens are valid. autofree replaces the
	# hand-rolled remove_child+free that used to live in after_each: GUT frees
	# this right after each test (ADDCHILD-AUTOFREE-01).
	add_child_autofree(_time)
	watch_signals(_step)
	watch_signals(_time)
	_step.player_step_committed.connect(_capture_step)
	# Real GuardBrain (E08). Kept OUT of the scene tree so its _process cannot
	# inject wall-clock ticks: every decision below is driven explicitly.
	# autofree keeps the orphan count flat (ADDCHILD-AUTOFREE-01 discipline).
	_bus = EventBus.new()
	autofree(_bus)
	_exp = GuardBrain.new()
	autofree(_exp)
	_exp.guard_id = 1
	_exp.set_event_bus(_bus)
	watch_signals(_bus)
	_captured_step = {}


func after_each() -> void:
	Engine.time_scale = 1.0   # reset global scale possibly polluted by focus tween
	# _time is released by add_child_autofree after this method returns; the old
	# manual remove_child+free is gone so there is exactly ONE teardown path.
	_step = null
	_time = null
	_bus = null
	_exp = null


func _capture_step(p: Dictionary) -> void:
	_captured_step = p


func _count_commit(_p: Dictionary = {}) -> void:
	_commit_count += 1


func test_commit_moves_player_to_landing_point():
	# E03-S4: committing a step records the landing point and emits footfall.
	var from := Vector3.ZERO
	var to := Vector3(0, 0, 1.5)
	_step.commit(from, to, "STONE")
	assert_eq(_captured_step.get("to", null), to, "landing point must equal the aimed target")
	assert_eq(_captured_step.get("from", null), from, "origin must equal the player position")
	assert_signal_emitted(_step, "player_step_committed",
		"footfall must drive sound + vision recompute (ADR-002)")


func test_commit_noise_radius_matches_budget():
	# E03-S4: noise_radius = BASE(5.0) * surface(STONE=1.0) * gait(SNEAK=0.5)
	_step.gait = "SNEAK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "STONE")
	var expected := 5.0 * 1.0 * 0.5
	assert_eq(_captured_step.get("noise_radius", -1.0), expected,
		"noise_radius must be 5.0 * surface * gait (control-manifest / §4)")


func test_focus_enters_slowmo_at_0_25():
	# E02-S1 + T-02: FOCUS emits time_scale_changed and sets mode FOCUS.
	assert_eq(_time.mode, "FLOWING", "starts FLOWING at 1.0")
	_time.enter_focus()
	assert_eq(_time.mode, "FOCUS", "mode must be FOCUS")
	assert_eq(_time.FOCUS_SCALE, 0.25, "FOCUS_SCALE constant must be 0.25 (T-02)")
	assert_signal_emitted(_time, "time_scale_changed",
		"HUD / audio / particles subscribe to this")


func test_focus_exit_restores_flowing():
	# E02-S1: releasing focus restores 1.0.
	_time.enter_focus()
	_time.exit_focus()
	assert_eq(_time.mode, "FLOWING", "mode must be FLOWING after release")


# --- E09-S5b (Sprint 2 · Batch C) --------------------------------------------
# The accessibility slider and the clock are two different objects; this test
# closes the seam between them. The MODEL's own bounds are asserted in
# test_a11y_settings.gd — what is proven HERE is the half no model test can see:
# that enter_focus() ramps to the player's number instead of the constant, and
# that changing it mid-focus is still a RAMP rather than a hard cut (V-06).
func test_focus_honours_user_time_scale() -> void:
	assert_almost_eq(_time.user_scale, TimeController.FOCUS_SCALE, 0.0001,
		"E09-S5b: an un-configured clock must behave exactly as Sprint 0 (T-02 = 0.25)")

	# T-01 clamp, BOTH ends. set_user_scale returns what it actually stored, so
	# a settings UI can echo the clamp back instead of showing a value the clock
	# silently refused.
	assert_almost_eq(_time.set_user_scale(5.0), TimeController.USER_MAX, 0.0001,
		"T-01: an over-range slider value must clamp to USER_MAX, never pass through")
	assert_almost_eq(_time.set_user_scale(-1.0), TimeController.USER_MIN, 0.0001,
		"T-01: an under-range value must clamp to USER_MIN (the physics floor)")

	# The chosen depth is what FOCUS actually ramps to.
	_time.set_user_scale(0.5)
	_time.enter_focus()
	assert_eq(_time.mode, "FOCUS", "the slider must not disturb the state machine")
	assert_almost_eq(_time.get_ramp_target(), 0.5, 0.0001,
		"E09-S5b: FOCUS must ramp to the PLAYER's scale, not to the FOCUS_SCALE constant")

	# V-06: a mid-focus drag RE-RAMPS. RAMP > 0 is the non-hard-cut guarantee.
	assert_gt(TimeController.RAMP, 0.0, "V-06: the focus transition must be eased, never cut")
	_time.set_user_scale(0.8)
	assert_almost_eq(_time.get_ramp_target(), 0.8, 0.0001,
		"V-06: a mid-focus change must re-ramp to the new target")

	# event-vocab-zero-drift: the retarget re-announces on the EXISTING signal.
	# Exactly two emissions so far — enter_focus and the mid-focus retarget; the
	# three FLOWING-mode slider writes above must stay silent, because a HUD
	# should not repaint for a setting that changes nothing on screen yet.
	assert_signal_emit_count(_time, "time_scale_changed", 2,
		"E09-S5b: only enter_focus + the mid-focus retarget may announce")

	_time.exit_focus()
	assert_almost_eq(_time.get_ramp_target(), TimeController.FLOWING_SCALE, 0.0001,
		"leaving FOCUS must ramp back to 1.0 regardless of where the slider sits")


func test_commit_cooldown_uses_real_time_not_scaled():
	# E03-S1 + E02-S3 + ADR-003 risk4: cooldown uses WALLCLOCK, not scaled delta.
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0), "STONE")
	assert_false(_step.can_commit(), "must not accept a second commit during cooldown")
	_step.tick_real(0.13)  # 0.13s of REAL time passes (regardless of time_scale)
	assert_true(_step.can_commit(), "cooldown (0.12s real) must have elapsed")


func _expose_for(ticks: int, visibility: float) -> void:
	for i in range(ticks):
		_exp._pending_vision = visibility
		_exp._decide(GuardBrain.TICK_DT)


func test_exposure_grace_1_2s():
	# H5 / E08-S4 + consistency-review C4: ALERT + visible for GRACE_RT(1.2s) of
	# REAL time is a soft fail. This used to run against ExposureGuardStub; it
	# now runs against the shipping GuardBrain.
	_exp.suspicion = 100.0
	_expose_for(1, 1.0)                       # CALM -> ALERT (single cross-level hop)
	assert_eq(_exp.get_state(), EventBus.GuardState.ALERT,
		"a saturated guard must reach ALERT before the grace clock can start")
	assert_almost_eq(_exp.exposure_timer, 0.0, 0.0001,
		"the grace clock only starts once the guard is ALREADY in ALERT")

	# 1.0s of continuous exposure is still inside the window.
	_expose_for(10, 1.0)
	assert_almost_eq(_exp.exposure_timer, 1.0, 0.0001,
		"the exposure clock must accumulate real time while ALERT + visible")
	assert_signal_not_emitted(_bus, "exposure_detected",
		"no exposure before the 1.2s grace elapses")

	# Two more ticks cross GRACE_RT.
	_expose_for(2, 1.0)
	assert_signal_emitted(_bus, "exposure_detected",
		"soft-fail exposure must fire after 1.2s of continuous visibility")
	assert_almost_eq(_exp.suspicion, 0.0, 0.0001,
		"a soft fail must reset the guard's suspicion to 0")
	assert_eq(_exp.get_state(), EventBus.GuardState.RETURN,
		"a soft fail must force the FSM down the RETURN path")


func test_exposure_grace_resets_when_los_breaks():
	# E08-S4: breaking line of sight INSIDE the grace window is the player's
	# escape hatch — the clock must RESET, not merely pause. This is the
	# mechanical basis of pillar 1 ("you get 1.2s to fix it").
	_exp.suspicion = 100.0
	_expose_for(1, 1.0)
	_expose_for(10, 1.0)
	assert_gt(_exp.exposure_timer, 0.9, "the grace clock is running")

	_expose_for(1, 0.0)                       # duck behind cover
	assert_almost_eq(_exp.exposure_timer, 0.0, 0.0001,
		"breaking LOS inside the grace window must RESET the exposure clock")
	assert_signal_not_emitted(_bus, "exposure_detected",
		"a player who breaks LOS in time must never trip the soft fail")

	# ...and the clock genuinely restarts from zero: 11 more visible ticks (1.1s)
	# must still be under the wire.
	_expose_for(11, 1.0)
	assert_signal_not_emitted(_bus, "exposure_detected",
		"after a reset the player gets the full 1.2s again, not the remainder")


func test_non_idle_rejects_commit():
	# E03-S1: only IDLE accepts a commit; RECOVERING must be rejected (no combo).
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0), "STONE")
	assert_eq(_step.state, "RECOVERING", "first commit moves to RECOVERING")
	_commit_count = 0
	_step.player_step_committed.connect(_count_commit)
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2.0), "STONE")  # must be ignored (not IDLE)
	assert_eq(_commit_count, 0, "second commit while RECOVERING must be ignored")
	_step.player_step_committed.disconnect(_count_commit)


func test_gait_switch_changes_noise_radius():
	# E03-S2 / E03-S5: noise_radius = 5.0 * surface * gait (per implementation).
	# NOTE: implementation SURFACE_FACTOR uses STONE=1.0 (see qa-plan §6.2 drift).
	_step.gait = "SNEAK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "STONE")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 2.5, 0.0001,
		"SNEAK+STONE must be 5.0*1.0*0.5 = 2.5")
	_step.tick_real(0.13)
	_step.gait = "WALK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "STONE")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 5.0, 0.0001,
		"WALK+STONE must be 5.0*1.0*1.0 = 5.0")


func test_commit_emits_step_signal_no_direct_sound():
	# G1 (S1C-FIX-01): commit emits player_step_committed, but NO LONGER emits
	# sound_emitted directly. Sound is owned solely by SoundPropagator (E06),
	# which subscribes to player_step_committed on the EventBus and emits the
	# full sound_emitted payload. The prior assertion that StepCommit emitted
	# sound_emitted directly encoded the legacy dual-emit path (design-review
	# G1) that this fix removes, so it is corrected here (test's-own-bug fix).
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "STONE")
	assert_signal_emitted(_step, "player_step_committed",
		"commit must emit player_step_committed")
	assert_signal_not_emitted(_step, "sound_emitted",
		"G1: StepCommit must NOT emit sound_emitted directly; SoundPropagator owns it via the bus")


func test_noise_radius_all_surfaces():
	# E03-S5: noise_radius = NOISE_BASE(5.0) * surface_factor * gait_factor.
	# Covers the MOSS surface (proposed 0.5, flagged GDD gap) plus the Sprint 0
	# STONE/GRASS/METAL set.
	_step.gait = "SNEAK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "MOSS")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 1.25, 0.0001,
		"SNEAK+MOSS = 5.0 * 0.5 * 0.5 = 1.25")
	_step.tick_real(0.13)

	_step.gait = "WALK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "GRASS")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 3.5, 0.0001,
		"WALK+GRASS = 5.0 * 0.7 * 1.0 = 3.5")
	_step.tick_real(0.13)

	_step.gait = "RUN"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "METAL")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 12.0, 0.0001,
		"RUN+METAL = 5.0 * 1.2 * 2.0 = 12.0")


func test_gait_run_noise_and_step():
	# E03-S6: switching to RUN applies RUN's distance / step_duration / noise
	# factor. RUN is a HIGH-COST deliberate option (10 m noise), not a free sprint.
	_step.gait = "RUN"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 4.0), "STONE")
	assert_eq(_captured_step.get("gait"), "RUN", "commit must record RUN gait")
	assert_almost_eq(_captured_step.get("distance", -1.0), 4.0, 0.0001,
		"RUN step distance must be 4.0 (max_step)")
	assert_almost_eq(_captured_step.get("step_duration", -1.0), 0.24, 0.0001,
		"RUN step_duration must be 0.24 (base)")
	assert_almost_eq(_captured_step.get("noise_radius", -1.0), 10.0, 0.0001,
		"RUN+STONE noise = 5.0 * 1.0 * 2.0 = 10.0 (high-cost)")
	# T-02 / ADR-003: at FOCUS (0.25) the same step plays ~4x slower in wall-clock.
	assert_almost_eq(_step.effective_step_duration(0.25), 0.96, 0.0001,
		"RUN step_duration scales 1/time_scale (0.24/0.25 = 0.96 at FOCUS)")


func test_footfall_vfx_present():
	# E03-S7: footfall VFX contract, headless-safe.
	# 1) surface is written into the payload for E06-S2 consumption.
	_step.gait = "WALK"
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2.0), "MOSS")
	assert_eq(_captured_step.get("surface"), "MOSS",
		"payload must carry surface for E06-S2")
	# 2) ghost_trail is capped at MAX_GHOST (<= 6) regardless of VFX.
	for i in range(10):
		_step.tick_real(0.13)
		_step.commit(Vector3(0, 0, float(i)), Vector3(0, 0, float(i + 1)), "STONE")
	assert_true(_step._ghost_trail.size() <= StepCommit.MAX_GHOST,
		"ghost_trail must stay <= MAX_GHOST (6)")
	assert_eq(_step._ghost_trail.size(), StepCommit.MAX_GHOST,
		"ghost_trail must be exactly capped at 6")
	# 3) Headless: VFX node creation must be skipped (StepCommit not in a live
	# tree) so the commit never crashes without a scene tree.
	assert_false(_step.is_vfx_enabled(),
		"VFX must be skipped when StepCommit is not inside a live tree (headless-safe)")
