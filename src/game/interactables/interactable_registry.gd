class_name InteractableRegistry
extends RefCounted

# ASHEN STEP — Sprint 2, Batch B. E07-S7 (lifecycle) + the counting source for
# E07-S8 (budget).
#
# The registry is the ONE place that:
#   1. allocates entity ids (POSITIVE, so they can never collide with the
#      synthetic carried-pool ids at InteractableCharges.POOL_ID_BASE);
#   2. binds every entity to the same bus + the same charge ledger;
#   3. wires the optional domain owners (E06 SoundPropagator / E04 LightModel /
#      the E07-S4 SmokeField) so a level never hand-wires four setters and
#      forgets one;
#   4. holds the ONLY long-lived reference to each entity, which is what makes
#      "unload the level" a single, provable operation.
#
# ★ E07-S7 in one sentence: because every interactable is a RefCounted (see the
#   header of interactable_entity.gd), dropping the registry's reference is the
#   whole teardown. There is no queue_free() to forget, so an interactable can
#   NEVER become a Godot orphan. release_count()/live_count() below let a test
#   prove the refcount actually went to zero rather than trusting that claim.
#
# ★ Scope discipline: reference counting here covers INTERACTABLE INSTANCES ONLY
#   (sprint2-stories E07-S7). It is not a general-purpose object tracker, and
#   the matching CI scan is WARN-ONLY — it does NOT enter the N-7 gate.
#
# ⚠ ZERO new event vocabulary. The registry emits NOTHING; it only constructs,
#   wires and releases. Every signal still leaves from the entity layer.

const EventBus = preload("res://src/core/event_bus.gd")
const InteractableCharges = preload("res://src/game/interactables/interactable_charges.gd")
const InteractableEntityScript = preload("res://src/game/interactables/interactable_entity.gd")
const DecoyEntityScript = preload("res://src/game/interactables/decoy_entity.gd")
const LightToggleEntityScript = preload("res://src/game/interactables/light_toggle_entity.gd")
const TrapEntityScript = preload("res://src/game/interactables/trap_entity.gd")
const SmokeEntityScript = preload("res://src/game/interactables/smoke_entity.gd")

# First id handed out. MUST stay positive: InteractableCharges persists carried
# pools under negative synthetic ids (interactable_charges.gd:71), and the SAV-S1
# `interactable_charges` dictionary mixes both id spaces in one map.
const FIRST_ENTITY_ID := 1

# E07-S8 / @ci:interactable-instance-cap. A soft ceiling on live interactables
# per level, derived from the two HARD control-manifest limits this system can
# push against: R-02 realtime lights (<=12 MVP) and G-02 sound rings (<=8).
# 16 leaves headroom for BLOCK-only mechanisms (which cost neither) while still
# going loud long before either hard budget can be saturated.
const INSTANCE_CAP := 16

var _entities: Dictionary = {}          # entity_id -> InteractableEntity
var _next_id: int = FIRST_ENTITY_ID
var _spawned_total: int = 0
var _released_total: int = 0

var _bus: EventBus = null
var _charges: InteractableCharges = null
var _sound: SoundPropagator = null
var _model: LightModel = null
var _smoke: SmokeField = null


func _init(bus: EventBus = null, ledger: InteractableCharges = null) -> void:
	_bus = bus
	# A registry without a ledger would silently disable the E07-S5 gate, so it
	# makes its own rather than running ungated.
	_charges = ledger if ledger != null else InteractableCharges.new()


# --- wiring ------------------------------------------------------------------
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		e.set_event_bus(bus)


func set_charges(ledger: InteractableCharges) -> void:
	if ledger == null:
		return
	_charges = ledger
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		e.set_charges(ledger)


func set_sound_propagator(propagator: SoundPropagator) -> void:
	_sound = propagator
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e is TrapEntity:
			(e as TrapEntity).set_sound_propagator(propagator)


func set_light_model(model: LightModel) -> void:
	_model = model
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e is LightToggleEntity:
			(e as LightToggleEntity).set_light_model(model)
		elif e is TrapEntity:
			(e as TrapEntity).set_light_model(model)


func set_smoke_field(field: SmokeField) -> void:
	_smoke = field
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e is SmokeEntity:
			(e as SmokeEntity).set_smoke_field(field)


func charges() -> InteractableCharges:
	return _charges


