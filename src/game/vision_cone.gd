class_name VisionCone
extends Node

# ASHEN STEP — Sprint 1 (Phase 5), E05 vision-cone (complete).
# Extends the Sprint 0 vertical slice with:
#   - E05-S5 cone-edge tell: emit `vision_looming(guard_id)` when the player enters
#     the 8deg rim warning band (debounced: fires on entry, re-arms after leaving).
#     Pulse is capped at <=2Hz (V-02) and the tell is brightness/shape-coded, not
#     hue-coded (C-05).
#   - E05-S6 external `visibility_multiplier` injection (smoke x0.3 / cover x0.6,
#     consistency-review C3). Reduces visibility, NEVER grants invisibility (R-03);
#     no new system is introduced.
#   - E05-S7 cone VFX: a cold-white (#9FB8C9) translucent ground light spot with a
#     <=2Hz pulse (V-02), brightness contrast >=3:1 (C-03), non-realtime light
#     (R-02, emissive quad not an OmniLight3D), brightness-coded not hue-coded
#     (C-04). The VFX mesh is only built when a live scene tree exists, so the
#     class stays headless-safe.
# The real-time 10Hz tick (ADR-002 / G-03) and the Sprint 0 visibility formula are
# unchanged.

# ★ Sprint 3 Batch A (E08-S7): these stay `const` — the STANDARD cone. A guard
# variant supplies its own geometry through a GuardVariantParams overlay (see
# set_variant_params below), it never rewrites these. Same FLAG-B discipline as
# patrol_ai.gd's frozen thresholds.
const HALF_ANGLE_DEG := 35.0
const RANGE := 14.0
const TICK_HZ := 10.0

# E05-S5: cone-edge warning band half-width (deg), inside the rim.
const EDGE_MARGIN_DEG := 8.0

# E05-S7: cone VFX constants. Headless tests assert these; a real shader/Tween
# reads them. (R-02 no realtime light / V-02 <=2Hz / C-03 >=3:1 / C-04 no hue.)
const CONE_VFX_PULSE_HZ := 2.0            # pulse frequency cap (V-02, gentle)
const CONE_VFX_COLOR := Color("#9FB8C9")  # cold white (C-04: not a danger hue)
const CONE_VFX_ALPHA_MIN := 0.06
const CONE_VFX_ALPHA_MAX := 0.30          # 0.30 / 0.06 = 5:1 >= 3:1 (C-03)

# E05-S6: external visibility multipliers (consistency-review C3).
const VIS_MULT_SMOKE := 0.3
const VIS_MULT_COVER := 0.6

var guard_id := 1
var observer_pos: Vector3 = Vector3.ZERO
var observer_forward: Vector3 = Vector3.FORWARD
var player_pos: Vector3 = Vector3.ZERO
var _accum := 0.0
var _last_ms := 0
var _edge_warned := false
var _light: LightModel = null
var _query: SpatialQueryWrapper = null
var _bus: EventBus = null
var _readability_boost := false
# E07-S4: optional smoke registry (a SmokeField). Deliberately typed RefCounted
# and called duck-typed: SmokeField already reads VIS_MULT_SMOKE off this class,
# so naming its type here would be a cyclic class_name reference. Null by
# default -> the cone behaves exactly as it did in Sprint 1.
var _smoke: RefCounted = null
# E08-S7 guard variant overlay. null == STANDARD, and every accessor below falls
# back to the frozen class constants in that case, so an un-configured cone is
# byte-for-byte the Sprint 1/2 cone. Injected by GuardBrain, which owns the
# variant (a cone never picks its own).
var _variant: GuardVariantParams = null

signal vision_stimulus(guard_id: int, target: Node, visibility: float)
signal vision_looming(guard_id: int)
signal cone_vfx_ready(mesh: MeshInstance3D)


func _ready() -> void:
	if _light == null:
		_light = LightModel.new()
	if _query == null:
		_query = SpatialQueryWrapper.new()
	# Phase-offset the tick so multiple guards don't all fire on the same frame.
	_accum = randf() * (1.0 / TICK_HZ)


func set_light_model(lm: LightModel) -> void:
	_light = lm


func set_event_bus(bus: EventBus) -> void:
	_bus = bus


