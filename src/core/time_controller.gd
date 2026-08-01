class_name TimeController
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 single source of truth for global time scaling (ADR-003 / E02).
# Drives the world via Engine.time_scale:
#   - FLOWING : time_scale = 1.0 (normal play)
#   - FOCUS   : time_scale = 0.25 (hold 凝神, eased ramp, non-hard-cut V-06)
#
# CRITICAL (ADR-003 risk 4): gameplay cooldown / timers MUST use REAL time
# (Time.get_ticks_msec() or accumulated unscaled delta), never the scaled
# _process delta. This controller only owns Engine.time_scale; it never feeds
# scaled delta back into any cooldown logic.

const FOCUS_SCALE := 0.25   # rtwp-time-model T-02 (default focus slow-mo)
const RAMP := 0.15          # ease ramp duration, non-hard-cut (V-06)
const USER_MIN := 0.1       # T-02 lower clamp (physics stability floor)
const USER_MAX := 1.0       # T-01 upper clamp

var mode := "FLOWING"       # FLOWING | FOCUS | PAUSED

signal time_scale_changed(old: float, new: float, mode: String)

var _tween: Tween = null


func enter_focus() -> void:
	if mode == "FOCUS":
		return
	var old := Engine.time_scale
	var new_scale := FOCUS_SCALE
	_ramp_to(new_scale)
	mode = "FOCUS"
	time_scale_changed.emit(old, new_scale, mode)


func exit_focus() -> void:
	if mode == "FLOWING":
		return
	var old := Engine.time_scale
	var new_scale := 1.0
	_ramp_to(new_scale)
	mode = "FLOWING"
	time_scale_changed.emit(old, new_scale, mode)


func _ramp_to(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(Engine, "time_scale", target, RAMP)
