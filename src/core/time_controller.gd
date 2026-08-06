class_name TimeController
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5), Sprint 2 Batch C (E09-S5b).
# L2 single source of truth for global time scaling (ADR-003 / E02).
# Drives the world via Engine.time_scale:
#   - FLOWING : time_scale = 1.0 (normal play)
#   - FOCUS   : time_scale = user_scale (default 0.25, eased ramp, V-06)
#   - PAUSED  : time_scale = 0.0 (menus / save screen only, T-03). Wired in
#               S3-B by E-11; see enter_paused() for why this one transition is
#               a hard assignment rather than a ramp, and why T-03's remaining
#               open question (get_tree().paused vs time_scale = 0) changes
#               exactly one function body and nothing else.
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
const PAUSED_SCALE := 0.0   # T-03 完全冻结, menus only — never a gameplay state


## L2 time mode. All three values are LIVE as of S3-B (E-11).
##
## PAUSED was declared-only for two sprints — nothing assigned it and no
## enter/exit pair existed, so every `match mode` branch on it was dead code.
## It is now wired, and it is wired HERE rather than in the UI because three
## documents already route through this enum:
##   · control-manifest T-03            (显式暂停, menus / settings only)
##   · accessibility-matrix 行 10        (显式暂停读场辅助 — a promised a11y feature)
##   · design/audio/s3b-save-load-audio-spec.md §1.4
##       (World bus PAUSED preset, -12 dB / LPF 700 Hz, driven off this mode)
##
## ★ Consumers subscribe to time_scale_changed and read the third argument.
## Do NOT add a second pause signal: E01-S9 froze the event vocabulary, and the
## existing signal already carries the mode.
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


## E-11 (S3-B). Enter T-03 explicit pause. Callers: SaveSlotsScreen.open_screen()
## today; any future pause / settings screen tomorrow.
##
## ★ WHY THIS IS A HARD ASSIGNMENT AND NOT _ramp_to() ★
## _ramp_to() drives Engine.time_scale with a Tween, and a Tween's own delta is
## itself scaled by Engine.time_scale. Ramping TOWARD zero is therefore a Zeno
## problem: the closer the clock gets to 0, the slower the ramp that is trying
## to reach it, and it never arrives. Ramping back OUT of 0 is worse — a Tween
## created while time_scale is exactly 0.0 never advances at all, and the game
## would stay frozen forever. Both directions must bypass the tween.
##
## V-06「禁硬切」is not violated: it governs visual TRANSITIONS (「禁硬切闪光」),
## and opening a menu is not a world transition. The audible side of the same
## rule is AUD-V6, which AudioDirector honours with its own 120 ms wall-clock
## ramp on the World bus — a ramp that keeps running precisely because it does
## not read a scaled delta.
##
## T-03 has still not chosen between `get_tree().paused = true` and
## `time_scale = 0`. This function implements the latter. If T-03 later picks
## the former, THIS BODY is the only thing that changes: the mode value, the
## signal and every subscriber stay exactly as they are.
func enter_paused() -> void:
	if mode == "PAUSED":
		return
	var old := Engine.time_scale
	_freeze_to(PAUSED_SCALE)
	mode = "PAUSED"
	time_scale_changed.emit(old, PAUSED_SCALE, mode)


## E-11 (S3-B). Leave T-03 explicit pause, always back to FLOWING.
##
## Never back to FOCUS: 凝神 and 暂停 are mutually exclusive by construction
## (audio spec §1.4 —「打开暂停菜单必然先退出 FOCUS」), so there is no prior
## focus state to restore, and restoring one would silently re-enter slow-mo
## from a menu.
##
## ★ MUST be called on EVERY exit path, including the one that does not look
## like a close: a successful load tears the save screen down through
## _end_load_fade(), not close_screen(). Miss that path and the game returns to
## the world with Engine.time_scale still 0.0 — permanently frozen, with no
## error and nothing for CI to catch.
func exit_paused() -> void:
	if mode != "PAUSED":
		return
	var old := Engine.time_scale
	_freeze_to(FLOWING_SCALE)
	mode = "FLOWING"
	time_scale_changed.emit(old, FLOWING_SCALE, mode)


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


## Instant, tween-free clock assignment. Used only by the PAUSED transitions —
## see enter_paused() for the Zeno argument. Kills any ramp in flight so a
## half-finished FOCUS ramp cannot land on top of the pause a frame later.
func _freeze_to(target: float) -> void:
	_ramp_target = target
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	Engine.time_scale = target


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