# E07-S4: inject the smoke registry (duck-typed, same "orchestrate, don't
# repaint" contract as set_readability_boost). Passing null detaches it.
func set_smoke_field(field: RefCounted) -> void:
	_smoke = field


# The smoke multiplier at a world point: 1.0 (neutral) when no field is
# attached or the point is outside every live puff. Headless-safe.
func smoke_multiplier_at(target: Vector3) -> float:
	if _smoke == null:
		return 1.0
	if not _smoke.has_method("smoke_factor_at"):
		return 1.0
	return clampf(float(_smoke.smoke_factor_at(target)), 0.0, 1.0)


# --- E08-S7: guard variant overlay (range / half-angle / dark floor) --------
# Passing null detaches the overlay and restores the STANDARD constants.
func set_variant_params(p: GuardVariantParams) -> void:
	_variant = p


## Cone radius in metres for THIS guard. Hound = 11m (GDD §9.2).
func effective_range() -> float:
	return _variant.cone_range_m if _variant != null else RANGE


## Cone HALF angle in degrees for THIS guard. Hound = 30deg (GDD §9.2).
func effective_half_angle_deg() -> float:
	return _variant.cone_angle_deg if _variant != null else HALF_ANGLE_DEG


## Light sensitivity under this guard's dark floor (GDD §9.3).
##
## For a STANDARD guard — overlay absent, or present with the default 0.20 floor
## — this is arithmetically identical to LightModel.light_sensitivity(), so
## standard guards keep reading 0.0 in shadow. Only the sentinel's lower floor
## (0.05) changes the answer, which is the entire mechanic: shadow stops being a
## free safe zone in a sentinel's patrol.
func effective_light_sensitivity(level: float) -> float:
	if _variant != null:
		return _variant.light_sensitivity(level)
	if _light != null:
		return _light.light_sensitivity(level)
	return 1.0


func set_observer(pos: Vector3, forward: Vector3) -> void:
	observer_pos = pos
	observer_forward = forward


# E09-S3: readability orchestration (duck-typed; HudSlice only calls this and
# never touches our material). Boost pins the cone to its brightest legal step
# instead of pulsing, so FOCUS reads as "hold still and look".
func set_readability_boost(on: bool) -> void:
	_readability_boost = on


func cone_alpha_floor() -> float:
	return CONE_VFX_ALPHA_MAX if _readability_boost else CONE_VFX_ALPHA_MIN


# --- E05-S6: visibility with an optional external multiplier (smoke/cover). ---
# The multiplier only scales the light-sensitivity term; cone/LOS/range gates
# above it are untouched, so a target outside the cone or behind a wall stays 0,
# and cover/smoke lower visibility without ever making a seen target invisible
# (R-03).
#
# E07-S4 extends this with the thrown-smoke term:
#     vis = base_vis x cover_factor x smoke_factor
# `visibility_multiplier` stays the caller's term (cover, or a hand-passed smoke
# value from the Sprint 1 tests); the field term is looked up here so ANY caller
# -- the 10Hz tick, AI, tests -- gets the puff for free. Both terms are clamped
# to [0,1] and the product is clamped again, so smoke can only ever LOWER
# visibility and never grants invisibility (R-03).
func compute_visibility(target: Vector3, visibility_multiplier := 1.0) -> float:
	var to_t := target - observer_pos
	var dist := to_t.length()
	if dist > effective_range():
		return 0.0
	var dir := to_t.normalized()
	var ang := rad_to_deg(observer_forward.angle_to(dir))
	if ang > effective_half_angle_deg():
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
		# E08-S7: routed through the overlay so the sentinel's dark floor applies.
		# Still gated on `_light != null` so the "no light model" case keeps its
		# Sprint 0 answer of 1.0 exactly.
		sens = effective_light_sensitivity(lvl)
	var m := clampf(visibility_multiplier, 0.0, 1.0)
	var smoke := smoke_multiplier_at(target)
	return clampf(sens * m * smoke, 0.0, 1.0)


