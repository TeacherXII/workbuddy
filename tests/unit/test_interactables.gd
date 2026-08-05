# tests/unit/test_interactables.gd
# GUT unit tests for the real E07 interactable entity layer (Sprint 2 · Batch B).
#
# Covers:
#   E07-S1 DECOY        -> decoy_landed(pos, surface, radius~8m) -> E06 ring, charges-1
#   E07-S2 LIGHT_TOGGLE -> light_state_changed(id, EXTINGUISHED|LIT) -> E04/E05
#   E07-S3 TRAP         -> internal FSM + routing to the EXISTING E04/E05/E06 verbs
#   E07-S4 SMOKE        -> vis = base x cover x smoke (0.3) for ~4s, then expires
#   E07-S5 charges      -> world vs carried dual model + the SAV-S1 contract shape
#   E07-S7 lifecycle    -> registry reference counting + level-unload release
#   E07-S8 budget       -> the two WARN-ONLY scans, and R-02/G-02 left intact
#
# ★ ZERO new event vocabulary. Every assertion below watches a signal that was
#   already frozen in src/core/event_bus.gd; nothing in this suite would pass if
#   a new signal had been minted.
#
# ★ N-7: this file contains no bare risky-token literal. These are plain @test
#   functions, and the budget assertions they touch are WARN-ONLY.
#
# Headless discipline (same as test_sound_propagation.gd:29): EventBus /
# SoundPropagator / VisionCone are Nodes deliberately kept OUT of the scene tree
# — every entry point under test is pure logic — and are released with
# autofree() so the orphan count never regresses. The interactable entities
# themselves are RefCounted and need no such ceremony; that is the whole point
# of E07-S7.
#
# Time is NEVER advanced with a sleep: SmokeField exposes a clock override so a
# 4-second expiry is proven deterministically in microseconds.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const EventBusScript = preload("res://src/core/event_bus.gd")
const SoundPropagatorScript = preload("res://src/game/sound_propagation.gd")
const LightModelScript = preload("res://src/game/light_model.gd")
const VisionConeScript = preload("res://src/game/vision_cone.gd")
const SaveManagerScript = preload("res://src/core/save_manager.gd")
const BudgetChecks = preload("res://tests/ci/budget_checks.gd")

const ChargesScript = preload("res://src/game/interactables/interactable_charges.gd")
const RegistryScript = preload("res://src/game/interactables/interactable_registry.gd")
const DecoyScript = preload("res://src/game/interactables/decoy_entity.gd")
const LightToggleScript = preload("res://src/game/interactables/light_toggle_entity.gd")
const TrapScript = preload("res://src/game/interactables/trap_entity.gd")
const SmokeScript = preload("res://src/game/interactables/smoke_entity.gd")
const SmokeFieldScript = preload("res://src/game/interactables/smoke_field.gd")

const T_DECOY := EventBusScript.InteractableType.DECOY
const T_LIGHT := EventBusScript.InteractableType.LIGHT_TOGGLE
const T_TRAP := EventBusScript.InteractableType.TRAP
const T_SMOKE := EventBusScript.InteractableType.SMOKE

const LIT := EventBusScript.LightState.LIT
const EXTINGUISHED := EventBusScript.LightState.EXTINGUISHED

# Hermetic scratch space for the CI reverse-assertions. Never touches the repo
# or a developer's real user:// data beyond this one subdirectory.
const TEST_DIR := "user://__test_interactables"

var _bus: EventBusScript
var _reg: RegistryScript
var _decoy_events: Array = []
var _triggered: Array = []
var _lights: Array = []
var _cells: Array = []


func before_all() -> void:
	var d := DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive("__test_interactables")


func after_all() -> void:
	# Best-effort cleanup: the scratch dir lives in user:// app-data and is
	# harmless if it lingers, but a leftover .tscn would poison a later scan.
	# `fname`, not `name`: GutTest extends Node, and `name` is a Node property.
	for fname in ["orphan_viol.tscn", "cap_viol.tscn"]:
		var g := ProjectSettings.globalize_path(TEST_DIR.path_join(fname))
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)


