class_name TrapEntity
extends InteractableEntity

# ASHEN STEP — Sprint 2, Batch B. E07-S3: the mechanism (world object).
#
# interactables.md §9.3 / sprint2-design-scope.md §2.1 lock the internal FSM:
#
#   IDLE --arm()--> ARMED --trigger()--> TRIGGERED --> RECOVER --> ARMED   (charges > 0)
#                                                              \-> SPENT   (charges == 0)
#
# ★ The FSM is INTERNAL. It is NOT a new mechanism family and it emits NO new
#   vocabulary: pulling a lever emits interactable_triggered(obj_id, TRAP,
#   payload) (event_bus.gd:82) and then ROUTES to the verbs E04/E05/E06 already
#   own:
#     SOUND -> SoundPropagator.emit(source=TRAP)  -> sound_emitted + G-02 ring
#     LIGHT -> LightModel.toggle_light            -> light_state_changed + R-05
#     BLOCK -> EventBus.cover_state_changed(cell) -> E05 O(cell) recompute
#   A lever, a rune and a winch are three skins over these three verbs — that
#   is the whole point of "不新增机制族".
#
# ★ RECOVER resolves IMMEDIATELY in Sprint 2 (no cooldown dwell). The GDD arrow
#   chain specifies the STATES, not a duration, and inventing a timer would put
#   a wall-clock dependency into a headless unit test for no acceptance value.
#   A timed dwell is a one-line change at _resolve_recover() when design signs
#   a number.

const SoundPropagatorScript = preload("res://src/game/sound_propagation.gd")
const SpatialHashGrid3DScript = preload("res://src/core/spatial_hash_grid.gd")

enum State { IDLE, ARMED, TRIGGERED, RECOVER, SPENT }

const VERB_SOUND := "SOUND"
const VERB_LIGHT := "LIGHT"
const VERB_BLOCK := "BLOCK"
const ALL_VERBS := [VERB_SOUND, VERB_LIGHT, VERB_BLOCK]

# Loudness of a sprung mechanism, normalised to [0,1] like every other E06
# source (sound_propagation.gd:42 forbids exceeding 1.0).
const SOUND_INTENSITY := 1.0

var state: int = State.IDLE
# Which of the three existing verbs this skin drives. A lever might be
# ["SOUND","BLOCK"], a rune ["LIGHT"], a winch all three.
var verbs: Array[String] = [VERB_SOUND]
# LIGHT verb target (E04 light id). Defaults to entity_id.
var light_id: int = -1

var _sound: SoundPropagator = null
var _model: LightModel = null
var _light_state: int = EventBus.LightState.LIT
var _block_cell: Vector3i = Vector3i.ZERO
var _block_cell_set: bool = false
var _history: Array[int] = [State.IDLE]


func _init() -> void:
	type = EventBus.InteractableType.TRAP


# --- wiring ------------------------------------------------------------------
func set_sound_propagator(propagator: SoundPropagator) -> void:
	_sound = propagator


func set_light_model(model: LightModel) -> void:
	_model = model
	if _model != null:
		_model.register_light(effective_light_id(), position)
		_light_state = _model.get_light_state(effective_light_id())


func set_verbs(list: Array) -> void:
	var clean: Array[String] = []
	for v in list:
		var verb := str(v).to_upper()
		if not ALL_VERBS.has(verb):
			push_warning("TrapEntity: unknown verb `%s` ignored (legal: %s)"
				% [verb, str(ALL_VERBS)])
			continue
		if not clean.has(verb):
			clean.append(verb)
	verbs = clean


func set_block_cell(cell: Vector3i) -> void:
	_block_cell = cell
	_block_cell_set = true


func effective_light_id() -> int:
	return light_id if light_id >= 0 else entity_id


## Grid cell this mechanism blocks/unblocks. Mirrors light_model.gd:169 — the
## cell size is locked to SpatialHashGrid3D.CELL by ADR-002.
static func cell_of(pos: Vector3) -> Vector3i:
	var c: float = SpatialHashGrid3DScript.CELL
	return Vector3i(int(floor(pos.x / c)), int(floor(pos.y / c)), int(floor(pos.z / c)))


