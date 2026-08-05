class_name GuardBrain
extends Node

# ASHEN STEP — Sprint 1 Batch C. E08 patrol-ai (L3) + the E06-S5 consumer side.
#
# Stories: E08-S1 (5-state FSM) · E08-S2 (continuous suspicion 25/60/10) ·
#          E08-S3 (10Hz throttled decisions, G-04) · E08-S4 (1.2s exposure grace
#          soft-fail) · E08-S5 (A* on transition only, G-05) · E08-S6 (four
#          signals + tier) · E08-S8 (non-color posture) · E06-S5 (sound-by-
#          distance suspicion, consumer side).
#
# Value-domain authority: EventBus.GuardState / EventBus.SusTier (L2 vocabulary,
# decision D6). This class deliberately does NOT declare its own GuardState enum
# — two copies of an enum always drift.
#
# Time base: every timer in here is REAL time (ADR-002/ADR-003 + T-02). _process's
# delta is scaled by Engine.time_scale, so it is never used directly; the wall
# clock is read from Time.get_ticks_msec(), exactly as step_commit.gd:138-147 and
# vision_cone.gd:154-160 already do.
#
# Headless-safe: no rendering, no scene-tree dependency. Tests drive tick_real()
# and _decide() directly.

const EventBus = preload("res://src/core/event_bus.gd")

# ── GDD-locked constants (patrol-ai §3 — values are frozen) ──────────────────
#
# ★ Sprint 3 Batch A (E08-S10 / FLAG-B) — these stay `const`. ★
# Guard variants are implemented as a PARAMETER OBJECT (GuardVariantParams),
# never by turning any of these into a runtime-mutable instance var. THR_SUSP /
# THR_ALERT / THR_RETURN / DECISION_HZ are the locked FSM contract and are not
# even representable in the overlay — GuardVariantParams has no field for them —
# so a variant cannot pollute them, by construction rather than by convention.
# KV / KS remain the STANDARD defaults, mirrored into
# GuardVariantParams.STD_KV / STD_KS and drift-locked by
# tests/unit/test_guard_variants.gd.
const THR_SUSP := 25.0        # pts     upward threshold -> SUSPICIOUS  [FROZEN]
const THR_ALERT := 60.0       # pts     upward threshold -> ALERT       [FROZEN]
const THR_RETURN := 10.0      # pts     downward threshold -> RETURN    [FROZEN]
const KV := 35.0              # pts/s   vision gain, STANDARD default (x vis x dt)
const KS := 15.0              # pts/event  sound gain, STANDARD default ([D5] NOT x dt)
const DECAY := 8.0            # pts/s   decay while unstimulated (x dt) [FROZEN]
const GRACE_RT := 1.2         # s (real) exposure grace                 [FROZEN]
const DECISION_HZ := 10.0     # Hz (real) G-04 ceiling                  [FROZEN]
const TICK_DT := 0.1          # s       = 1.0 / DECISION_HZ (derived)

# ── E06-S4 (Batch D) DECOY redirect [D12-A] ──────────────────────────────────
# Why a floor exists at all (N-9): a single decoy is MATHEMATICALLY unable to
# raise a calm guard to SUSPICIOUS on the pure additive path —
#   KS(15.0) x falloff_max(1.0) = 15.0  <  THR_SUSP(25.0)
# so the core verb would fail silently while every test stayed green. D12-A
# resolves this with a floor (maxf), NOT a new gain constant: no KS_DECOY, no
# change to KS, no change to the [0,1] intensity domain, no new scale.
const DECOY_REDIRECT_COOLDOWN_RT := 3.0   # s (real clock) anti-spam, PER GUARD.
                                          # The ONLY new free value in Batch D
                                          # (principal-confirmed, D12-A).

