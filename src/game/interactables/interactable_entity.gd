class_name InteractableEntity
extends RefCounted

# ASHEN STEP — Sprint 2, Batch B. E07 interactable entity BASE.
#
# ★ RefCounted, deliberately NOT Node (E07-S7). An interactable is a small
#   logical object with a charge ledger and one world verb; making it a Node
#   buys nothing and costs the one thing the story is actually about — a Node
#   dropped without queue_free() becomes a Godot ORPHAN, and the orphan scan is
#   the exit hook for this story. RefCounted instances are reference-freed and
#   can never show up in that count. (Same reasoning as the BoostStub note in
#   tests/unit/test_hud_slice.gd:30.)
#
# ★ ZERO new event vocabulary (sprint2-stories §Batch B, locked). Every subclass
#   speaks ONLY signals already frozen in src/core/event_bus.gd:
#     DECOY         -> decoy_landed(pos, surface, radius)          -> E06
#     LIGHT_TOGGLE  -> light_state_changed(light_id, state)        -> E04/E05
#     TRAP          -> interactable_triggered + sound/cover verbs   -> E04/E05/E06
#     SMOKE         -> visibility multiplier injection (no signal)  -> E05
#   ALL four additionally emit interactable_triggered(obj_id, type, payload) so
#   the HUD slot (E07-S6 / E09-S4) has one uniform feed.
#
# Lifecycle: never construct these by hand in production — InteractableRegistry
# .spawn() assigns the id, binds the bus/ledger and does the refcounting.

const EventBus = preload("res://src/core/event_bus.gd")
const InteractableCharges = preload("res://src/game/interactables/interactable_charges.gd")

var entity_id: int = 0
var type: int = EventBus.InteractableType.DECOY
var position: Vector3 = Vector3.ZERO

var _bus: EventBus = null
var _charges: InteractableCharges = null


# Bind an entity to its level context. Called by InteractableRegistry.spawn();
# safe to call directly from a unit fixture.
func bind(id: int, pos: Vector3, bus: EventBus, ledger: InteractableCharges) -> void:
	entity_id = id
	position = pos
	_bus = bus
	_charges = ledger
	if _charges != null:
		# No-op for carried types; creates the per-object row for world types.
		_charges.ensure_world(entity_id, type)


func set_event_bus(bus: EventBus) -> void:
	_bus = bus


func set_charges(ledger: InteractableCharges) -> void:
	_charges = ledger
	if _charges != null:
		_charges.ensure_world(entity_id, type)


# --- E07-S5 gate -------------------------------------------------------------
func remaining() -> int:
	if _charges == null:
		return 0
	return _charges.remaining(entity_id, type)


## A null ledger means "unconfigured fixture" and stays UNGATED, mirroring the
## null-tolerant _light/_query discipline in vision_cone.gd (headless safety).
## Production always has a ledger — the registry injects one on spawn.
func can_trigger() -> bool:
	if _charges == null:
		return true
	return _charges.has_charge(entity_id, type)


# --- trigger template --------------------------------------------------------
## Fire this interactable. Returns true only when the world actually changed.
##
## A blocked trigger (no charges left, or a subclass FSM gate that refuses) is a
## COMPLETELY SILENT no-op: no domain event, no interactable_triggered, no
## charge spent. "用尽不可投" means the throw never happens — emitting a
## courtesy event here would make every "did the gate hold?" assertion in
## test_interactables.gd unfalsifiable.
func trigger(ctx: Dictionary = {}) -> bool:
	if not can_trigger():
		return false
	# ① The world verb first. A subclass that refuses returns an EMPTY payload,
	#    so a refusal can never silently eat a charge.
	var payload := _fire(ctx)
	if payload.is_empty():
		return false
	# ② Debit, then ③ tell the subclass the debit landed (TRAP advances its FSM
	#    here, because RECOVER's branch depends on the POST-debit balance).
	#    The payload is handed over by reference so the subclass can stamp its
	#    own post-debit facts onto it without a second hook.
	if _charges != null:
		_charges.consume(entity_id, type)
	_on_consumed(payload)
	# ④ One uniform HUD feed. `charges` is the minimal shape locked by D8
	#    (event_bus.gd:81); extra keys are additive and contract-safe.
	payload["charges"] = remaining()
	payload["entity_id"] = entity_id
	_emit_triggered(payload)
	return true


## HUD-only refresh (E07-S6 "道具切换"). Re-announces the CURRENT type + charges
## without touching the world. It rides interactable_triggered because that is
## the only frozen verb the HUD listens to; `hud_only` marks it for any future
## consumer that must not treat it as a world event.
func announce_to_hud() -> void:
	_emit_triggered({
		"charges": remaining(),
		"entity_id": entity_id,
		"hud_only": true,
	})


# --- subclass hooks ----------------------------------------------------------
## Perform the type-specific world effect and return a payload. Return {} to
## refuse (no charge is spent, nothing is emitted).
func _fire(_ctx: Dictionary) -> Dictionary:
	return {}


## Called right after a charge was debited, BEFORE the event goes out. Mutate
## `payload` in place to publish post-debit facts. Default: nothing.
func _on_consumed(_payload: Dictionary) -> void:
	pass


func _emit_triggered(payload: Dictionary) -> void:
	if _bus != null:
		_bus.interactable_triggered.emit(entity_id, type, payload)


# --- budget accounting (E07-S8) ----------------------------------------------
## Does this instance hold a REALTIME light right now (R-02, <=12 MVP / <=32
## Tier2)? Only LIGHT_TOGGLE ever answers true; overridden there.
func occupies_realtime_light() -> bool:
	return false


## Does firing this instance push a ring into the E06 FIFO (G-02, <=8)?
## DECOY and a SOUND-routed TRAP do; overridden there.
func emits_sound_ring() -> bool:
	return false
