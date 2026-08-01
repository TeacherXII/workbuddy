class_name StepCommit
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5). E03 stealth-step-commit.
# Real implementation of the read-and-step loop. Commit cooldowns use REAL
# time (ADR-003 risk 4): _process derives an unscaled delta from the wall
# clock so focus slow-mo never delays the commit cadence.

const COMMIT_COOLDOWN_RT := 0.12   # stealth-step-commit §3 (real-time floor)
const NOISE_BASE := 5.0            # noise radius base (m)
const GAIT_FACTOR := {"SNEAK": 0.5, "WALK": 1.0}
const SURFACE_FACTOR := {"STONE": 1.0, "GRASS": 0.7, "METAL": 1.2}
const MAX_GHOST := 6

var state := "IDLE"                 # IDLE / AIMING / COMMITTING / RECOVERING
var gait := "SNEAK"                 # SNEAK | WALK
var _cooldown := 0.0
var _ghost_trail: Array[Vector3] = []
var aim_point: Vector3 = Vector3.ZERO

signal player_step_committed(payload: Dictionary)
signal sound_emitted(payload: Dictionary)

var _last_ms := 0


func can_commit() -> bool:
	return state == "IDLE" and _cooldown <= 0.0


func commit(from: Vector3, to: Vector3, surface: String) -> void:
	if not can_commit():
		return
	state = "COMMITTING"
	var noise_radius := NOISE_BASE \
		* float(SURFACE_FACTOR.get(surface, 1.0)) \
		* float(GAIT_FACTOR.get(gait, 1.0))
	player_step_committed.emit({
		"from": from,
		"to": to,
		"surface": surface,
		"gait": gait,
		"noise_radius": noise_radius,
	})
	# Footstep foley hook: drive the sound system from the landing point.
	sound_emitted.emit({"pos": to, "radius": noise_radius})
	_push_ghost(from)
	state = "RECOVERING"
	_cooldown = COMMIT_COOLDOWN_RT


func _push_ghost(p: Vector3) -> void:
	_ghost_trail.append(p)
	if _ghost_trail.size() > MAX_GHOST:
		_ghost_trail.pop_front()


func tick_real(delta: float) -> void:
	# Real-time cooldown / state recovery (ADR-003: never a scaled delta).
	_cooldown = max(0.0, _cooldown - delta)
	if state == "RECOVERING" and _cooldown <= 0.0:
		state = "IDLE"


func _process(_scaled: float) -> void:
	# Real-time accumulator: Engine.time_scale scales the _process delta, so
	# derive an unscaled delta from the wall clock instead (ADR-003 risk 4).
	var now := Time.get_ticks_msec()
	var rd := 0.0
	if _last_ms > 0:
		rd = float(now - _last_ms) / 1000.0
	_last_ms = now
	if rd > 0.0:
		tick_real(rd)