# ── D10 constants (adopted verbatim by the showrunner) ───────────────────────
const LOST_TARGET_RT := 0.5      # s (real) ALERT->SEARCH "lost the target" test
const RETURN_SETTLE_RT := 1.0    # s (real) RETURN->CALM minimal Sprint 1 settle
const STIM_EPS := 0.001          # -       stimulus float test (no eternal grudge)
const SUS_EMIT_EPS := 0.5        # pts     suspicion_changed throttle
const MAX_CATCHUP_TICKS := 3     # -       fixed-step catch-up cap (no death spiral)
const XFORM_POS_EPS := 0.5       # m       guard_transform_dirty position epsilon
const XFORM_YAW_EPS_DEG := 5.0   # deg     guard_transform_dirty yaw epsilon

# Fixed-step timers accumulate dt as binary floats: ten additions of 0.1 sum to
# 0.9999999999999999, so a bare `>= 1.0` would silently cost one extra tick and
# make LOST_TARGET_RT / RETURN_SETTLE_RT / GRACE_RT land a tick late. Compare
# with an epsilon far below half a tick (1e-6 << 0.05) so the threshold fires on
# the intended tick without ever firing early.
const TIMER_EPS := 1e-6

# E08-S8 — art-bible §4.1 posture per state, 1:1 with EventBus.GuardState.
# ★ Pure enum/String: NO color field anywhere, so the read stays 100% legible
# under all three types of color blindness (C-05 / C-07).
const POSTURE := {
	EventBus.GuardState.CALM: "LANTERN_LOW",         # lantern low, patrolling
	EventBus.GuardState.SUSPICIOUS: "LANTERN_RAISED",# lantern up, turning
	EventBus.GuardState.ALERT: "BLADE_DRAWN",        # blade drawn, lantern high
	EventBus.GuardState.SEARCH: "LANTERN_SWEEP",     # lantern sweeping side to side
	EventBus.GuardState.RETURN: "RETURNING",         # heading home
}

# ── E08-S7/S9/S10 (Sprint 3 · Batch A) variant overlay ───────────────────────
# The ONE piece of variant state on this class. Defaults to the STANDARD params,
# so an un-configured GuardBrain behaves EXACTLY as it did in Sprint 1/2 (the
# standard values are literal mirrors of the constants above, drift-locked by
# test_guard_variants.gd). Never null — see set_variant_params.
var _params: GuardVariantParams = GuardVariantParams.standard()

# ── State (E08-S1) ───────────────────────────────────────────────────────────
var guard_id: int = 1
var fsm: int = EventBus.GuardState.CALM
var suspicion: float = 0.0                    # [0,100]
var last_known: Vector3 = Vector3.ZERO
var exposure_timer: float = 0.0               # real time
var decision_count: int = 0                   # G-04 assertion counter

var _lost_timer: float = 0.0                  # ALERT: accumulated "no vision"
var _return_timer: float = 0.0                # RETURN: accumulated settle time

# ── Tick buffers (E08-S2/S3) ─────────────────────────────────────────────────
var _accum: float = 0.0
var _last_ms: int = 0
var _pending_vision: float = 0.0
var _pending_sound_max: float = 0.0
var _pending_sound_count: int = 0
var _pending_sound_origin: Vector3 = Vector3.ZERO
var _pending_target: Node = null
# E06-S4: set by _on_sound_emitted (intake), consumed in _decide (10Hz). The
# split is deliberate — see the placement note in _decide.
var _pending_decoy: bool = false
var _last_decoy_rt: float = -999.0            # s (real clock); sentinel = never

# ── Emission throttles (E08-S6) ──────────────────────────────────────────────
var _last_emitted_sus: float = -999.0
var _last_emitted_tier: int = -1
var _last_dirty_pos: Vector3 = Vector3.ZERO
var _last_dirty_yaw: float = 0.0

# ── Pose, externally driven in Sprint 1 (no navigation movement yet) ─────────
var _pos: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
# last_known priority (1) needs the target's REAL position. VisionCone currently
# emits a null target node (E05), so Sprint 1 accepts an explicit position from
# the level/test. Sprint 2 replaces this with the real player node.
var target_pos: Vector3 = Vector3.ZERO
var _has_target_pos: bool = false