func before_each() -> void:
	_bus = autofree(EventBusScript.new())
	_reg = RegistryScript.new(_bus)
	_decoy_events = []
	_triggered = []
	_lights = []
	_cells = []
	_bus.decoy_landed.connect(_on_decoy_landed)
	_bus.interactable_triggered.connect(_on_triggered)
	_bus.light_state_changed.connect(_on_light_changed)
	_bus.cover_state_changed.connect(_on_cover_changed)
	watch_signals(_bus)


func after_each() -> void:
	_reg = null
	_bus = null
	# Harness discipline: FOCUS-mode tests elsewhere in the suite mutate the
	# global time scale, and a leaked value would silently skew any timing
	# assertion that runs after them.
	Engine.time_scale = 1.0


func _on_decoy_landed(pos: Vector3, surface: String, radius: float) -> void:
	_decoy_events.append({"pos": pos, "surface": surface, "radius": radius})


func _on_triggered(obj_id: int, type: int, payload: Dictionary) -> void:
	_triggered.append({"obj_id": obj_id, "type": type, "payload": payload})


func _on_light_changed(light_id: int, state: int) -> void:
	_lights.append({"light_id": light_id, "state": state})


func _on_cover_changed(cell: Vector3i) -> void:
	_cells.append(cell)


# --- E07-S1 -------------------------------------------------------------------
func test_decoy_spawn_emits_decoy_landed_and_decrements_charges() -> void:
	# A REAL E06 propagator is wired to the same bus, so this proves the whole
	# chain the story specifies: throw -> decoy_landed -> E06 sound ring.
	var sp: SoundPropagatorScript = autofree(SoundPropagatorScript.new())
	sp.set_event_bus(_bus)

	var decoy := _reg.spawn(T_DECOY, Vector3.ZERO) as DecoyScript
	assert_not_null(decoy, "E07-S1: the registry must be able to spawn a DECOY")
	var before := _reg.charges().remaining(decoy.entity_id, T_DECOY)
	assert_gt(before, 0, "E07-S1 precondition: a fresh backpack must hold decoys")

	var landing := Vector3(3, 0, 4)
	assert_true(decoy.throw(landing, "STONE"),
		"E07-S1: a throw with charges available must succeed")

	# ① the frozen signal, with every declared parameter (N-8).
	assert_eq(_decoy_events.size(), 1, "E07-S1: exactly one decoy_landed per throw")
	assert_eq(_decoy_events[0]["pos"], landing,
		"E07-S1: decoy_landed must carry the LANDING point, not the thrower")
	assert_eq(_decoy_events[0]["surface"], "STONE", "E07-S1: surface rides the signal")
	assert_eq(_decoy_events[0]["radius"], SoundPropagatorScript.DECOY_RADIUS,
		"E07-S1: radius must be the E06 constant ~8m, never a second literal")
	assert_almost_eq(_decoy_events[0]["radius"], 8.0, 0.001,
		"E07-S1 acceptance: radius ~8m (interactables.md §2)")

	# ② E06 really turned it into a sound event (the ring path, not a stub).
	assert_signal_emitted(_bus, "sound_emitted",
		"E07-S1: decoy_landed must reach E06 and produce a sound event")
	assert_false(sp.is_over_ring_budget(),
		"E07-S8/G-02: one decoy ring must not exceed the FIFO cap")

	# ③ the charge was spent, and the HUD feed carries the new count.
	assert_eq(_reg.charges().remaining(decoy.entity_id, T_DECOY), before - 1,
		"E07-S1: a successful throw spends exactly one charge")
	assert_eq(_triggered.size(), 1, "E07-S1: the HUD feed sees the throw")
	assert_eq(_triggered[0]["type"], T_DECOY, "E07-S1: HUD feed carries the type")
	assert_eq(int(_triggered[0]["payload"]["charges"]), before - 1,
		"E07-S1/D8: interactable_triggered payload reports the POST-debit count")

	# ④ the pebble now lies where it landed (a later save/announce reads this).
	assert_eq(decoy.position, landing, "E07-S1: the entity moves to its landing point")


