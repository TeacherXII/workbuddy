class_name InteractableCharges
extends RefCounted

# ASHEN STEP — Sprint 2, Batch B. E07-S5: the charges DUAL MODEL.
#
# interactables.md §9.1 / sprint2-design-scope.md §2.1 lock TWO different
# accounting models behind one API:
#
#   MODEL_WORLD    LIGHT_TOGGLE / TRAP — the WORLD OBJECT owns its charges.
#                  Two candle stands are two independent ledgers; dousing one
#                  must never spend the other.
#   MODEL_CARRIED  DECOY / SMOKE — the BACKPACK owns ONE pool PER TYPE.
#                  Every pebble in the level draws from the same counter,
#                  because the counter belongs to the player, not to the pebble.
#
# Getting this backwards is a real bug in both directions: a per-entity decoy
# ledger makes the backpack infinite (pick up a new pebble, get a new charge),
# and a per-type light ledger lets one candle lock out every other candle in
# the level.
#
# ⚠ ZERO new event vocabulary. This class is a pure ledger — it emits nothing.
#   The entity layer (interactable_entity.gd) owns every signal emission.
#
# E11 contract (SAV-S1): snapshot()/restore() speak the frozen save field
# `interactable_charges: Dictionary[int,int]`. This file NEVER touches
# SaveManager; it only produces/consumes the dictionary shape.

const EventBus = preload("res://src/core/event_bus.gd")

# --- model selection --------------------------------------------------------
const MODEL_WORLD := 0
const MODEL_CARRIED := 1

const MODEL_BY_TYPE := {
	EventBus.InteractableType.DECOY: MODEL_CARRIED,
	EventBus.InteractableType.LIGHT_TOGGLE: MODEL_WORLD,
	EventBus.InteractableType.TRAP: MODEL_WORLD,
	EventBus.InteractableType.SMOKE: MODEL_CARRIED,
}

# interactables.md §2: "charges MVP 每类 2–3 发". Every default below MUST sit
# inside [CHARGES_MIN, CHARGES_MAX]; test_interactables.gd reverse-asserts it so
# a "just bump it to 10" edit goes red instead of quietly breaking the economy.
const CHARGES_MIN := 2
const CHARGES_MAX := 3

const DEFAULT_CHARGES := {
	EventBus.InteractableType.DECOY: 3,          # entity-inventory #10 Decoy
	EventBus.InteractableType.LIGHT_TOGGLE: 3,   # entity-inventory #12/#13 Candle / Sconce
	EventBus.InteractableType.TRAP: 2,           # entity-inventory #16 Lever / Rune / Winch
	EventBus.InteractableType.SMOKE: 2,          # entity-inventory #11 Smoke Screen
}

# The level/asset layer names entities the way entity-inventory.md does. This is
# the ONLY place that string -> enum mapping is allowed to live.
const INVENTORY_KEYS := {
	"DECOY": EventBus.InteractableType.DECOY,
	"LIGHT_TOGGLE": EventBus.InteractableType.LIGHT_TOGGLE,
	"TRAP": EventBus.InteractableType.TRAP,
	"SMOKE": EventBus.InteractableType.SMOKE,
}

# --- SAV-S1 wire contract ---------------------------------------------------
# `interactable_charges` is entity_id -> remaining. A CARRIED pool has no single
# owning entity (the whole backpack shares it), so it is persisted under a
# SYNTHETIC id: pool_id(type) = POOL_ID_BASE - type.
#   DECOY -> -100   SMOKE -> -103
# Level entity ids are always POSITIVE (InteractableRegistry.FIRST_ENTITY_ID),
# so the two id spaces can never collide, and SaveManager._norm_int_int
# round-trips negative ints unchanged (int("-100") == -100).
const POOL_ID_BASE := -100

# entity_id -> remaining (MODEL_WORLD rows only)
var _world: Dictionary = {}
# InteractableType -> remaining (MODEL_CARRIED pools only)
var _carried: Dictionary = {}
# InteractableType -> configured initial value (entity-inventory override)
var _initial: Dictionary = {}


func _init() -> void:
	# A bare ledger is already playable: the carried pools seed themselves from
	# DEFAULT_CHARGES so a unit fixture never has to hand-configure the backpack.
	_seed_missing_pools()


# --- static helpers ---------------------------------------------------------
static func model_for(type: int) -> int:
	return int(MODEL_BY_TYPE.get(type, MODEL_CARRIED))


static func pool_id_for(type: int) -> int:
	return POOL_ID_BASE - type


static func is_pool_id(entity_id: int) -> bool:
	return entity_id <= POOL_ID_BASE