# ── Collaborators / D9 seams ─────────────────────────────────────────────────
var _bus: EventBus = null
var _sound: SoundPropagator = null            # ★ landmine 2 (W1)
var _cone: VisionCone = null                  # W2: this guard's own cone
# D9 seam (1): Sprint 2 wires SaveManager.restore_checkpoint here (E01-S5).
var _checkpoint_sink: Callable = Callable()
# D9 seam (2): Sprint 2 wires NavServer.request_path here (E01-S8).
# Contract: request_path(from: Vector3, to: Vector3) -> PackedVector3Array
var _path_provider: Callable = Callable()
var _cached_path: PackedVector3Array = PackedVector3Array()
var _path_dirty: bool = true


func _ready() -> void:
	# ★ Landmine 2 (W1): register on the FIRST frame, never "on first move".
	# If the guard is only pushed to SoundPropagator once it moves, a stationary
	# guard is invisible to emit()'s distance filter and E06-S5 dies silently.
	_register_with_sound()
	set_checkpoint_sink(SaveManager.restore_checkpoint)  # D9 seam (1) CLOSED — SAV-S3, FLAG-A(a) zero-arg


# --- Dependency injection (mirrors vision_cone.gd / sound_propagation.gd) ----
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_bind_bus()


func _bind_bus() -> void:
	if _bus == null:
		return
	# Idempotent: _ready and set_event_bus may both run, in either order.
	if not _bus.vision_stimulus.is_connected(_on_vision_stimulus):
		_bus.vision_stimulus.connect(_on_vision_stimulus)
	if not _bus.sound_emitted.is_connected(_on_sound_emitted):
		_bus.sound_emitted.connect(_on_sound_emitted)


# ★ Landmine 2 (W1) fix entry point. SoundPropagator exposes register_guard /
# update_guard / remove_guard (ready since Batch B) but NOTHING called them, so
# _guard_positions stayed empty forever -> target_guard_ids was always empty ->
# E06-S5 distance attenuation never ran, while the unit tests stayed green.
# This class is the caller that closes that loop.
func set_sound_system(sound: SoundPropagator) -> void:
	_sound = sound
	_register_with_sound()


func _register_with_sound() -> void:
	if _sound != null and is_instance_valid(_sound):
		_sound.register_guard(guard_id, _pos)


# --- E08-S7 · variant overlay injection ------------------------------------
# Applied at instantiation (GuardSpawner), never mid-life: GDD §9.1 makes the
# variant a level-authoring decision, "运行时不可切换". Passing null restores the
# STANDARD params rather than leaving a null to crash the 10Hz tick.
func set_variant_params(params: GuardVariantParams) -> void:
	_params = params if params != null else GuardVariantParams.standard()
	# W2: a cone attached BEFORE the params must still receive them, otherwise
	# the hound's 11m/30deg cone would depend on wiring order and silently stay
	# 14m/35deg half the time.
	_apply_params_to_cone()


func get_variant_params() -> GuardVariantParams:
	return _params


func get_variant() -> int:
	return _params.variant


# W2: one VisionCone instance per guard, kept in sync with this brain's pose.
func set_vision_cone(cone: VisionCone) -> void:
	_cone = cone
	if _cone != null:
		_cone.guard_id = guard_id
		_cone.set_observer(_pos, _forward())
		_apply_params_to_cone()


# The single seam where ③ (vision) learns about the variant. Kept separate from
# set_vision_cone so BOTH wiring orders (cone-then-params, params-then-cone)
# converge on the same state.
func _apply_params_to_cone() -> void:
	if _cone != null and is_instance_valid(_cone):
		_cone.set_variant_params(_params)


# D9 seam (1). Default Callable() is a safe no-op.
func set_checkpoint_sink(sink: Callable) -> void:
	_checkpoint_sink = sink


