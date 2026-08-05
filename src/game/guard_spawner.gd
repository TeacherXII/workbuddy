class_name GuardSpawner
extends RefCounted

# ASHEN STEP — Sprint 3 Batch A. E08-S9 variant instantiation + G-01 budget.
#
# Story: E08-S9 "变体实例化与 entity-inventory 类型绑定" — a level names its
#        guards by the TYPE FIELD of design/assets/entity-inventory.md (rows
#        2/3/4); this class turns those rows into live GuardBrain instances with
#        the matching GuardVariantParams overlay applied, and counts every one
#        of them against control-manifest G-01.
#
# Scope discipline (GDD §9.4 / architecture §3.4): this is NOT a new system. It
# creates the SAME GuardBrain the standard guard uses and hands it a parameter
# object. No new FSM state, no new mechanic family, and — critically — ZERO new
# event vocabulary: nothing here touches src/core/event_bus.gd, and no
# `guard_spawned` signal is introduced (that idea is parked in GDD §9.1 pending
# an E01-S9 vocabulary decision, and Sprint 3 Batch A does not spend it).
#
# RefCounted on purpose: a spawner that is itself a Node is one more thing that
# can be dropped without queue_free() (FLAG-D orphan debt). The brains it makes
# ARE Nodes — that is GuardBrain's pre-existing shape — so their lifetime is
# tracked here and released by despawn_all().

const GuardBrainScript := preload("res://src/game/patrol_ai.gd")

# ── control-manifest G-01 (:86) 同区活动守卫 MVP <= 8 / Tier2 <= 16 ──────────
# Tier2 is where the variants live (entity-inventory rows 3/4 are both Tier2),
# so the two rungs are modelled explicitly rather than collapsed to the larger
# number: shipping the MVP slice must not silently inherit the Tier2 headroom.
const GUARD_BUDGET_MVP := 8
const GUARD_BUDGET_TIER2 := 16

enum Tier {
	MVP = 0,
	TIER2 = 1,
}

const TIER_NAMES := {
	Tier.MVP: "MVP",
	Tier.TIER2: "Tier2",
}


## Which budget rung this spawner enforces. Defaults to the CONSERVATIVE rung:
## a level that wants the Tier2 headroom has to ask for it in writing. (A
## default of TIER2 would mean an MVP level could quietly ship 16 guards and
## only discover G-01 at profiling time.)
var tier: int = Tier.MVP

## E08-S9 anti-rot ledger. An entity-inventory row whose type field is not in
## GuardVariantParams.ENTITY_TYPE_TO_VARIANT still spawns (as STANDARD, so a
## typo does not crash a level) but is recorded here. Without this ledger a
## misspelled "SENTINAL" would spawn a perfectly healthy standard guard and the
## missing dark vision would never surface — the variant would be "working"
## right up until someone play-tested the shadow that was supposed to be unsafe.
var unknown_entity_types: PackedStringArray = PackedStringArray()

## Spawn requests refused because the G-01 budget was already full.
var over_budget_rejections: int = 0

var _live: Array = []          # Array[GuardBrain], insertion-ordered
var _next_auto_id: int = 1


# ── Budget ──────────────────────────────────────────────────────────────────
func budget() -> int:
	return GUARD_BUDGET_TIER2 if tier == Tier.TIER2 else GUARD_BUDGET_MVP


func tier_name() -> String:
	return str(TIER_NAMES.get(tier, "MVP"))


func live_count() -> int:
	_prune_freed()
	return _live.size()


func can_spawn() -> bool:
	return live_count() < budget()


func live_guards() -> Array:
	_prune_freed()
	return _live.duplicate()


## How many guards of a given variant are currently live (G-01 accounting by
## variant, so a level can be told "you are at 16 because 9 of them are hounds").
func live_count_of_variant(v: int) -> int:
	var n := 0
	for b in live_guards():
		if b.get_variant_params().variant == v:
			n += 1
	return n