# --- configuration (entity-inventory) ---------------------------------------
## Load per-type initial charges from the level's entity-inventory block.
## Keys may be the InteractableType ordinal OR the entity-inventory word
## ("DECOY"/"SMOKE"/"LIGHT_TOGGLE"/"TRAP"). Unknown keys are WARNED and skipped
## — never silently swallowed, because a typo'd level config that quietly falls
## back to the default is exactly the bug that ships as "the smoke feels wrong".
func configure_from_inventory(cfg: Dictionary) -> void:
	for raw_key in cfg.keys():
		var type := _resolve_type(raw_key)
		if type < 0:
			push_warning("InteractableCharges: unknown entity-inventory key `%s` ignored"
				% str(raw_key))
			continue
		var amount := int(cfg[raw_key])
		if amount < CHARGES_MIN or amount > CHARGES_MAX:
			push_warning("InteractableCharges: `%s` initial charges %d outside the GDD band [%d,%d]"
				% [str(raw_key), amount, CHARGES_MIN, CHARGES_MAX])
		amount = maxi(0, amount)
		_initial[type] = amount
		if model_for(type) == MODEL_CARRIED:
			_carried[type] = amount
	_seed_missing_pools()


func initial_for(type: int) -> int:
	if _initial.has(type):
		return int(_initial[type])
	return int(DEFAULT_CHARGES.get(type, 0))


# --- ledger ------------------------------------------------------------------
## Create the world row for a freshly registered LIGHT_TOGGLE / TRAP. No-op for
## carried types (their pool is type-scoped, not entity-scoped) and idempotent,
## so a re-register never refills a half-spent lever.
func ensure_world(entity_id: int, type: int) -> void:
	if model_for(type) != MODEL_WORLD:
		return
	if not _world.has(entity_id):
		_world[entity_id] = initial_for(type)


func remaining(entity_id: int, type: int) -> int:
	if model_for(type) == MODEL_WORLD:
		return int(_world.get(entity_id, initial_for(type)))
	return int(_carried.get(type, initial_for(type)))


func has_charge(entity_id: int, type: int) -> bool:
	return remaining(entity_id, type) > 0


## Spend exactly one charge. Returns false (and changes NOTHING) when the
## ledger is already empty — the gate and the debit are the same call, so no
## caller can decrement past zero by forgetting to check first.
func consume(entity_id: int, type: int) -> bool:
	var left := remaining(entity_id, type)
	if left <= 0:
		return false
	if model_for(type) == MODEL_WORLD:
		_world[entity_id] = left - 1
	else:
		_carried[type] = left - 1
	return true


## Resupply. Sprint 2 ships CONFIGURATION only (sprint2-stories E07-S5: "用尽需
## 补给（Sprint 2 仅配置不实现补给 UI）"), so this is the seam a pickup would
## call — there is no UI wired to it this sprint.
func refill(entity_id: int, type: int, amount: int) -> void:
	var add := maxi(0, amount)
	if add == 0:
		return
	if model_for(type) == MODEL_WORLD:
		_world[entity_id] = remaining(entity_id, type) + add
	else:
		_carried[type] = remaining(entity_id, type) + add


func forget_world(entity_id: int) -> void:
	_world.erase(entity_id)


## Level unload (E07-S7). World rows die WITH the level; the carried pools are
## the player's backpack and deliberately SURVIVE — walking through a door must
## not refill (or confiscate) the pebbles.
func clear_world() -> void:
	_world.clear()


func world_row_count() -> int:
	return _world.size()


# --- SAV-S1 snapshot / restore ----------------------------------------------
## entity_id -> remaining, ready to hand to SaveManager.make_slot() under the
## frozen `interactable_charges` field. Ordering is deterministic (pools first,
## then world ids ascending) so slot diffs stay readable inside the SAV-S2 size
## budget.
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	var carried_types: Array = _carried.keys()
	carried_types.sort()
	for type in carried_types:
		out[pool_id_for(int(type))] = int(_carried[type])
	var world_ids: Array = _world.keys()
	world_ids.sort()
	for id in world_ids:
		out[int(id)] = int(_world[id])
	return out


func restore(data: Dictionary) -> void:
	for raw_id in data.keys():
		var id := int(raw_id)
		var amount := maxi(0, int(data[raw_id]))
		if is_pool_id(id):
			var type := POOL_ID_BASE - id
			if MODEL_BY_TYPE.has(type):
				_carried[type] = amount
			else:
				push_warning("InteractableCharges.restore: unknown carried pool id %d" % id)
			continue
		_world[id] = amount


# --- internals ---------------------------------------------------------------
func _seed_missing_pools() -> void:
	for type in MODEL_BY_TYPE.keys():
		if model_for(int(type)) != MODEL_CARRIED:
			continue
		if not _carried.has(type):
			_carried[type] = initial_for(int(type))


func _resolve_type(raw: Variant) -> int:
	match typeof(raw):
		TYPE_INT, TYPE_FLOAT:
			var as_int := int(raw)
			return as_int if MODEL_BY_TYPE.has(as_int) else -1
		TYPE_STRING, TYPE_STRING_NAME:
			var key := str(raw).to_upper()
			return int(INVENTORY_KEYS.get(key, -1))
		_:
			return -1