# --- E07-S2 -------------------------------------------------------------------
func test_light_toggle_emits_light_state_changed() -> void:
	var lm := LightModelScript.new()
	_reg.set_light_model(lm)
	var fixture := _reg.spawn(T_LIGHT, Vector3(2, 0, 0)) as LightToggleScript
	assert_not_null(fixture, "E07-S2: the registry must be able to spawn a LIGHT_TOGGLE")
	assert_true(fixture.is_lit(), "E07-S2 precondition: a fresh fixture is LIT")

	assert_true(fixture.toggle(), "E07-S2: dousing a charged fixture must succeed")
	assert_eq(_lights.size(), 1, "E07-S2: exactly one light_state_changed per interact")
	assert_eq(_lights[0]["light_id"], fixture.effective_light_id(),
		"E07-S2: the frozen signature carries the LIGHT id")
	assert_eq(_lights[0]["state"], EXTINGUISHED,
		"E07-S2: LIT -> EXTINGUISHED on the first interact")

	# E04 is the single authority for the state; the entity mirrors, not decides.
	assert_eq(lm.get_light_state(fixture.effective_light_id()), EXTINGUISHED,
		"E07-S2: LightModel (E04) holds the authoritative state")
	assert_false(fixture.is_lit(), "E07-S2: the entity reads its state back from E04")

	# Relight: the same verb flips back. Two authorities would drift here.
	assert_true(fixture.toggle(), "E07-S2: relighting is the same verb")
	assert_eq(_lights[1]["state"], LIT, "E07-S2: EXTINGUISHED -> LIT on the second interact")

	# E07-S8 / R-02: a doused fixture RELEASES its realtime light slot.
	assert_eq(_reg.realtime_light_count(), 1, "E07-S8: a LIT fixture holds one R-02 slot")
	fixture.toggle()
	assert_eq(_reg.realtime_light_count(), 0, "E07-S8: dousing returns the R-02 slot")


# --- E07-S3 -------------------------------------------------------------------
func test_trap_fsm_transitions() -> void:
	var trap := _reg.spawn(T_TRAP, Vector3(5, 0, 5)) as TrapScript
	assert_not_null(trap, "E07-S3: the registry must be able to spawn a TRAP")
	assert_eq(trap.state, TrapScript.State.IDLE, "E07-S3: a mechanism starts IDLE")

	# An unarmed mechanism does nothing AND spends nothing. Without this gate the
	# FSM would be decoration.
	var charges_at_idle := _reg.charges().remaining(trap.entity_id, T_TRAP)
	assert_false(trap.trigger({}), "E07-S3: IDLE must refuse to trigger")
	assert_eq(_reg.charges().remaining(trap.entity_id, T_TRAP), charges_at_idle,
		"E07-S3: a refused trigger must NOT eat a charge")
	assert_eq(_triggered.size(), 0, "E07-S3: a refused trigger emits nothing at all")

	assert_true(trap.arm(), "E07-S3: IDLE -> ARMED")
	assert_eq(trap.state, TrapScript.State.ARMED, "E07-S3: arm() lands in ARMED")

	# First spring: TRIGGERED -> RECOVER -> ARMED, because charges remain.
	assert_true(trap.trigger({}), "E07-S3: an ARMED mechanism springs")
	assert_eq(trap.state, TrapScript.State.ARMED,
		"E07-S3: RECOVER re-arms while charges remain")
	assert_eq(trap.state_history(), [
			TrapScript.State.IDLE,
			TrapScript.State.ARMED,
			TrapScript.State.TRIGGERED,
			TrapScript.State.RECOVER,
			TrapScript.State.ARMED,
		],
		"E07-S3: the FSM path must be IDLE->ARMED->TRIGGERED->RECOVER->ARMED")

	# Second spring exhausts the mechanism: RECOVER branches to SPENT instead.
	assert_true(trap.trigger({}), "E07-S3: the second spring still fires")
	assert_eq(trap.state, TrapScript.State.SPENT,
		"E07-S3: RECOVER -> SPENT once the POST-debit balance hits zero")
	assert_true(trap.is_spent(), "E07-S3: is_spent() agrees with the state")

	# SPENT is terminal this sprint (resupply is config-only, E07-S5).
	assert_false(trap.trigger({}), "E07-S3: a SPENT mechanism cannot fire")
	assert_false(trap.arm(), "E07-S3: a SPENT mechanism cannot be re-armed")
	assert_eq(trap.state, TrapScript.State.SPENT, "E07-S3: SPENT is terminal")

	# The FSM reports itself on the frozen HUD feed — no new signal was minted.
	var last: Dictionary = _triggered[_triggered.size() - 1]["payload"]
	assert_eq(int(last["state"]), TrapScript.State.SPENT,
		"E07-S3: the FSM state rides interactable_triggered, not a new signal")


