# tests/unit/test_step_commit.gd
# GUT unit tests for the real E03 StepCommit + E02 TimeController.
# Covers: stealth-step-commit (landing point + noise radius budget) and
# rtwp-time-model (focus -> 0.25, real-time cooldown per ADR-003).
#
# E08 (patrol-ai exposure grace) is NOT implemented in Sprint 0. The single
# ExposureGuardStub below is the ONLY retained stub and stands in for
# GuardBrain's exposure timer until Sprint 1. All other systems use the real
# classes via preload (Phase 4 smoke stubs removed).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const StepCommit = preload("res://src/game/step_commit.gd")
const TimeController = preload("res://src/core/time_controller.gd")


# ---- Single allowed stub: E08 GuardBrain exposure timer (Sprint 1) ----
class ExposureGuardStub:
	signal exposure_detected(guard_id, target)
	var grace_rt: float = 1.2            # GRACE_RT real-time (patrol-ai §3)
	var exposure_timer: float = 0.0
	var alert: bool = false

	func set_alert(v: bool) -> void:
		alert = v
		if not v:
			exposure_timer = 0.0

	func tick_real(delta: float, visibility: float) -> void:
		if alert and visibility > 0.0:
			exposure_timer += delta
			if exposure_timer >= grace_rt:
				exposure_detected.emit(1, null)
		else:
			exposure_timer = max(0.0, exposure_timer - delta)


var _step: StepCommit
var _time: TimeController
var _exp: ExposureGuardStub
var _captured_step: Dictionary = {}
var _commit_count: int = 0


func before_each() -> void:
	_step = StepCommit.new()
	_time = TimeController.new()
	add_child(_time)   # in tree so enter_focus/exit_focus tweens are valid
	watch_signals(_step)
	watch_signals(_time)
	_step.player_step_committed.connect(_capture_step)
	_exp = ExposureGuardStub.new()
	watch_signals(_exp)
	_captured_step = {}


func after_each() -> void:
	Engine.time_scale = 1.0   # reset global scale possibly polluted by focus tween
	if _time != null:
		if _time.get_parent() != null:
			_time.get_parent().remove_child(_time)
		_time.free()
	_step = null
	_time = null
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


func test_commit_cooldown_uses_real_time_not_scaled():
	# E03-S1 + E02-S3 + ADR-003 risk4: cooldown uses WALLCLOCK, not scaled delta.
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0))
	assert_false(_step.can_commit(), "must not accept a second commit during cooldown")
	_step.tick_real(0.13)  # 0.13s of REAL time passes (regardless of time_scale)
	assert_true(_step.can_commit(), "cooldown (0.12s real) must have elapsed")


func test_exposure_grace_1_2s_triggers_soft_fail():
	# E08-S4 + consistency-review C4: ALERT + visible for grace 1.2s real -> soft fail.
	# NOTE: E08 (GuardBrain) is unimplemented in Sprint 0; ExposureGuardStub is
	# the only retained stub (see header). Real E08 lands in Sprint 1.
	_exp.set_alert(true)
	_exp.tick_real(1.0, 1.0)  # still inside the grace window
	assert_signal_not_emitted(_exp, "exposure_detected",
		"no exposure before the 1.2s grace elapses")
	_exp.tick_real(0.3, 1.0)  # grace window (1.2s) exceeded
	assert_signal_emitted(_exp, "exposure_detected",
		"soft-fail exposure must fire after 1.2s of continuous visibility")


func test_non_idle_rejects_commit():
	# E03-S1: only IDLE accepts a commit; RECOVERING must be rejected (no combo).
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.0))
	assert_eq(_step.state, "RECOVERING", "first commit moves to RECOVERING")
	_commit_count = 0
	_step.player_step_committed.connect(_count_commit)
	_step.commit(Vector3.ZERO, Vector3(0, 0, 2.0))  # must be ignored (not IDLE)
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


func test_commit_emits_both_signals_with_payload():
	# E03-S4 / E03-S6: commit emits player_step_committed AND sound_emitted.
	_step.commit(Vector3.ZERO, Vector3(0, 0, 1.5), "STONE")
	assert_signal_emitted(_step, "player_step_committed",
		"commit must emit player_step_committed")
	assert_signal_emitted(_step, "sound_emitted",
		"commit must emit sound_emitted (footfall)")


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