static func nominal_sound_radius() -> float:
	# Reuses the E06 nominal ring radius rather than minting a second magic
	# number for the G-02 budget conversation. Design may sign a dedicated TRAP
	# figure later; until then one radius is one radius.
	return SoundPropagatorScript.DECOY_RADIUS


# --- FSM ---------------------------------------------------------------------
func state_history() -> Array[int]:
	return _history.duplicate()


func is_spent() -> bool:
	return state == State.SPENT


## IDLE/RECOVER -> ARMED. Returns false when the mechanism is exhausted (it
## lands in SPENT instead) or is mid-trigger.
func arm() -> bool:
	if state == State.ARMED:
		return true
	if state == State.SPENT or state == State.TRIGGERED:
		return false
	if not can_trigger():
		_set_state(State.SPENT)
		return false
	_set_state(State.ARMED)
	return true


func _fire(ctx: Dictionary) -> Dictionary:
	# A trap that was never armed does nothing and spends nothing. This is the
	# gate that makes test_trap_fsm_transitions falsifiable — without it every
	# state would be a legal trigger and the FSM would be decoration.
	if state != State.ARMED:
		return {}
	_set_state(State.TRIGGERED)
	var routed := _route(ctx)
	return {
		"routed": routed,
		"verbs": verbs.duplicate(),
	}


func _on_consumed(payload: Dictionary) -> void:
	_set_state(State.RECOVER)
	_resolve_recover()
	payload["state"] = state
	payload["fsm_path"] = state_history()


func _resolve_recover() -> void:
	# interactables.md §9.3: RECOVER branches on the POST-debit balance.
	if can_trigger():
		_set_state(State.ARMED)
	else:
		_set_state(State.SPENT)


func _set_state(next: int) -> void:
	if state == next:
		return
	state = next
	_history.append(next)


# --- routing (E04 / E05 / E06) ------------------------------------------------
func _route(ctx: Dictionary) -> Array[String]:
	var done: Array[String] = []
	for verb in verbs:
		var ok := false
		match verb:
			VERB_SOUND:
				ok = _route_sound(ctx)
			VERB_LIGHT:
				ok = _route_light()
			VERB_BLOCK:
				ok = _route_block()
			_:
				ok = false
		if ok:
			done.append(verb)
	return done


func _route_sound(ctx: Dictionary) -> bool:
	var radius: float = float(ctx.get("radius", nominal_sound_radius()))
	if radius <= 0.0:
		radius = nominal_sound_radius()
	var payload := {
		"origin": position,
		"radius": radius,
		"intensity": SOUND_INTENSITY,
		"source": SoundPropagatorScript.SOURCE_TRAP,
	}
	if _sound != null:
		# E06 owns the ring FIFO (G-02) AND the sound_emitted broadcast, so we
		# hand it the payload and never emit the signal ourselves — doing both
		# would double-count the ring against the budget.
		_sound.emit(payload)
		return true
	if _bus != null:
		# No propagator wired (headless fixture): the stimulus still reaches E08
		# so suspicion is testable. No ring is claimed, so no budget is spent.
		_bus.sound_emitted.emit(payload)
		return true
	return false


func _route_light() -> bool:
	var before := _light_state
	if _model != null:
		before = _model.get_light_state(effective_light_id())
		_model.toggle_light(effective_light_id())
		_light_state = _model.get_light_state(effective_light_id())
	else:
		_light_state = LightToggleEntity.flip(before)
	if _bus == null:
		return _model != null
	_bus.light_state_changed.emit(effective_light_id(), _light_state)
	return true


func _route_block() -> bool:
	var cell := _block_cell if _block_cell_set else cell_of(position)
	if _model != null:
		# E05/G-03: only the affected cell is recomputed, never the whole grid.
		_model.mark_cell_dirty(cell)
	if _bus == null:
		return _model != null
	_bus.cover_state_changed.emit(cell)
	return true


# --- budget accounting (E07-S8) ----------------------------------------------
func emits_sound_ring() -> bool:
	return verbs.has(VERB_SOUND)


func occupies_realtime_light() -> bool:
	# A mechanism never OWNS a light; the fixture it toggles is E04's and is
	# already counted by that fixture's own LightToggleEntity row.
	return false