func test_trap_routes_to_sound_light_block() -> void:
	# A winch drives all three verbs at once. The point of E07-S3 is that this
	# introduces NO new mechanism family: each verb is an EXISTING system's API.
	var sp: SoundPropagatorScript = autofree(SoundPropagatorScript.new())
	sp.set_event_bus(_bus)
	var lm := LightModelScript.new()
	_reg.set_sound_propagator(sp)
	_reg.set_light_model(lm)

	var trap := _reg.spawn(T_TRAP, Vector3(0, 0, 7)) as TrapScript
	trap.set_verbs([TrapScript.VERB_SOUND, TrapScript.VERB_LIGHT, TrapScript.VERB_BLOCK])
	assert_true(trap.arm(), "routing precondition: the mechanism is armed")
	assert_true(trap.trigger({}), "routing precondition: the mechanism springs")

	var routed: Array = _triggered[0]["payload"]["routed"]
	assert_eq(routed.size(), 3, "E07-S3: all three verbs must report as routed")

	# SOUND -> E06 (which owns the ring FIFO and the sound_emitted broadcast).
	assert_signal_emitted(_bus, "sound_emitted",
		"E07-S3/SOUND: the mechanism must reach E06")
	assert_false(sp.is_over_ring_budget(),
		"E07-S8/G-02: a sprung mechanism must not blow the ring FIFO")

	# LIGHT -> E04 (authoritative state) + the frozen bus signal.
	assert_eq(_lights.size(), 1, "E07-S3/LIGHT: exactly one light_state_changed")
	assert_eq(_lights[0]["state"], EXTINGUISHED,
		"E07-S3/LIGHT: the verb flips the fixture through E04")
	assert_eq(lm.get_light_state(trap.effective_light_id()), EXTINGUISHED,
		"E07-S3/LIGHT: E04 holds the authoritative state, not the mechanism")

	# BLOCK -> E05 cell recompute (G-03: O(cell), never a full-grid rebuild).
	assert_eq(_cells.size(), 1, "E07-S3/BLOCK: exactly one cover_state_changed")
	assert_eq(_cells[0], TrapScript.cell_of(trap.position),
		"E07-S3/BLOCK: the dirtied cell is the mechanism's own cell")

	# The whole routing table used ONLY frozen vocabulary.
	assert_eq(_triggered.size(), 1,
		"E07-S3: one spring produces exactly one interactable_triggered")
	assert_eq(_triggered[0]["type"], T_TRAP, "E07-S3: the HUD feed carries TRAP")


