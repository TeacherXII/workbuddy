class_name StepCommit
extends Node

# ASHEN STEP — Sprint 1. E03 stealth-step-commit (full: 3 gaits + MOSS surface
# + footfall VFX). Real implementation of the read-and-step loop. Commit
# cooldowns use REAL time (ADR-003 risk 4): _process derives an unscaled delta
# from the wall clock so focus slow-mo never delays the commit cadence.

const COMMIT_COOLDOWN_RT := 0.12   # stealth-step-commit §3 (real-time floor)
const NOISE_BASE := 5.0            # noise radius base (m)
const MAX_GHOST := 6               # ghost_trail cap (E03)

# Surface attenuation. Authoritative values from stealth-step-commit §2
# (design/gdd/systems/stealth-step-commit.md): Surface = {STONE,GRASS,METAL,MOSS},
# STONE 1.0 is the canonical gameplay value (WOOD maps to STONE); MOSS 0.5 is
# quieter than GRASS 0.7.
const SURFACE_FACTOR := {
	"STONE": 1.0,
	"GRASS": 0.7,
	"METAL": 1.2,
	"MOSS": 0.5,
}

# Gait parameters (stealth-step-commit §2 + E03-S6).
#   max_step     : real-world distance per step (m)
#   step_duration: base step duration (s); scales with time_scale at playback (T-02)
#   noise_factor : gait multiplier in the noise radius formula (gait_factor)
# RUN is a HIGH-COST, DELIBERATE option (user ruling D1): a 10 m noise radius that
# meaningfully alerts guards. It is NOT a "free sprint" -- the feel must read as a
# committed, risky maneuver, never an auto-escape. (C-05: RUN feedback uses shape,
# not just color.)
const GAIT_PARAMS := {
	"SNEAK": {"max_step": 1.5, "step_duration": 0.55, "noise_factor": 0.5},
	"WALK":  {"max_step": 2.5, "step_duration": 0.38, "noise_factor": 1.0},
	"RUN":   {"max_step": 4.0, "step_duration": 0.24, "noise_factor": 2.0},
}

const FootfallVFX = preload("res://src/game/footfall_vfx.gd")

var state := "IDLE"                 # IDLE / AIMING / COMMITTING / RECOVERING
var gait := "SNEAK"                 # SNEAK | WALK | RUN
var _cooldown := 0.0
var _ghost_trail: Array[Vector3] = []
var aim_point: Vector3 = Vector3.ZERO
var _vfx: FootfallVFX = null

signal player_step_committed(payload: Dictionary)
signal sound_emitted(payload: Dictionary)

var _last_ms := 0


func can_commit() -> bool:
	return state == "IDLE" and _cooldown <= 0.0


func commit(from: Vector3, to: Vector3, surface: String) -> void:
	if not can_commit():
		return
	state = "COMMITTING"
	var gp: Dictionary = GAIT_PARAMS.get(gait, GAIT_PARAMS["WALK"])
	var surface_factor := float(SURFACE_FACTOR.get(surface, 1.0))
	var noise_radius := NOISE_BASE * surface_factor * float(gp["noise_factor"])
	var distance := from.distance_to(to)
	var step_duration := float(gp["step_duration"])
	# payload carries surface for E06-S2 (sound radius by surface) and distance /
	# step_duration for HUD/a11y + time_scale-scaled playback (T-02).
	player_step_committed.emit({
		"from": from,
		"to": to,
		"surface": surface,
		"gait": gait,
		"distance": distance,
		"noise_radius": noise_radius,
		"step_duration": step_duration,
	})
	# G1 (S1C-FIX-01): sound is owned solely by SoundPropagator (E06-S2), which
	# subscribes to `player_step_committed` on the EventBus and emits the full
	# `sound_emitted` payload (origin/radius/intensity/source/target_guard_ids).
	# StepCommit no longer emits sound_emitted directly -- that dual path caused
	# a duplicate, field-incomplete sound_emitted on the bus (design-review G1).
	# The `signal sound_emitted` declaration on this class is intentionally kept
	# so the public API is unchanged, but it is never emitted from here.
	_push_ghost(from)
	_spawn_footfall_vfx(from, to, surface)
	state = "RECOVERING"
	_cooldown = COMMIT_COOLDOWN_RT


func effective_step_duration(time_scale: float) -> float:
	# T-02 / ADR-003: playback duration expands as time_scale shrinks. At FOCUS
	# (0.25) a RUN step plays ~4x slower in wall-clock. Paused (<=0) -> base.
	var gp: Dictionary = GAIT_PARAMS.get(gait, GAIT_PARAMS["WALK"])
	var base := float(gp["step_duration"])
	if time_scale <= 0.0:
		return base
	return base / time_scale


func _push_ghost(p: Vector3) -> void:
	_ghost_trail.append(p)
	if _ghost_trail.size() > MAX_GHOST:
		_ghost_trail.pop_front()


func _spawn_footfall_vfx(from: Vector3, to: Vector3, surface: String) -> void:
	# E03-S7: landing micro-glow + surface-variant footfall foley. Rendering-only;
	# only meaningful inside a live scene tree with a main loop. Unit tests create
	# StepCommit WITHOUT a tree, so this is skipped and the commit stays safe
	# (headless-friendly: no node/tween creation when there is no tree).
	if Engine.get_main_loop() == null:
		return
	if not is_inside_tree():
		return
	if _vfx == null:
		var vfx_script := load("res://src/game/footfall_vfx.gd")
		if vfx_script == null:
			push_warning("ASHEN STEP: footfall_vfx.gd not found, skipping VFX spawn")
			return
		_vfx = vfx_script.new()
		add_child(_vfx)
	_vfx.spawn_landing_glow(to)
	_vfx.emit_foley(surface)


func is_vfx_enabled() -> bool:
	# True only when rendering is actually possible (live tree + main loop).
	return Engine.get_main_loop() != null and is_inside_tree()


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
