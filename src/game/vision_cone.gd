class_name VisionCone
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5). E05 vision-cone.
# Single guard cone: 35deg half-angle / 14m range (= grid cell, ADR-002),
# recomputed at <= 10Hz with per-guard phase offset (G-03). Visibility =
# InCone * LOS_clear * light_sensitivity(get_light_level). _process uses a
# REAL-time accumulator (vision-cone §2: tick is real-time, not time_scale).

const HALF_ANGLE_DEG := 35.0
const RANGE := 14.0
const TICK_HZ := 10.0

var guard_id := 1
var observer_pos: Vector3 = Vector3.ZERO
var observer_forward: Vector3 = Vector3.FORWARD
var player_pos: Vector3 = Vector3.ZERO
var _accum := 0.0
var _last_ms := 0
var _light: LightModel = null
var _query: SpatialQueryWrapper = null

signal vision_stimulus(guard_id: int, target: Node, visibility: float)


func _ready() -> void:
	if _light == null:
		_light = LightModel.new()
	if _query == null:
		_query = SpatialQueryWrapper.new()
	# Phase-offset the tick so multiple guards don't all fire on the same frame.
	_accum = randf() * (1.0 / TICK_HZ)


func set_light_model(lm: LightModel) -> void:
	_light = lm


func compute_visibility(target: Vector3) -> float:
	var to_t := target - observer_pos
	var dist := to_t.length()
	if dist > RANGE:
		return 0.0
	var dir := to_t.normalized()
	var ang := rad_to_deg(observer_forward.angle_to(dir))
	if ang > HALF_ANGLE_DEG:
		return 0.0
	var los := true
	if _query != null:
		los = _query.has_line_of_sight(observer_pos, target, 1)
	if not los:
		return 0.0
	var lvl := 1.0
	if _light != null:
		lvl = _light.get_light_level(target)
	var sens := 1.0
	if _light != null:
		sens = _light.light_sensitivity(lvl)
	return sens


func _process(_scaled: float) -> void:
	# Real-time tick accumulator (vision-cone §2: not time_scale-scaled).
	var now := Time.get_ticks_msec()
	var rd := 0.0
	if _last_ms > 0:
		rd = float(now - _last_ms) / 1000.0
	_last_ms = now
	if rd <= 0.0:
		return
	_accum += rd
	var step := 1.0 / TICK_HZ
	while _accum >= step:
		_accum -= step
		var v := compute_visibility(player_pos)
		vision_stimulus.emit(guard_id, null, v)