# --- E07-S4 -------------------------------------------------------------------
func test_smoke_applies_visibility_0_3_for_4s() -> void:
	var vc: VisionConeScript = autofree(VisionConeScript.new())
	var lm := LightModelScript.new()
	vc.set_light_model(lm)
	vc.observer_pos = Vector3.ZERO
	# Vector3.FORWARD is (0,0,-1); targets sit at +Z, so the observer looks BACK
	# (same note as test_vision_cone.gd:28).
	vc.observer_forward = Vector3.BACK
	var target := Vector3(0, 0, 5)

	var field := SmokeFieldScript.new()
	# Deterministic clock: a 4s expiry must be provable without a 4s sleep.
	field.set_clock_override(0.0)
	vc.set_smoke_field(field)
	_reg.set_smoke_field(field)

	assert_eq(vc.compute_visibility(target), 1.0,
		"E07-S4 baseline: a lit target in the open is fully visible")

	var smoke := _reg.spawn(T_SMOKE, Vector3.ZERO) as SmokeScript
	var before := _reg.charges().remaining(smoke.entity_id, T_SMOKE)
	assert_true(smoke.throw(target), "E07-S4: a smoke throw with charges must succeed")
	assert_eq(_reg.charges().remaining(smoke.entity_id, T_SMOKE), before - 1,
		"E07-S4: a smoke throw spends exactly one charge")

	# vis = base x smoke
	assert_almost_eq(vc.compute_visibility(target), 0.3, 0.001,
		"E07-S4: a target inside the puff reads smoke_factor 0.3")
	assert_eq(SmokeFieldScript.factor(), VisionConeScript.VIS_MULT_SMOKE,
		"E07-S4: 0.3 has exactly ONE owner (E05), never a second copy")

	# vis = base x cover x smoke (the full formula the story specifies).
	assert_almost_eq(vc.compute_visibility(target, VisionConeScript.VIS_MULT_COVER),
		0.18, 0.001,
		"E07-S4: cover and smoke multiply (1.0 x 0.6 x 0.3), they do not replace")

	# R-03: smoke LOWERS visibility, it never grants invisibility. Two overlapping
	# puffs must still read 0.3, not 0.09.
	field.spawn(target, SmokeFieldScript.RADIUS, SmokeFieldScript.DURATION_RT)
	assert_almost_eq(vc.compute_visibility(target), 0.3, 0.001,
		"E07-S4/R-03: overlapping puffs must NOT stack toward invisibility")

	# ~4s lifetime.
	assert_almost_eq(SmokeFieldScript.DURATION_RT, 4.0, 0.001,
		"E07-S4 acceptance: the puff lasts ~4s")
	field.advance_clock(3.9)
	assert_almost_eq(vc.compute_visibility(target), 0.3, 0.001,
		"E07-S4: the puff is still live just before it expires")
	field.advance_clock(0.2)
	assert_eq(vc.compute_visibility(target), 1.0,
		"E07-S4: after ~4s the puff expires and visibility returns to baseline")
	assert_eq(field.active_count(), 0, "E07-S4: expired puffs are pruned, not leaked")

	# A target OUTSIDE the puff was never affected in the first place.
	field.set_clock_override(0.0)
	field.spawn(Vector3(0, 0, 5), SmokeFieldScript.RADIUS, SmokeFieldScript.DURATION_RT)
	assert_eq(vc.compute_visibility(Vector3(0, 0, 12)), 1.0,
		"E07-S4: smoke is local — a target outside the radius is unaffected")


# --- E07-S5 -------------------------------------------------------------------
func test_charges_gate_blocks_when_zero() -> void:
	var decoy := _reg.spawn(T_DECOY, Vector3.ZERO) as DecoyScript
	var stock := _reg.charges().remaining(decoy.entity_id, T_DECOY)
	assert_gt(stock, 0, "gate precondition: the backpack starts stocked")

	for i in range(stock):
		assert_true(decoy.throw(Vector3(float(i), 0, 0), "STONE"),
			"E07-S5: throw %d must succeed while charges remain" % i)
	assert_eq(_reg.charges().remaining(decoy.entity_id, T_DECOY), 0,
		"E07-S5: the pool is now empty")

	# "用尽不可触发": the throw does not happen. Not a quieter throw — no throw.
	var events_before := _decoy_events.size()
	var hud_before := _triggered.size()
	assert_false(decoy.throw(Vector3(9, 0, 9), "STONE"),
		"E07-S5: an exhausted item must refuse to fire")
	assert_eq(_decoy_events.size(), events_before,
		"E07-S5: a blocked throw emits NO domain event")
	assert_eq(_triggered.size(), hud_before,
		"E07-S5: a blocked throw emits NO interactable_triggered either")
	assert_eq(_reg.charges().remaining(decoy.entity_id, T_DECOY), 0,
		"E07-S5: a blocked throw cannot decrement past zero")

	# The gate is the same call as the debit, so no caller can bypass it.
	assert_false(_reg.charges().consume(decoy.entity_id, T_DECOY),
		"E07-S5: consume() on an empty ledger returns false and changes nothing")

	# A world object hits the same wall independently.
	var fixture := _reg.spawn(T_LIGHT, Vector3(1, 0, 1)) as LightToggleScript
	var fx_stock := _reg.charges().remaining(fixture.entity_id, T_LIGHT)
	for i in range(fx_stock):
		assert_true(fixture.toggle(), "E07-S5: fixture interact %d succeeds" % i)
	assert_false(fixture.toggle(), "E07-S5: an exhausted fixture refuses to toggle")


