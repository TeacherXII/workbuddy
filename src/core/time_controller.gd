class_name TimeController
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5), Sprint 2 Batch C (E09-S5b).
# L2 single source of truth for global time scaling (ADR-003 / E02).
# Drives the world via Engine.time_scale:
#   - FLOWING : time_scale = 1.0 (normal play)
#   - FOCUS   : time_scale = user_scale (default 0.25, eased ramp, V-06)
#
# CRITICAL (ADR-003 risk 4): gameplay cooldown / timers MUST use REAL time
# (Time.get_ticks_msec() or accumulated unscaled delta), never the scaled
# _process delta. This controller only owns Engine.time_scale; it never feeds
# scaled delta back into any cooldown logic. E09-S5b does not change that: the
# accessibility slider moves the TARGET of the ramp, never the clock any input
# or cooldown is measured against.
#
# [E09-S5b] The 凝神 depth is now player-adjustable (T-01 [0.1, 1.0], T-02
# default 0.25). The slider does NOT write Engine.time_scale directly — it
# writes `user_scale`, and every transition still goes through _ramp_to(), so
# V-06「禁硬切」holds for a mid-focus slider drag exactly as it does for
# entering focus.

const FOCUS_SCALE := 0.25   # rtwp-time-model T-02 (default focus slow-mo)
const RAMP := 0.15          # ease ramp duration, non-hard-cut (V-06)
const USER_MIN := 0.1       # T-02 lower clamp (physics stability floor)
const USER_MAX := 1.0       # T-01 upper clamp
const FLOWING_SCALE := 1.0

var mode := "FLOWING"       # FLOWING | FOCUS | PAUSED

## E09-S5b. The FOCUS target the player picked, clamped into [USER_MIN, USER_MAX].
## Defaults to FOCUS_SCALE so an un-configured build behaves exactly as Sprint 0.
## Write through set_user_scale() — a raw assignment skips the clamp and the
## mid-focus re-ramp.
var user_scale := FOCUS_SCALE

signal time_scale_changed(old: float, new: float, mode: String)

var _tween: Tween = null

# Where the CURRENT ramp is heading. Engine.time_scale only reaches it after
# RAMP seconds of real frames, which a headless unit test never gets — so this
# is the assertable half of「ramp≈0.15s 缓动，非硬切」.
var _ramp_target := FLOWING_SCALE


func enter_focus() -> void:
	if mode == "FOCUS":
		return
	var old := Engine.time_scale
	var new_scale := focus_target()
	_ramp_to(new_scale)
	mode = "FOCUS"
	time_scale_changed.emit(old, new_scale, mode)


func exit_focus() -> void:
	if mode == "FLOWING":
		return
	var old := Engine.time_scale
	var new_scale := FLOWING_SCALE
	_ramp_to(new_scale)
	mode = "FLOWING"
	time_scale_changed.emit(old, new_scale, mode)


## The scale FOCUS will ramp to right now. Always inside T-01, even if someone
## assigned `user_scale` directly.
func focus_target() -> float:
	return clampf(user_scale, USER_MIN, USER_MAX)


## Target of the ramp currently in flight (or the last one that completed).
## Engine.time_scale converges on this over RAMP seconds.
func get_ramp_target() -> float:
	return _ramp_target


## E09-S5b — the accessibility slider's ONLY entry point.
## Clamps into T-01, and if the player is already holding 凝神 the change is
## eased in over RAMP rather than snapped (V-06). Returns the value actually
## stored, so a UI slider can echo the clamp back to the player.
func set_user_scale(value: float) -> float:
	var clamped := clampf(value, USER_MIN, USER_MAX)
	if is_equal_approx(clamped, user_scale):
		return user_scale
	user_scale = clamped
	if mode == "FOCUS":
		# Mid-focus retarget: ease from wherever the previous ramp got to.
		var old := Engine.time_scale
		_ramp_to(clamped)
		time_scale_changed.emit(old, clamped, mode)
	return user_scale


## Pull the slider value out of the a11y field model. A11ySettings owns the
## field (E09-S7); this controller owns the clock. Deliberately a PULL, not a
## signal subscription: event-vocab-zero-drift forbids new bus vocabulary, and
## a direct call keeps the dependency one-way (E02 reads E09 data, never the
## other way round).
func apply_a11y(settings: A11ySettings) -> void:
	if settings == null or not is_instance_valid(settings):
		return
	set_user_scale(settings.time_scale_user)


func _ramp_to(target: float) -> void:
	_ramp_target = target
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# create_tween() requires a live tree. Outside one (headless construction,
	# a controller built but never added) fall back to recording the target so
	# the state machine stays coherent instead of pushing an error.
	if not is_inside_tree():
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(Engine, "time_scale", target, RAMP)