# --- E05-S5: is the target inside the 8deg rim warning band (range + angle)? ---
# Pure geometry (range + angle), independent of LOS/light so the tell reads as a
# spatial "about to be swept" warning. Returns false outside the cone rim.
func is_in_edge_band(target: Vector3) -> bool:
	var to_t := target - observer_pos
	var dist := to_t.length()
	if dist > effective_range():
		return false
	var dir := to_t.normalized()
	var ang := rad_to_deg(observer_forward.angle_to(dir))
	# E08-S7: the rim tell must track the ACTUAL cone. A hound whose cone is
	# 30deg but whose warning band still sat at 27..35deg would promise "about to
	# be swept" outside the cone and stay silent inside it — a tell that lies is
	# worse than no tell (C-05 readability).
	var half := effective_half_angle_deg()
	return ang >= (half - EDGE_MARGIN_DEG) and ang <= half


# One real-time tick: compute visibility + emit the edge tell. Extracted so
# headless tests can drive it directly without a SceneTree.
func _tick_once() -> void:
	# G2 (S1C-FIX-01): apply the cover multiplier (E04-S6 / consistency-review
	# C3). If the player stands in a cover spot (adjacent to an occluder, per
	# LightModel.get_cover), the guard's visibility of them is reduced. Cover
	# only lowers visibility; it never grants invisibility (R-03) -- the
	# multiplier is clamped to [0,1] inside compute_visibility, and the
	# cone/LOS/range gates above it are untouched.
	var vis_mult := 1.0
	if _light != null and _light.get_cover(player_pos):
		vis_mult = VIS_MULT_COVER
	var v := compute_visibility(player_pos, vis_mult)
	vision_stimulus.emit(guard_id, null, v)
	if _bus != null:
		_bus.vision_stimulus.emit(guard_id, null, v)
	var at_edge := is_in_edge_band(player_pos)
	if at_edge and not _edge_warned:
		# G3 (S1C-FIX-01): the rim "about to be swept" tell must NOT fire when the
		# player is occluded (behind a wall). A hidden target poses no threat
		# tell. No physics world (headless) -> treat as visible so the tell still
		# works in tests/editor (SpatialQueryWrapper returns true when no world).
		var visible := true
		if _query != null:
			visible = _query.has_line_of_sight(observer_pos, player_pos, 1)
		if visible:
			_edge_warned = true
			vision_looming.emit(guard_id)
			if _bus != null:
				_bus.vision_looming.emit(guard_id)
	elif not at_edge:
		# Re-arm: a new entry into the band will fire the tell again.
		_edge_warned = false


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
		_tick_once()


# --- E05-S7: cone VFX (ground light spot + <=2Hz pulse). Headless-safe: only
# builds the mesh when a live scene tree exists; otherwise a no-op. ---
func attach_cone_vfx() -> MeshInstance3D:
	if not _can_render():
		return null
	var spot := MeshInstance3D.new()
	spot.mesh = CylinderMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# R-02: NOT a realtime point light — an emissive quad (same pattern as
	# footfall_vfx). Brightness-coded, cool tone (C-04), not a danger hue (C-05).
	mat.emissive_enabled = true
	mat.emissive_color = CONE_VFX_COLOR
	mat.emissive_intensity = CONE_VFX_ALPHA_MIN
	var c := CONE_VFX_COLOR
	c.a = CONE_VFX_ALPHA_MIN
	mat.albedo_color = c
	spot.material_override = mat
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.scale = Vector3(1.0, 0.02, 1.0)   # flatten into a ground patch
	add_child(spot)
	cone_vfx_ready.emit(spot)
	_start_pulse(spot, mat)
	return spot


func _start_pulse(spot: MeshInstance3D, mat: StandardMaterial3D) -> void:
	var tween := create_tween().set_loops(-1)
	# T-04: slow the pulse with time_scale so it stays world-synced in FOCUS
	# (never speeds up, so V-02 <=2Hz always holds).
	tween.set_speed_scale(Engine.time_scale if Engine.time_scale > 0.0 else 1.0)
	var dur := 1.0 / CONE_VFX_PULSE_HZ        # seconds per full pulse cycle
	tween.tween_property(mat, "emissive_intensity", CONE_VFX_ALPHA_MAX, dur * 0.5)
	tween.tween_property(mat, "emissive_intensity", CONE_VFX_ALPHA_MIN, dur * 0.5)
	spot.tree_exiting.connect(tween.kill)


func _can_render() -> bool:
	return Engine.get_main_loop() != null and is_inside_tree()