# D9 seam (2). Default Callable() is a safe no-op.
func set_path_provider(provider: Callable) -> void:
	_path_provider = provider


# Sprint 1: the guard pose is driven by the level script / tests. Sprint 2 will
# drive it from real navigation movement; nothing else in this class changes.
func set_transform_state(pos: Vector3, yaw_rad: float) -> void:
	_pos = pos
	_yaw = yaw_rad


func set_target_position(p: Vector3) -> void:
	target_pos = p
	_has_target_pos = true


# --- Read-only accessors ----------------------------------------------------
func get_state() -> int:
	return fsm


func get_posture() -> String:
	return POSTURE.get(fsm, "LANTERN_LOW")


func get_cached_path() -> PackedVector3Array:
	return _cached_path


# =============================================================================
# E08-S3 — real-time clock -> fixed 10Hz decision steps (G-04)
# =============================================================================
func _process(_scaled: float) -> void:
	# _scaled is multiplied by Engine.time_scale; the AI clock must not be. Read
	# the wall clock instead (identical to step_commit.gd / vision_cone.gd).
	var now := Time.get_ticks_msec()
	var rd := 0.0
	if _last_ms > 0:
		rd = float(now - _last_ms) / 1000.0
	_last_ms = now
	if rd > 0.0:
		tick_real(rd)


func tick_real(delta_real: float) -> void:
	_accum += delta_real
	var n := 0
	while _accum >= TICK_DT and n < MAX_CATCHUP_TICKS:
		_decide(TICK_DT)
		_accum -= TICK_DT
		n += 1
	if n >= MAX_CATCHUP_TICKS:
		# E5: after a long hitch, DROP the backlog. Never try to compensate —
		# that turns one stall into a decision storm.
		_accum = 0.0


# =============================================================================
# E08-S2 — one decision step. ⚠ The order below is contractual (spec §3.2).
# =============================================================================
func _decide(dt: float) -> void:
	decision_count += 1
	var vis: float = _pending_vision                  # [0,1], continuous
	var snd: float = _pending_sound_max               # [0,1], this tick's MAX (E2)
	var had_sound: bool = _pending_sound_count > 0

	# (2) stimulus test — E3: STIM_EPS, never "> 0.0", or float noise makes the
	# guard hold a grudge forever.
	var stimulus: bool = (vis > STIM_EPS) or had_sound

	# (3) accumulate — [D5] vision is a RATE, sound is an IMPULSE.
	# E08-S7: the gains come from the variant overlay, NOT from the class
	# constants. For a STANDARD guard _params.kv/_params.ks ARE KV/KS (mirrored
	# and drift-locked), so this line is behaviour-identical to Sprint 1; for a
	# hound it is 15/30. Note what is NOT parameterised: dt, the decay, and every
	# threshold below. That is E08-S10's contract (FLAG-B).
	var d: float = _params.kv * vis * dt
	if had_sound:
		d += _params.ks * snd                         # ★ no dt: unit is pts/event

	# (4) decay — E4: mutually exclusive with accumulation within a tick.
	if not stimulus:
		d -= DECAY * dt

	# (5) clamp both ends — E1: the excess above 100 is TRUNCATED, never banked.
	suspicion = clampf(suspicion + d, 0.0, 100.0)

	# (6)..(10)
	_update_last_known(vis)
	# (6b) E06-S4 [D12-A] DECOY suspicion floor. Ordering is contractual:
	#   AFTER _update_last_known  — so the §3.12 priority (visible target > sound
	#     origin > keep) settles FIRST. A decoy raises alarm but must never
	#     override line of sight [M-3]; that keeps DECOY from being a universal
	#     escape key.
	#   BEFORE _step_fsm          — so the raised value is what the thresholds
	#     actually see this same tick, instead of one tick late.
	# maxf, not assignment: an already-ALERT guard must never be talked DOWN to
	# 25 by a thrown stone. DECOY guarantees "at least investigating", nothing more.
	if _pending_decoy:
		var now_rt: float = Time.get_ticks_msec() / 1000.0
		if (now_rt - _last_decoy_rt) >= DECOY_REDIRECT_COOLDOWN_RT:
			suspicion = maxf(suspicion, THR_SUSP)
			_last_decoy_rt = now_rt
		# Cleared unconditionally, including when suppressed by the cooldown —
		# a surviving flag would re-fire the instant the window expires.
		_pending_decoy = false
	_step_exposure(vis, dt)
	_step_fsm(vis, dt)
	_ensure_path()
	_maybe_mark_transform_dirty()
	_emit_if_changed()

	# (11) clear the per-tick impulse buffers. _pending_vision is NOT cleared:
	# vision is a continuous quantity that E05 overwrites every tick.
	_pending_sound_max = 0.0
	_pending_sound_count = 0


