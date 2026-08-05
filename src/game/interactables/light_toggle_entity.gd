class_name LightToggleEntity
extends InteractableEntity

# ASHEN STEP — Sprint 2, Batch B. E07-S2: the douse/relight fixture (world object).
#
# interactables.md §2 / sprint2-stories E07-S2:
#   Aiming at a candle stand (entity-inventory #12) or a sconce (#13) and
#   pressing interact emits light_state_changed(light_id, EXTINGUISHED|LIT),
#   which E04 consumes to swap the OmniLight + emissive + the R-05 fog ramp, and
#   E05 consumes to recompute the affected cell (G-03, O(cell)).
#
# ★ The signature (light_id: int, state: LightState) was FROZEN by E01-S9 in
#   Sprint 1 (event_bus.gd:37) and must not change.
#
# ★ Who emits what — this is the part that is easy to get wrong:
#   LightModel owns the authoritative per-light STATE and emits its own LOCAL
#   signal (light_model.gd:37/119) plus the dirty-cell recompute and the
#   extinction ramp. Nothing in the repo bridges that local signal onto the bus,
#   so this entity is the FIRST production emitter of the BUS signal. We
#   therefore: (1) let LightModel flip the state so the E04 side effects run
#   exactly once, then (2) mirror the resulting state onto the bus. We never
#   compute the next state ourselves when a model is present — two authorities
#   for one boolean is how a light ends up visually lit and logically doused.

# The E04 light this fixture drives. Defaults to entity_id (a level that gives
# the fixture and the light the same id needs no extra wiring).
var light_id: int = -1

# Optional E04 owner. Null is legal (headless fixture): the entity then keeps
# its own state so the bus signal is still correct and testable.
var _model: LightModel = null
var _state: int = EventBus.LightState.LIT


func _init() -> void:
	type = EventBus.InteractableType.LIGHT_TOGGLE


## The ONE place the LIT <-> EXTINGUISHED rule lives. TrapEntity's LIGHT verb
## calls this too, so the two routes can never disagree about what "toggle"
## means (light_model.gd:122 implements the same rule on the E04 side).
static func flip(state: int) -> int:
	if state == EventBus.LightState.LIT:
		return EventBus.LightState.EXTINGUISHED
	return EventBus.LightState.LIT


func set_light_model(model: LightModel) -> void:
	_model = model
	if _model != null:
		_model.register_light(effective_light_id(), position)
		_state = _model.get_light_state(effective_light_id())


func effective_light_id() -> int:
	return light_id if light_id >= 0 else entity_id


func get_state() -> int:
	if _model != null:
		return _model.get_light_state(effective_light_id())
	return _state


func is_lit() -> bool:
	return get_state() == EventBus.LightState.LIT


## Interact. Returns false when the fixture is out of charges (a spent candle
## cannot be relit this sprint — resupply is config-only, E07-S5).
func toggle() -> bool:
	return trigger({})


func _fire(_ctx: Dictionary) -> Dictionary:
	var before := get_state()
	var after := before
	if _model != null:
		# E04 owns the flip: state + O(cell) recompute + R-05 extinction ramp.
		_model.toggle_light(effective_light_id())
		after = _model.get_light_state(effective_light_id())
	else:
		after = flip(before)
		_state = after
	if _bus != null:
		_bus.light_state_changed.emit(effective_light_id(), after)
	return {
		"light_id": effective_light_id(),
		"state": after,
		"was": before,
	}


# E07-S8 / R-02: a LIT fixture holds one realtime OmniLight; dousing it RELEASES
# that slot back to the <=12 MVP / <=32 Tier2 budget. The registry sums this
# across live instances for @ci:interactable-instance-cap.
func occupies_realtime_light() -> bool:
	return is_lit()