func test_charges_dual_model_world_vs_carried() -> void:
	# ① The model table itself. Getting this backwards is a real bug in BOTH
	#    directions, so it is asserted directly rather than inferred.
	assert_eq(ChargesScript.model_for(T_DECOY), ChargesScript.MODEL_CARRIED,
		"E07-S5: DECOY is a BACKPACK pool (per type)")
	assert_eq(ChargesScript.model_for(T_SMOKE), ChargesScript.MODEL_CARRIED,
		"E07-S5: SMOKE is a BACKPACK pool (per type)")
	assert_eq(ChargesScript.model_for(T_LIGHT), ChargesScript.MODEL_WORLD,
		"E07-S5: LIGHT_TOGGLE charges belong to the WORLD OBJECT")
	assert_eq(ChargesScript.model_for(T_TRAP), ChargesScript.MODEL_WORLD,
		"E07-S5: TRAP charges belong to the WORLD OBJECT")

	# ② WORLD: two fixtures are two independent ledgers.
	var a := _reg.spawn(T_LIGHT, Vector3(0, 0, 0)) as LightToggleScript
	var b := _reg.spawn(T_LIGHT, Vector3(9, 0, 0)) as LightToggleScript
	var a0 := _reg.charges().remaining(a.entity_id, T_LIGHT)
	var b0 := _reg.charges().remaining(b.entity_id, T_LIGHT)
	a.toggle()
	assert_eq(_reg.charges().remaining(a.entity_id, T_LIGHT), a0 - 1,
		"E07-S5/WORLD: interacting with fixture A spends A's charge")
	assert_eq(_reg.charges().remaining(b.entity_id, T_LIGHT), b0,
		"E07-S5/WORLD: fixture B must be untouched (a shared pool would lock the level)")

	# ③ CARRIED: two pebbles draw from ONE pool, because the pool is the player's.
	var p := _reg.spawn(T_DECOY, Vector3(0, 0, 0)) as DecoyScript
	var q := _reg.spawn(T_DECOY, Vector3(4, 0, 0)) as DecoyScript
	var pool0 := _reg.charges().remaining(p.entity_id, T_DECOY)
	p.throw(Vector3(1, 0, 1), "STONE")
	assert_eq(_reg.charges().remaining(q.entity_id, T_DECOY), pool0 - 1,
		"E07-S5/CARRIED: throwing pebble P must also decrement pebble Q's count")
	assert_eq(_reg.charges().remaining(p.entity_id, T_DECOY),
		_reg.charges().remaining(q.entity_id, T_DECOY),
		"E07-S5/CARRIED: a per-entity decoy ledger would make the backpack infinite")

	# ④ The MVP economy band. A "just bump it to 10" edit must go red here.
	for type in [T_DECOY, T_LIGHT, T_TRAP, T_SMOKE]:
		var initial: int = ChargesScript.DEFAULT_CHARGES[type]
		assert_between(initial, ChargesScript.CHARGES_MIN, ChargesScript.CHARGES_MAX,
			"E07-S5: initial charges must stay in the GDD band 2-3 (type %d)" % type)