# --- Stimulus intake --------------------------------------------------------
func _on_vision_stimulus(from_guard: int, target: Node, visibility: float) -> void:
	# The bus is a broadcast: ignore other guards' cones.
	if from_guard != guard_id:
		return
	# Overwrite, don't sum: vision is a continuous level, not an event count.
	_pending_vision = visibility
	_pending_target = target


# E06-S5 consumer side. The producer (SoundPropagator.suspicion_from_distance)
# shipped in Batch B and is NOT touched here.
func _on_sound_emitted(payload: Dictionary) -> void:
	# Only events whose grid+radius filter already named this guard (E06-S1).
	var targets: Array = payload.get("target_guard_ids", [])
	var addressed: bool = targets.has(guard_id)
	var mult: float = _params.perception_radius_mult
	# ★ E08-S7 hound hearing reach (GDD §9.2 sound_detect_radius_mult = 1.6).
	# `sound_emitted` is a BROADCAST — every brain sees every event and filters
	# itself — so a guard whose hearing reaches further than the event radius can
	# legitimately accept an event that E06's radius filter did not address to
	# it. This is the only way the x1.6 can actually extend RANGE: E06's
	# target_guard_ids is computed from the emitter's radius alone and knows
	# nothing about per-guard hearing, so filtering on it first would cap the
	# hound at the standard radius and reduce x1.6 to a pure loudness buff that
	# no test could tell apart from "the multiplier does nothing".
	# mult <= 1.0 (every STANDARD guard) keeps the original early-out verbatim.
	if not addressed and mult <= 1.0:
		return
	if _sound == null or not is_instance_valid(_sound):
		return
	var origin: Vector3 = payload.get("origin", Vector3.ZERO)
	var radius: float = float(payload.get("radius", 0.0))
	var intensity: float = float(payload.get("intensity", 0.0))
	# 3D euclidean distance — MUST match sound_propagation.gd:126's in-radius
	# test, otherwise "inside the circle" and "how loud" disagree.
	var dist: float = origin.distance_to(_pos)
	# The multiplier is applied to the RADIUS, not to the resulting falloff:
	# E06's formula is intensity * (1 - dist/radius), so scaling the radius both
	# extends the reach AND raises the loudness at any fixed distance, which is
	# exactly "hearing is sharper" rather than "sounds are louder everywhere".
	# Clamped >= 1.0 so a malformed overlay can never DEAFEN a guard below the
	# E06 contract it was already addressed under.
	var eff_radius: float = radius * maxf(mult, 1.0)
	var falloff: float = _sound.suspicion_from_distance(intensity, dist, eff_radius)
	if falloff <= 0.0:
		return                                        # dist >= radius, or radius <= 0
	# E2: take the MAX, never the sum — otherwise many quiet steps out-score one
	# loud one and the gait economy inverts.
	_pending_sound_max = maxf(_pending_sound_max, falloff)
	_pending_sound_count += 1
	_pending_sound_origin = origin
	# E06-S4 [D12-A]: MARK ONLY. The suspicion floor itself is applied in
	# _decide(), never here — this handler runs at sound-event frequency, which
	# is unbounded, and moving the FSM from here would breach G-04 (<=10Hz) while
	# bypassing decision_count entirely. Asserted by
	# test_patrol_ai.gd::test_fsm_tick_le_10hz (H27).
	if payload.get("source", "") == SoundPropagator.SOURCE_DECOY:
		_pending_decoy = true