# ── Spawning ────────────────────────────────────────────────────────────────
## Instantiate one guard of `variant`. Returns null when the G-01 budget for the
## current tier is already full — REFUSING is the enforcement (the budget is a
## cap, not a suggestion); the caller can read over_budget_rejections.
##
## `guard_id` defaults to an auto-incrementing id. The brain is NOT added to any
## scene tree here: GuardBrain is headless-driven (its own tests do the same),
## and tree insertion is the level's decision.
func spawn(variant: int = GuardVariantParams.Variant.STANDARD, guard_id: int = -1) -> GuardBrain:
	if not can_spawn():
		over_budget_rejections += 1
		return null
	var brain: GuardBrain = GuardBrainScript.new()
	brain.guard_id = guard_id if guard_id >= 0 else _take_auto_id()
	# ★ The whole batch in one line: the variant is applied as a PARAMETER
	# OBJECT. No class constant of GuardBrain is written, here or anywhere else
	# (FLAG-B). See patrol_ai.gd::set_variant_params.
	brain.set_variant_params(GuardVariantParams.for_variant(variant))
	_live.append(brain)
	return brain


## E08-S9 — spawn from an entity-inventory TYPE FIELD (the asset-driven path).
func spawn_from_entity_type(type_field: String, guard_id: int = -1) -> GuardBrain:
	if not GuardVariantParams.is_known_entity_type(type_field):
		unknown_entity_types.append(type_field)
	var v := GuardVariantParams.variant_for_entity_type(type_field)
	if v == GuardVariantParams.VARIANT_UNKNOWN:
		v = GuardVariantParams.Variant.STANDARD
	return spawn(v, guard_id)


## E08-S9 — load a whole entity-inventory slice. `rows` is an Array of
## Dictionaries shaped like the asset sheet:
##     {"type": "守卫·循声猎犬", "guard_id": 3}
## `guard_id` is optional. Rows past the G-01 budget are refused (and counted),
## so an over-populated level is truncated at the cap instead of blowing it.
## Returns the guards actually spawned, in row order.
func spawn_from_inventory(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var type_field := ""
		var gid := -1
		if row is Dictionary:
			type_field = str(row.get("type", row.get("entity_type", "")))
			gid = int(row.get("guard_id", -1))
		else:
			type_field = str(row)
		var brain := spawn_from_entity_type(type_field, gid)
		if brain != null:
			out.append(brain)
	return out


# ── Lifetime ────────────────────────────────────────────────────────────────
## Drop one guard from the budget ledger and free it. Frees rather than leaks:
## GuardBrain is a Node, and a Node dropped without free() is a Godot orphan
## (FLAG-D). Nodes that live in a tree get queue_free(); tree-free nodes (the
## headless case) get free().
func despawn(brain: GuardBrain) -> void:
	_live.erase(brain)
	_free_brain(brain)


func despawn_all() -> void:
	var doomed := _live.duplicate()
	_live.clear()
	for b in doomed:
		_free_brain(b)


## Forget every tracked guard WITHOUT freeing it — for callers (tests included)
## that hand ownership to something else, e.g. GUT's autofree.
func release_all() -> void:
	_live.clear()


# ── @ci:guard-instance-budget (G-01) · WARN-ONLY surface ────────────────────
## Pure function so tests/ci/budget_assert.gd can report G-01 without owning any
## of the arithmetic, and so tests/unit/test_guard_variants.gd can feed it an
## over-budget count and prove it actually warns (reverse assertion: a scan that
## can never fire is a scan that rots green).
##
## WARN-ONLY by [D15-A]/[N-12]: this returns TEXT. It never exits, never throws,
## and its caller must keep exit code 0.
static func budget_warnings(count: int, for_tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cap: int = GUARD_BUDGET_TIER2 if for_tier == Tier.TIER2 else GUARD_BUDGET_MVP
	if count > cap:
		out.append("guard-instance-budget")
	return out


## Human-readable line for the same check (kept next to the logic so the two
## cannot describe different numbers).
static func budget_detail(count: int, for_tier: int) -> String:
	var cap: int = GUARD_BUDGET_TIER2 if for_tier == Tier.TIER2 else GUARD_BUDGET_MVP
	var label: String = "Tier2" if for_tier == Tier.TIER2 else "MVP"
	return "%s active guards %d / cap %d" % [label, count, cap]


# ── internals ───────────────────────────────────────────────────────────────
func _take_auto_id() -> int:
	var id := _next_auto_id
	_next_auto_id += 1
	return id


func _prune_freed() -> void:
	# A caller may have freed a brain behind our back (a level tearing down its
	# scene, or GUT's autofree). Stale handles must not eat G-01 headroom.
	var kept: Array = []
	for b in _live:
		if is_instance_valid(b):
			kept.append(b)
	_live = kept


func _free_brain(brain: GuardBrain) -> void:
	if brain == null or not is_instance_valid(brain):
		return
	if brain.is_inside_tree():
		brain.queue_free()
	else:
		brain.free()