func test_charges_snapshot_matches_save_contract() -> void:
	# E07-S5 exposes the SAV-S1 CONTRACT SHAPE only; SaveManager is NOT modified.
	assert_true(SaveManagerScript.SLOT_FIELD_ORDER.has("interactable_charges"),
		"E07-S5/SAV-S1: the save field is already frozen in SLOT_FIELD_ORDER")

	var fixture := _reg.spawn(T_LIGHT, Vector3(0, 0, 0)) as LightToggleScript
	var decoy := _reg.spawn(T_DECOY, Vector3(0, 0, 0)) as DecoyScript
	fixture.toggle()
	decoy.throw(Vector3(2, 0, 2), "STONE")

	var snap := _reg.snapshot_charges()
	# Dictionary[int,int] — every key AND value is an int, or SaveManager's
	# _norm_int_int round-trip would silently reshape the slot.
	for key in snap.keys():
		assert_eq(typeof(key), TYPE_INT, "SAV-S1: snapshot keys must be ints")
		assert_eq(typeof(snap[key]), TYPE_INT, "SAV-S1: snapshot values must be ints")

	# Carried pools ride synthetic NEGATIVE ids; level entity ids are positive,
	# so the two id spaces can never collide inside one dictionary.
	var decoy_pool := ChargesScript.pool_id_for(T_DECOY)
	assert_eq(decoy_pool, -100, "SAV-S1: the DECOY pool id is -100")
	assert_true(snap.has(decoy_pool), "SAV-S1: the carried pool is persisted")
	assert_true(snap.has(fixture.entity_id), "SAV-S1: the world row is persisted")
	assert_gt(fixture.entity_id, 0, "SAV-S1: level entity ids must stay positive")

	# Round-trip through a fresh ledger.
	var restored := ChargesScript.new()
	restored.restore(snap)
	assert_eq(restored.remaining(fixture.entity_id, T_LIGHT),
		_reg.charges().remaining(fixture.entity_id, T_LIGHT),
		"SAV-S1: a world row survives the round-trip")
	assert_eq(restored.remaining(decoy.entity_id, T_DECOY),
		_reg.charges().remaining(decoy.entity_id, T_DECOY),
		"SAV-S1: a carried pool survives the round-trip")


# --- E07-S7 -------------------------------------------------------------------
func test_registry_releases_all_instances_on_level_unload() -> void:
	var ids: Array[int] = []
	for type in [T_DECOY, T_LIGHT, T_TRAP, T_SMOKE]:
		var e := _reg.spawn(type, Vector3.ZERO)
		assert_not_null(e, "E07-S7: every InteractableType must be spawnable")
		ids.append(e.entity_id)
	assert_eq(_reg.live_count(), 4, "E07-S7: four live instances")
	assert_eq(_reg.leaked_count(), 0, "E07-S7: nothing leaked while live")

	# Hold a WEAK reference so we can prove the object was actually FREED, not
	# merely forgotten by our own bookkeeping. This is the assertion that makes
	# "interactables can never orphan" falsifiable.
	var probe: InteractableEntity = _reg.get_entity(ids[0])
	assert_gte(_reg.reference_count_of(ids[0]), 2,
		"E07-S7: the registry AND this test both hold a real reference")
	assert_eq(_reg.reference_count_of(999), 0,
		"E07-S7: an unknown id reports zero references, not a crash")
	var weak := weakref(probe)
	probe = null

	var released := _reg.unload_level()
	assert_eq(released, 4, "E07-S7: level unload releases every live instance")
	assert_eq(_reg.live_count(), 0, "E07-S7: nothing survives the unload")
	assert_eq(_reg.leaked_count(), 0, "E07-S7: spawned == released after unload")
	assert_null(weak.get_ref(),
		"E07-S7: the entity is reference-freed on unload (RefCounted can never orphan)")

	# World rows die WITH the level; the player's backpack deliberately does not.
	assert_eq(_reg.charges().world_row_count(), 0,
		"E07-S7: world charge rows are cleared on unload")
	assert_eq(_reg.charges().remaining(ChargesScript.pool_id_for(T_DECOY), T_DECOY),
		ChargesScript.DEFAULT_CHARGES[T_DECOY],
		"E07-S7: walking through a door must not confiscate the backpack")

	# Despawning one instance is the same contract at single-object scale.
	var solo := _reg.spawn(T_TRAP, Vector3.ZERO)
	var solo_id := solo.entity_id
	solo = null
	assert_true(_reg.despawn(solo_id), "E07-S7: despawn retires a live instance")
	assert_false(_reg.despawn(solo_id), "E07-S7: a double despawn is a no-op, not a crash")
	assert_eq(_reg.live_count(), 0, "E07-S7: despawn removed the instance")