# §3.12 write priority: (1) real target position when seen, (2) sound origin,
# (3) keep the previous value — never clear it on a quiet tick.
func _update_last_known(vis: float) -> void:
	if vis > STIM_EPS:
		if _pending_target is Node3D:
			last_known = (_pending_target as Node3D).global_position
		elif _has_target_pos:
			last_known = target_pos
	elif _pending_sound_count > 0:
		last_known = _pending_sound_origin


# =============================================================================
# E08-S4 — 1.2s exposure grace -> soft fail
# =============================================================================
func _step_exposure(vis: float, dt: float) -> void:
	if fsm == EventBus.GuardState.ALERT and vis > STIM_EPS:
		exposure_timer += dt
		if exposure_timer >= GRACE_RT - TIMER_EPS:
			_on_soft_fail(_pending_target)
	else:
		# Breaking line of sight inside the grace window rescues the player.
		exposure_timer = 0.0


func _on_soft_fail(target: Node) -> void:
	suspicion = 0.0
	exposure_timer = 0.0
	last_known = Vector3.ZERO
	_set_fsm(EventBus.GuardState.RETURN)              # forced path (§3.1)
	if _bus != null:
		_bus.exposure_detected.emit(guard_id, target)
	if _checkpoint_sink.is_valid():
		# Sprint 2: SaveManager.restore_checkpoint(). Sprint 1 injects a no-op /
		# counting stub — L3 stays decoupled from an L2 service that does not
		# exist yet (architecture.md §2 one-way dependency). This is correct
		# layering, not a workaround.
		_checkpoint_sink.call()


# =============================================================================
# E08-S1 — the five-state FSM
# =============================================================================
# Anti-thrash discipline (structural, so no hysteresis constant is needed):
#  1. There is NO step-by-step descent. Any downward move happens once, into
#     RETURN, and only when S < THR_RETURN. 25/60 are UPWARD-only thresholds,
#     which structurally eliminates threshold chatter.
#  2. guard_fsm_changed fires only when old != new.
#  3. Level skipping is allowed: 5 -> 65 in one tick goes CALM -> ALERT in a
#     single hop and emits ONE signal (edge E9). Note this is why the CALM arm
#     tests THR_ALERT first: the spec's transition table lists CALM->SUSPICIOUS,
#     but discipline 3 / edge E9 explicitly require the single-hop jump, and a
#     table-order implementation would synthesise an intermediate state and emit
#     twice. Discipline 3 wins; the table still holds for 25 <= S < 60.
func _step_fsm(vis: float, dt: float) -> void:
	match fsm:
		EventBus.GuardState.CALM:
			if suspicion >= THR_ALERT:
				_set_fsm(EventBus.GuardState.ALERT)     # discipline 3 / edge E9
			elif suspicion >= THR_SUSP:
				_set_fsm(EventBus.GuardState.SUSPICIOUS)
		EventBus.GuardState.SUSPICIOUS:
			if suspicion >= THR_ALERT:
				_set_fsm(EventBus.GuardState.ALERT)
			elif suspicion < THR_RETURN:
				_set_fsm(EventBus.GuardState.RETURN)
		EventBus.GuardState.ALERT:
			if vis <= STIM_EPS:
				_lost_timer += dt
				if _lost_timer >= LOST_TARGET_RT - TIMER_EPS:
					_set_fsm(EventBus.GuardState.SEARCH)
			else:
				_lost_timer = 0.0
		EventBus.GuardState.SEARCH:
			if vis > STIM_EPS:
				_set_fsm(EventBus.GuardState.ALERT)
			elif suspicion < THR_RETURN:
				# Natural timeout via decay (60 -> 10 takes 6.25s). No separate
				# SEARCH_TIMEOUT constant is introduced.
				_set_fsm(EventBus.GuardState.RETURN)
		EventBus.GuardState.RETURN:
			if suspicion >= THR_SUSP:
				_set_fsm(EventBus.GuardState.SUSPICIOUS)  # re-alarmed en route
			else:
				_return_timer += dt
				if _return_timer >= RETURN_SETTLE_RT - TIMER_EPS:
					_set_fsm(EventBus.GuardState.CALM)