# --- spawn / despawn ---------------------------------------------------------
## Build, bind and wire one interactable. Returns null for an unknown type
## (rather than a half-built object that fails three calls later).
func spawn(type: int, pos: Vector3 = Vector3.ZERO) -> InteractableEntity:
	var entity := _make(type)
	if entity == null:
		push_warning("InteractableRegistry.spawn: unknown InteractableType %d" % type)
		return null
	var id := _next_id
	_next_id += 1
	entity.bind(id, pos, _bus, _charges)
	_wire(entity)
	_entities[id] = entity
	_spawned_total += 1
	if live_count() > INSTANCE_CAP:
		# WARN-ONLY, exactly like the CI scan. A level that legitimately needs a
		# 17th prop must not be unable to load; it must be VISIBLE.
		push_warning("InteractableRegistry: %d live interactables exceeds INSTANCE_CAP %d (E07-S8)"
			% [live_count(), INSTANCE_CAP])
	return entity


## Retire one entity. Returns false when the id was never live (a double
## despawn is a no-op, not a crash).
func despawn(entity_id: int) -> bool:
	if not _entities.has(entity_id):
		return false
	_entities.erase(entity_id)
	_charges.forget_world(entity_id)
	_released_total += 1
	return true


## E07-S7 level unload. Drops every registry-held reference (which frees each
## RefCounted entity the moment the last outside reference goes too) and clears
## the WORLD charge rows. The CARRIED pools deliberately survive — they are the
## player's backpack, not level furniture (interactable_charges.gd:182).
## Returns how many instances were released.
func unload_level() -> int:
	var n := _entities.size()
	_entities.clear()
	_charges.clear_world()
	_released_total += n
	_next_id = FIRST_ENTITY_ID
	return n


# --- queries -----------------------------------------------------------------
func get_entity(entity_id: int) -> InteractableEntity:
	return _entities.get(entity_id, null)


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


func live_count() -> int:
	return _entities.size()


func live_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _entities.keys():
		ids.append(int(id))
	ids.sort()
	return ids


func spawn_count() -> int:
	return _spawned_total


func release_count() -> int:
	return _released_total


## E07-S7 leak probe: every id ever handed out is either still live or was
## released. Anything else means a reference escaped the registry's bookkeeping.
func leaked_count() -> int:
	return _spawned_total - _released_total - live_count()


func count_of_type(type: int) -> int:
	var n := 0
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e.type == type:
			n += 1
	return n


## True reference count of a live entity (RefCounted bookkeeping, not our own).
## Returns 0 for an unknown id. This is what lets test_interactables.gd assert
## the teardown really released, instead of asserting our own counter agrees
## with itself.
func reference_count_of(entity_id: int) -> int:
	var e: InteractableEntity = _entities.get(entity_id, null)
	if e == null:
		return 0
	return e.get_reference_count()


# --- budget accounting (E07-S8) ----------------------------------------------
## Realtime lights currently held by interactables, for R-02 (<=12 MVP / <=32
## Tier2). Only LIT LightToggleEntity rows count; dousing releases the slot.
func realtime_light_count() -> int:
	var n := 0
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e.occupies_realtime_light():
			n += 1
	return n


## Live instances that WOULD push a ring into the E06 FIFO when fired (G-02,
## <=8). This is a worst-case headroom figure, not a live ring count — E06 owns
## the actual FIFO and its cap (sound_propagation.gd RING_CAP).
func sound_ring_emitter_count() -> int:
	var n := 0
	for id in _entities.keys():
		var e: InteractableEntity = _entities[id]
		if e.emits_sound_ring():
			n += 1
	return n


func over_instance_cap() -> bool:
	return live_count() > INSTANCE_CAP


# --- SAV-S1 pass-through ------------------------------------------------------
## The `interactable_charges` field for SaveManager.make_slot(). The registry is
## the natural caller because it owns the ledger; it still never touches
## SaveManager itself (E07-S5 ships the CONTRACT SHAPE only).
func snapshot_charges() -> Dictionary:
	return _charges.snapshot()


func restore_charges(data: Dictionary) -> void:
	_charges.restore(data)


# --- internals ---------------------------------------------------------------
func _make(type: int) -> InteractableEntity:
	match type:
		EventBus.InteractableType.DECOY:
			return DecoyEntityScript.new()
		EventBus.InteractableType.LIGHT_TOGGLE:
			return LightToggleEntityScript.new()
		EventBus.InteractableType.TRAP:
			return TrapEntityScript.new()
		EventBus.InteractableType.SMOKE:
			return SmokeEntityScript.new()
		_:
			return null


func _wire(entity: InteractableEntity) -> void:
	if entity is LightToggleEntity and _model != null:
		(entity as LightToggleEntity).set_light_model(_model)
	elif entity is TrapEntity:
		var trap := entity as TrapEntity
		if _sound != null:
			trap.set_sound_propagator(_sound)
		if _model != null:
			trap.set_light_model(_model)
	elif entity is SmokeEntity and _smoke != null:
		(entity as SmokeEntity).set_smoke_field(_smoke)