# --- E07-S8 -------------------------------------------------------------------
func test_interactable_budget_scans_are_warn_only() -> void:
	var bc := BudgetChecks.new()

	# ① The repo as it stands is CLEAN for both new checks.
	var warns := bc.run("res://")
	assert_false(warns.has("no-orphan-interactables"),
		"E07-S7: the real interactable layer must scan clean (all RefCounted)")
	assert_false(warns.has("interactable-instance-cap"),
		"E07-S8: no scene may declare more interactables than the cap")

	# ② E07-S8 requires that adding DECOY/LIGHT_TOGGLE does not BREAK the
	#    pre-existing budgets. R-02 is a static scene scan; G-02 is a runtime
	#    assertion owned by test_sound_propagation.gd. Neither may regress.
	assert_false(warns.has("R-02"),
		"E07-S8: adding interactables must not break the R-02 dynamic-light scan")
	assert_eq(SoundPropagatorScript.RING_CAP, 8,
		"E07-S8/G-02: the sound ring FIFO cap is unchanged at 8")
	assert_eq(DecoyScript.nominal_radius(), SoundPropagatorScript.DECOY_RADIUS,
		"E07-S8/G-02: a decoy ring uses the E06 radius, so it counts against G-02")
	assert_lte(RegistryScript.INSTANCE_CAP, BudgetChecks.LIGHT_BUDGET_TIER2,
		"E07-S8/R-02: the instance cap must stay inside the Tier2 light budget")

	# ③ REVERSE assertions (N-11/N-12): a scanner that can never warn is a
	#    scanner that rots green. Inject REAL violations and prove it fires.
	assert_true(bc.scan_interactable_base("Node3D").has("no-orphan-interactables"),
		"E07-S7 reverse: a Node-based interactable MUST emit [WARN]")
	assert_false(bc.scan_interactable_base("RefCounted").has("no-orphan-interactables"),
		"E07-S7 reverse: RefCounted is the legal base and must NOT warn")
	var over_cap := bc.scan_interactable_count(RegistryScript.INSTANCE_CAP + 1)
	assert_true(over_cap.has("interactable-instance-cap"),
		"E07-S8 reverse: exceeding the cap MUST emit [WARN]")
	var at_cap := bc.scan_interactable_count(RegistryScript.INSTANCE_CAP)
	assert_false(at_cap.has("interactable-instance-cap"),
		"E07-S8 reverse: exactly AT the cap is legal and must NOT warn")

	# ④ The same two violations through the REAL run() path, via an isolated
	#    scan root (never the repo).
	var orphan_root := _write_scan_fixture("orphan_viol.tscn", 1)
	if orphan_root != "":
		assert_true(bc.run(orphan_root).has("no-orphan-interactables"),
			"E07-S7 reverse: a scene that attaches an interactable script MUST warn")
	var cap_root := _write_scan_fixture("cap_viol.tscn", RegistryScript.INSTANCE_CAP + 1)
	if cap_root != "":
		assert_true(bc.run(cap_root).has("interactable-instance-cap"),
			"E07-S8 reverse: a scene over the cap MUST warn")

	# ⑤ WARN-ONLY means WARN-ONLY. Adding two checks must not have touched the
	#    exit contract: budget_assert.gd still quits 0 for every outcome.
	#    (The runtime proof that no N-7 token is ever PRINTED already lives in
	#    test_budget_assert.gd::test_budget_assert_is_warn_only, which executes
	#    the script headless — it is not duplicated here.)
	var ba: String = FileAccess.get_file_as_string("res://tests/ci/budget_assert.gd")
	assert_true("const EXIT_OK := 0" in ba,
		"E07-S7/S8: the WARN-ONLY exit code must remain 0")
	assert_true("quit(EXIT_OK)" in ba,
		"E07-S7/S8: budget_assert must still take the single unconditional exit path")
	assert_false("EXIT_FAIL" in ba,
		"E07-S7/S8: the new checks must not have introduced a failing exit path")


## Write a synthetic scene that attaches `count` interactable scripts, into an
## isolated user:// scan root. Returns "" when user:// is unavailable, so the
## caller degrades to the direct-helper assertions instead of failing on I/O.
func _write_scan_fixture(file_name: String, count: int) -> String:
	var path := TEST_DIR.path_join(file_name)
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return ""
	var txt := "[gd_scene format=3]\n\n"
	for i in range(count):
		txt += "[ext_resource type=\"Script\" path=\"res://src/game/interactables/decoy_entity.gd\" id=\"%d\"]\n" % (i + 1)
	txt += "\n[node name=\"Root\" type=\"Node3D\"]\n"
	fa.store_string(txt)
	fa.close()
	return TEST_DIR + "/"