# The ONE place fsm is written. Owns path invalidation and the D6 signal.
func _set_fsm(next: int) -> void:
	if next == fsm:
		return                                        # discipline 2
	var prev: int = fsm
	fsm = next
	_lost_timer = 0.0
	_return_timer = 0.0
	if next == EventBus.GuardState.ALERT or next == EventBus.GuardState.SEARCH:
		_path_dirty = true                            # G-05, §3.5
	if _bus != null:
		_bus.guard_fsm_changed.emit(guard_id, prev, next)   # [D6] int enum


# =============================================================================
# E08-S5 — A* only on state transitions, then cached (G-05)
# =============================================================================
func _ensure_path() -> void:
	if not _path_dirty:
		return                                        # ★ cache hit: not per-frame
	if _path_provider.is_valid():
		_cached_path = _path_provider.call(_pos, last_known)
	_path_dirty = false


# =============================================================================
# E08-S6 — the four outbound signals
# =============================================================================
# SusTier is the HUD band; GuardState is the behaviour state. SEARCH is the one
# case where the FSM overrides the value band (system-breakdown §2.3).
# RETURN needs no special case: it is only entered at S < 10, so the value band
# already resolves to CALM.
func compute_tier(s: float, state: int) -> int:
	if state == EventBus.GuardState.SEARCH:
		return EventBus.SusTier.SEARCH
	if s >= THR_ALERT:
		return EventBus.SusTier.ALERT
	if s >= THR_SUSP:
		return EventBus.SusTier.SUSPICIOUS
	return EventBus.SusTier.CALM


func _emit_if_changed() -> void:
	var tier: int = compute_tier(suspicion, fsm)
	var moved_enough := absf(suspicion - _last_emitted_sus) >= SUS_EMIT_EPS
	if moved_enough or tier != _last_emitted_tier:
		_last_emitted_sus = suspicion
		_last_emitted_tier = tier
		if _bus != null:
			_bus.suspicion_changed.emit(guard_id, suspicion, tier)


# ★★★ Landmine 2 (W1 + W3): one place closes BOTH "E05 recomputes vision" and
# "E06 back-fills the guard position for distance filtering". ★★★
# This runs inside the 10Hz decision tick, so G-03 is satisfied without a second
# timer.
func _maybe_mark_transform_dirty() -> void:
	var moved := _pos.distance_to(_last_dirty_pos) >= XFORM_POS_EPS
	var turned := absf(rad_to_deg(angle_difference(_yaw, _last_dirty_yaw))) >= XFORM_YAW_EPS_DEG
	if not (moved or turned):
		return
	_last_dirty_pos = _pos
	_last_dirty_yaw = _yaw
	if _bus != null:
		_bus.guard_transform_dirty.emit(guard_id)     # W3 -> E05 vision recompute
	if _sound != null and is_instance_valid(_sound):
		_sound.update_guard(guard_id, _pos)           # ★ W1 -> E06 distance filter
	if _cone != null and is_instance_valid(_cone):
		_cone.set_observer(_pos, _forward())          # W2 -> this guard's own cone


# yaw 0 faces Vector3.FORWARD (0,0,-1), matching VisionCone's default observer
# forward; +yaw turns toward +X.
func _forward() -> Vector3:
	return Vector3(sin(_yaw), 0.0, -cos(_yaw))
