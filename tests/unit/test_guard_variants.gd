# tests/unit/test_guard_variants.gd
# GUT tests for E08 guard variants — Sprint 3, Batch A.
#
# Story coverage:
#   E08-S7  hound / sentinel parameter overrides (KV/KS, hearing reach, cone
#           geometry, dark-vision floor)
#   E08-S9  variant instantiation bound to the entity-inventory type field, and
#           G-01 guard-budget accounting
#   E08-S10 merged FSM verification: the locked threshold contract
#           (THR_SUSP=25 / THR_ALERT=60 / THR_RETURN=10 / DECISION_HZ=10) must
#           survive every overlay — FLAG-B (sprint2-stories.md §5)
#
# ── ANTI-ROT DISCIPLINE (why almost every test here is doubled) ──────────────
# A parameter overlay is the single easiest thing in this codebase to break
# silently. If `_params.kv` ever stopped being read and the code fell back to
# the class constant, EVERY Sprint 1/2 test would stay green — they all describe
# a standard guard — and the variants would simply stop existing. Nothing would
# go red until someone played a hound level and noticed it behaved like a guard.
#
# So the variant assertions here are MIRRORED: each one runs the same scenario
# on a standard brain and on a variant brain, pins BOTH to their own predicted
# numbers, and then asserts the two DIFFER. A silent fallback to the class
# constant collapses the variant onto the standard value and trips the mirror.
# The `_mirror_*` helpers and the "standard reads X, variant reads Y" assertion
# pairs are that lock — please keep both halves when editing.
#
# The second lock is structural: test_overlay_cannot_express_a_threshold()
# asserts GuardVariantParams has NO field capable of holding a threshold. That
# is the FLAG-B mitigation stated as an assertion rather than as a comment.
#
# Node discipline: GuardBrain is a Node but is never added to the scene tree —
# every tick is driven manually through tick_real()/_decide(), exactly as
# test_patrol_ai.gd does, so timing is deterministic and _ready() (which would
# reach for the SaveManager autoload) never runs. Brains made by hand are
# autofree()'d; brains made by GuardSpawner are owned by the spawner and
# released through despawn_all() in after_each — never both, or it is a double
# free.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const GuardBrain = preload("res://src/game/patrol_ai.gd")
const VariantParams = preload("res://src/game/guard_variant_params.gd")
const Spawner = preload("res://src/game/guard_spawner.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const SoundPropagator = preload("res://src/game/sound_propagation.gd")
const VisionConeScript = preload("res://src/game/vision_cone.gd")
const LightModelScript = preload("res://src/game/light_model.gd")

var _bus: EventBus
var _spawner: Spawner


func before_each() -> void:
	_bus = EventBus.new()
	autofree(_bus)
	_spawner = Spawner.new()


func after_each() -> void:
	# The spawner owns every brain it made; free them through it exactly once.
	if _spawner != null:
		_spawner.despawn_all()
	_spawner = null
	_bus = null


# ---- helpers ---------------------------------------------------------------
## A hand-made brain of `variant`, wired to the bus, autofree'd, NOT in a tree.
func _brain_of(variant: int, guard_id: int = 1) -> GuardBrain:
	var b: GuardBrain = GuardBrain.new()
	autofree(b)
	b.guard_id = guard_id
	b.set_event_bus(_bus)
	b.set_variant_params(VariantParams.for_variant(variant))
	return b


## Drive n fixed decision steps at exactly TICK_DT (same helper shape as
## test_patrol_ai.gd::_tick, so the two files read alike).
func _tick(brain: GuardBrain, n: int, vis: float) -> void:
	for i in range(n):
		brain._pending_vision = vis
		brain._decide(GuardBrain.TICK_DT)


## Attach a SoundPropagator so suspicion_from_distance() is available, and park
## the guard at the origin so a sound placed on +Z reads distance in metres.
func _wire_sound(brain: GuardBrain) -> SoundPropagator:
	var sound := SoundPropagator.new()
	autofree(sound)
	brain.set_transform_state(Vector3.ZERO, 0.0)
	brain.set_sound_system(sound)
	return sound


## Feed one sound event straight into the consumer. `addressed` controls whether
## E06's radius filter named this guard — the hound's whole extra reach lives in
## the `false` case.
func _emit_sound(brain: GuardBrain, dist_m: float, radius: float, addressed: bool) -> void:
	brain._on_sound_emitted({
		"origin": Vector3(0, 0, dist_m),
		"radius": radius,
		"intensity": 1.0,
		"source": SoundPropagator.SOURCE_FOOTFALL,
		"target_guard_ids": [brain.guard_id] if addressed else [],
	})


## A cone carrying `variant`'s overlay (or the bare STANDARD cone when
## `variant` is -1, i.e. no overlay attached at all).
func _cone_of(variant: int, light: LightModelScript = null) -> VisionCone:
	var c: VisionCone = VisionConeScript.new()
	autofree(c)
	if light != null:
		c.set_light_model(light)
	if variant >= 0:
		c.set_variant_params(VariantParams.for_variant(variant))
	c.set_observer(Vector3.ZERO, Vector3.FORWARD)
	return c


## Point at `dist` metres and `angle_deg` off the observer's forward axis.
## Forward is Vector3.FORWARD = (0,0,-1); +angle swings toward +X.
func _point_at(dist: float, angle_deg: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(dist * sin(a), 0.0, -dist * cos(a))


# =============================================================================
# DRIFT LOCKS — the STANDARD mirrors in GuardVariantParams must equal the
# constants they mirror. GuardVariantParams is deliberately dependency-free
# (pure data, no preloads, no cycles), and the price of that is duplicated
# literals. These assertions are the receipt: retune an owner without retuning
# its mirror and CI goes red instead of the overlay quietly changing standard
# guard behaviour.
# =============================================================================
func test_standard_params_mirror_guard_brain_constants() -> void:
	assert_almost_eq(VariantParams.STD_KV, GuardBrain.KV, 0.0001,
		"GuardVariantParams.STD_KV must mirror GuardBrain.KV — a standard guard " +
		"built through the overlay has to be the SAME guard")
	assert_almost_eq(VariantParams.STD_KS, GuardBrain.KS, 0.0001,
		"GuardVariantParams.STD_KS must mirror GuardBrain.KS")

	# And the object built from those mirrors really is the standard guard.
	var std := VariantParams.standard()
	assert_almost_eq(std.kv, GuardBrain.KV, 0.0001, "standard() must carry GuardBrain.KV")
	assert_almost_eq(std.ks, GuardBrain.KS, 0.0001, "standard() must carry GuardBrain.KS")
	assert_true(std.is_standard(), "standard() must report the STANDARD variant")


func test_standard_params_mirror_vision_cone_constants() -> void:
	assert_almost_eq(VariantParams.STD_CONE_RANGE_M, VisionConeScript.RANGE, 0.0001,
		"STD_CONE_RANGE_M must mirror VisionCone.RANGE (14m)")
	assert_almost_eq(VariantParams.STD_CONE_ANGLE_DEG, VisionConeScript.HALF_ANGLE_DEG, 0.0001,
		"STD_CONE_ANGLE_DEG must mirror VisionCone.HALF_ANGLE_DEG — and both are " +
		"HALF angles; a full-angle reading here would double every cone")


func test_standard_light_floor_matches_light_model() -> void:
	# ★ The value GDD §9.2's table prints as 0.0 and §9.3's prose calls
	# "标准 0.20 等效地板". 0.20 is the reading this codebase implements, because
	# it is the only one that leaves standard guards unchanged. See the long
	# comment on STD_VISION_LIGHT_FLOOR.
	assert_almost_eq(VariantParams.STD_VISION_LIGHT_FLOOR, LightModelScript.L_DARK, 0.0001,
		"STD_VISION_LIGHT_FLOOR must mirror LightModel.L_DARK (0.20)")
	assert_almost_eq(VariantParams.STD_LIGHT_BRIGHT, LightModelScript.L_BRIGHT, 0.0001,
		"STD_LIGHT_BRIGHT must mirror LightModel.L_BRIGHT (0.60)")

	# The real proof: across the whole light range, the overlay's generalised
	# formula and LightModel's own must agree to the last digit for a STANDARD
	# guard. If they ever diverge, every standard guard silently gains or loses
	# dark vision — the exact regression the 0.0-vs-0.20 reading would cause.
	var lm := LightModelScript.new()
	var std := VariantParams.standard()
	for level in [0.0, 0.05, 0.1, 0.19, 0.2, 0.21, 0.35, 0.5, 0.59, 0.6, 0.75, 1.0]:
		assert_almost_eq(std.light_sensitivity(level), lm.light_sensitivity(level), 0.0001,
			"STANDARD overlay sensitivity must equal LightModel.light_sensitivity at L=%.2f"
				% level)


# =============================================================================
# E08-S7 · hound KV / KS override
# =============================================================================
func test_hound_kv_override_halves_vision_gain() -> void:
	var std := _brain_of(VariantParams.Variant.STANDARD, 1)
	var hound := _brain_of(VariantParams.Variant.SOUND_HOUND, 2)

	# Premise guard rail: if the two gains were ever retuned to the same number
	# the mirror below would pass for the wrong reason, so say so out loud.
	assert_ne(VariantParams.HOUND_KV, VariantParams.STD_KV,
		"premise: the hound's vision gain must actually differ from STANDARD, " +
		"otherwise the mirror assertion below is not a lock")

	_tick(std, 1, 1.0)
	_tick(hound, 1, 1.0)

	var want_std: float = GuardBrain.KV * 1.0 * GuardBrain.TICK_DT          # 3.5
	var want_hound: float = VariantParams.HOUND_KV * 1.0 * GuardBrain.TICK_DT # 1.5
	assert_almost_eq(std.suspicion, want_std, 0.0001,
		"a STANDARD guard must still gain KV*dt (%.2f) per fully-visible tick" % want_std)
	assert_almost_eq(hound.suspicion, want_hound, 0.0001,
		"a hound must gain HOUND_KV*dt (%.2f), not KV*dt (%.2f)" % [want_hound, want_std])

	# ★ MIRROR: a silent fallback to the class constant makes these equal.
	assert_ne(hound.suspicion, std.suspicion,
		"hound and standard vision gain must DIFFER. If they are equal, " +
		"_params.kv is not being read and the overlay is decorative.")
	assert_lt(hound.suspicion, std.suspicion,
		"the hound is the LESS visual guard — its gain must be the smaller one")


func test_hound_ks_override_doubles_sound_gain() -> void:
	var std := _brain_of(VariantParams.Variant.STANDARD, 1)
	var hound := _brain_of(VariantParams.Variant.SOUND_HOUND, 2)
	_wire_sound(std)
	_wire_sound(hound)

	assert_ne(VariantParams.HOUND_KS, VariantParams.STD_KS,
		"premise: the hound's sound gain must differ from STANDARD")

	# One addressed event at 4m inside an 8m radius.
	_emit_sound(std, 4.0, 8.0, true)
	_emit_sound(hound, 4.0, 8.0, true)
	_tick(std, 1, 0.0)
	_tick(hound, 1, 0.0)

	# STANDARD: falloff = 1 - 4/8 = 0.5  -> KS(15) * 0.5 = 7.5
	assert_almost_eq(std.suspicion, GuardBrain.KS * 0.5, 0.0001,
		"a STANDARD guard must gain KS*falloff = %.2f" % (GuardBrain.KS * 0.5))
	# HOUND: radius x1.6 = 12.8 -> falloff = 1 - 4/12.8 = 0.6875 -> 30 * 0.6875
	var hound_falloff: float = 1.0 - (4.0 / (8.0 * VariantParams.HOUND_PERCEPTION_RADIUS_MULT))
	assert_almost_eq(hound.suspicion, VariantParams.HOUND_KS * hound_falloff, 0.0001,
		"a hound must gain HOUND_KS * the x1.6-widened falloff (%.4f)"
			% (VariantParams.HOUND_KS * hound_falloff))

	# ★ MIRROR + the design intent: the hound is the ear.
	assert_gt(hound.suspicion, std.suspicion,
		"the hound must be strictly MORE alarmed by the same sound. Equal values " +
		"mean _params.ks / perception_radius_mult are not reaching the tick.")


# =============================================================================
# E08-S7 · hound hearing reach (perception_radius_mult = 1.6)
# =============================================================================
func test_hound_hears_beyond_the_event_radius() -> void:
	# ★★ The sharpest reverse assertion in this file. ★★
	# The sound sits at 10m with an 8m radius, and E06's filter does NOT name
	# either guard (that is what `addressed = false` encodes). A standard guard
	# must hear NOTHING — it is outside the circle. A hound's x1.6 reach makes
	# the effective radius 12.8m, so it must hear it.
	#
	# If perception_radius_mult were dropped, the hound would take the standard
	# early-out and this test's two halves would collapse onto each other. There
	# is no way to satisfy both assertions without the multiplier being live.
	var std := _brain_of(VariantParams.Variant.STANDARD, 1)
	var hound := _brain_of(VariantParams.Variant.SOUND_HOUND, 2)
	_wire_sound(std)
	_wire_sound(hound)

	# Start above zero so the "heard nothing" case is visible as plain decay
	# rather than being hidden by the [0,100] floor.
	std.suspicion = 50.0
	hound.suspicion = 50.0

	var radius := 8.0
	var dist := 10.0
	assert_gt(dist, radius,
		"premise: the sound must be OUTSIDE the nominal radius, or the hound's " +
		"extra reach is not what is being measured")
	assert_lt(dist, radius * VariantParams.HOUND_PERCEPTION_RADIUS_MULT,
		"premise: and INSIDE the hound's widened radius")

	_emit_sound(std, dist, radius, false)
	_emit_sound(hound, dist, radius, false)
	_tick(std, 1, 0.0)
	_tick(hound, 1, 0.0)

	# STANDARD heard nothing -> unstimulated tick -> plain decay.
	assert_almost_eq(std.suspicion, 50.0 - GuardBrain.DECAY * GuardBrain.TICK_DT, 0.0001,
		"a STANDARD guard must not hear a sound it was never addressed by; the " +
		"tick must decay as if silent")
	# HOUND heard it -> stimulated tick -> no decay, plus KS * widened falloff.
	var eff_r: float = radius * VariantParams.HOUND_PERCEPTION_RADIUS_MULT
	var expect_hound: float = 50.0 + VariantParams.HOUND_KS * (1.0 - dist / eff_r)
	assert_almost_eq(hound.suspicion, expect_hound, 0.0001,
		"a hound must hear out to radius x%.1f (expected %.4f)"
			% [VariantParams.HOUND_PERCEPTION_RADIUS_MULT, expect_hound])
	assert_gt(hound.suspicion, 50.0,
		"and it must be a NET RISE — a hound that only avoided decay has not heard anything")


func test_standard_guard_still_ignores_sounds_addressed_to_others() -> void:
	# Regression rail for the change above: widening the intake gate must not
	# turn every guard into an eavesdropper. This is the Sprint 1 contract
	# (test_patrol_ai.gd::test_suspicion_accumulates_from_sound_event case (d))
	# restated for the variant-aware code path.
	var std := _brain_of(VariantParams.Variant.STANDARD, 1)
	_wire_sound(std)
	std.suspicion = 0.0
	std._on_sound_emitted({
		"origin": Vector3.ZERO, "radius": 10.0, "intensity": 1.0,
		"target_guard_ids": [std.guard_id + 99],
	})
	_tick(std, 1, 0.0)
	assert_almost_eq(std.suspicion, 0.0, 0.0001,
		"a STANDARD guard (mult 1.0) must keep the original early-out for sounds " +
		"addressed to other guards")


# =============================================================================
# E08-S7 · hound cone geometry (11m / 30deg)
# =============================================================================
func test_hound_cone_range_is_shorter() -> void:
	var std_cone := _cone_of(VariantParams.Variant.STANDARD)
	var hound_cone := _cone_of(VariantParams.Variant.SOUND_HOUND)

	assert_almost_eq(hound_cone.effective_range(), VariantParams.HOUND_CONE_RANGE_M, 0.0001,
		"the hound cone must report an 11m range")
	assert_almost_eq(std_cone.effective_range(), VisionConeScript.RANGE, 0.0001,
		"the standard cone must still report 14m")

	# A target between the two ranges separates them behaviourally, not just by
	# what the accessor claims.
	var t := _point_at(12.5, 0.0)
	assert_gt(12.5, VariantParams.HOUND_CONE_RANGE_M, "premise: outside the hound cone")
	assert_lt(12.5, VisionConeScript.RANGE, "premise: inside the standard cone")

	assert_almost_eq(std_cone.compute_visibility(t), 1.0, 0.0001,
		"a standard guard must see a target at 12.5m")
	assert_almost_eq(hound_cone.compute_visibility(t), 0.0, 0.0001,
		"a hound must NOT see a target at 12.5m — its cone stops at 11m")


func test_hound_cone_angle_is_tighter() -> void:
	var std_cone := _cone_of(VariantParams.Variant.STANDARD)
	var hound_cone := _cone_of(VariantParams.Variant.SOUND_HOUND)

	assert_almost_eq(hound_cone.effective_half_angle_deg(), VariantParams.HOUND_CONE_ANGLE_DEG,
		0.0001, "the hound cone must report a 30deg half-angle")

	# 32deg sits between the hound's 30 and the standard's 35.
	var t := _point_at(5.0, 32.0)
	assert_almost_eq(std_cone.compute_visibility(t), 1.0, 0.0001,
		"32deg is inside the standard 35deg half-angle")
	assert_almost_eq(hound_cone.compute_visibility(t), 0.0, 0.0001,
		"32deg is outside the hound's 30deg half-angle")

	# The rim tell must move with the cone, or it warns about the wrong place.
	assert_true(hound_cone.is_in_edge_band(_point_at(5.0, 26.0)),
		"26deg must be inside the hound's rim band (30 - 8 = 22 .. 30)")
	assert_false(hound_cone.is_in_edge_band(_point_at(5.0, 34.0)),
		"34deg is outside the hound's cone entirely and must not raise the rim tell")


# =============================================================================
# E08-S7 · sentinel dark-vision floor (vision_light_floor = 0.05)
# =============================================================================
func test_sentinel_sees_in_shadow_where_standard_cannot() -> void:
	var lm := LightModelScript.new()
	lm.add_shadow_box(Vector3(0, 0, -5), 1.0)          # target sits in the dark
	var target := _point_at(5.0, 0.0)
	assert_almost_eq(lm.get_light_level(target), 0.1, 0.0001,
		"premise: the target must be inside a shadow box (L = 0.1)")
	assert_lt(0.1, LightModelScript.L_DARK,
		"premise: and that L must be BELOW the standard dark floor, or a standard " +
		"guard could see it anyway and this test proves nothing")

	var std_cone := _cone_of(VariantParams.Variant.STANDARD, lm)
	var sentinel_cone := _cone_of(VariantParams.Variant.DARK_SENTINEL, lm)

	var std_vis := std_cone.compute_visibility(target)
	var sen_vis := sentinel_cone.compute_visibility(target)

	assert_almost_eq(std_vis, 0.0, 0.0001,
		"a standard guard must be BLIND in shadow (L=0.1 <= L_DARK=0.20) — " +
		"shadow is the core stealth resource")
	# (0.1 - 0.05) / (0.6 - 0.05) = 0.0909...
	var expect: float = (0.1 - VariantParams.SENTINEL_VISION_LIGHT_FLOOR) \
		/ (LightModelScript.L_BRIGHT - VariantParams.SENTINEL_VISION_LIGHT_FLOOR)
	assert_almost_eq(sen_vis, expect, 0.0001,
		"a sentinel must read vis = %.4f in that same shadow" % expect)

	# ★ MIRROR: the mechanic IS the difference. If the floor stopped being
	# applied, sen_vis would collapse to 0.0 and the sentinel would be a guard
	# with a different silhouette and no gameplay identity at all.
	assert_gt(sen_vis, 0.0,
		"the sentinel must see SOMETHING in shadow. A reading of 0 means " +
		"vision_light_floor is not reaching compute_visibility — shadow would " +
		"still be a free safe zone and the whole variant would be inert.")
	assert_ne(sen_vis, std_vis,
		"sentinel and standard visibility in shadow must differ")


func test_sentinel_leaves_every_other_parameter_at_standard() -> void:
	# GDD §9.2: the sentinel row is default in every column but the light floor.
	# Asserted so a future "while we're in here" tweak to the sentinel's gains
	# has to be a deliberate, visible edit.
	var sen := VariantParams.sentinel()
	assert_almost_eq(sen.kv, VariantParams.STD_KV, 0.0001, "sentinel KV stays 35")
	assert_almost_eq(sen.ks, VariantParams.STD_KS, 0.0001, "sentinel KS stays 15")
	assert_almost_eq(sen.perception_radius_mult, VariantParams.STD_PERCEPTION_RADIUS_MULT,
		0.0001, "sentinel hearing reach stays x1.0")
	assert_almost_eq(sen.cone_range_m, VariantParams.STD_CONE_RANGE_M, 0.0001,
		"sentinel cone range stays 14m")
	assert_almost_eq(sen.cone_angle_deg, VariantParams.STD_CONE_ANGLE_DEG, 0.0001,
		"sentinel cone half-angle stays 35deg")
	assert_almost_eq(sen.vision_light_floor, VariantParams.SENTINEL_VISION_LIGHT_FLOOR,
		0.0001, "and the ONE override is the 0.05 dark floor")
	assert_lt(sen.vision_light_floor, VariantParams.STD_VISION_LIGHT_FLOOR,
		"the sentinel's floor must be LOWER than standard — that is what 'dark " +
		"vision' means; a higher floor would make it night-blind")


func test_standard_overlay_is_behaviourally_invisible() -> void:
	# Equivalence lock: attaching an explicit STANDARD overlay must change
	# nothing at all versus attaching no overlay. This is what lets GuardSpawner
	# apply params unconditionally without a special case for standard guards.
	var lm := LightModelScript.new()
	lm.add_shadow_box(Vector3(0, 0, -5), 1.0)
	var bare := _cone_of(-1, lm)                                  # no overlay
	var explicit := _cone_of(VariantParams.Variant.STANDARD, lm)  # STANDARD overlay

	for spec in [[5.0, 0.0], [5.0, 32.0], [12.5, 0.0], [13.9, 10.0], [14.1, 0.0], [3.0, 40.0]]:
		var t := _point_at(float(spec[0]), float(spec[1]))
		assert_almost_eq(explicit.compute_visibility(t), bare.compute_visibility(t), 0.0001,
			"a STANDARD overlay must be a no-op at %.1fm / %.0fdeg" % [spec[0], spec[1]])
		assert_eq(explicit.is_in_edge_band(t), bare.is_in_edge_band(t),
			"...including the rim tell at %.1fm / %.0fdeg" % [spec[0], spec[1]])


# =============================================================================
# E08-S9 · entity-inventory type binding
# =============================================================================
func test_entity_type_field_selects_the_variant() -> void:
	# entity-inventory.md rows 2/3/4. Both the English and the Chinese asset
	# names are accepted, because that sheet prints them in a single cell.
	var cases := {
		"Guard Standard": VariantParams.Variant.STANDARD,
		"GUARD_STANDARD": VariantParams.Variant.STANDARD,
		"守卫·标准": VariantParams.Variant.STANDARD,
		"Hound": VariantParams.Variant.SOUND_HOUND,
		"guard-hound": VariantParams.Variant.SOUND_HOUND,
		"守卫·循声猎犬": VariantParams.Variant.SOUND_HOUND,
		"Sentinel": VariantParams.Variant.DARK_SENTINEL,
		"  DARK_SENTINEL  ": VariantParams.Variant.DARK_SENTINEL,
		"守卫·暗视哨兵": VariantParams.Variant.DARK_SENTINEL,
	}
	for type_field in cases:
		var want: int = cases[type_field]
		assert_eq(VariantParams.variant_for_entity_type(type_field), want,
			"entity type '%s' must bind to variant %d" % [type_field, want])
		assert_true(VariantParams.is_known_entity_type(type_field),
			"entity type '%s' must be recognised" % type_field)


func test_unknown_entity_type_is_recorded_not_swallowed() -> void:
	# ★ ANTI-ROT. A typo'd asset row spawns a perfectly healthy STANDARD guard,
	# so the level runs and nothing crashes — which is exactly how a missing
	# variant hides. The ledger is what makes the miss observable.
	assert_false(VariantParams.is_known_entity_type("SENTINAL"),
		"a misspelled type must NOT be recognised")
	assert_eq(VariantParams.variant_for_entity_type("SENTINAL"),
		VariantParams.VARIANT_UNKNOWN,
		"an unrecognised type must report VARIANT_UNKNOWN, not silently map to STANDARD")

	var brain := _spawner.spawn_from_entity_type("SENTINAL", 7)
	assert_not_null(brain, "an unknown type must still yield a playable guard (no crash)")
	assert_eq(brain.get_variant(), VariantParams.Variant.STANDARD,
		"the fallback must be STANDARD")
	assert_eq(_spawner.unknown_entity_types.size(), 1,
		"and the miss must be RECORDED — a silent fallback is how a variant " +
		"quietly stops existing")
	assert_eq(_spawner.unknown_entity_types[0], "SENTINAL",
		"the ledger must name the offending type field verbatim")

	# A well-formed row must not pollute the ledger.
	_spawner.spawn_from_entity_type("Hound", 8)
	assert_eq(_spawner.unknown_entity_types.size(), 1,
		"a recognised type must not be logged as unknown")


func test_spawned_variant_carries_its_parameters() -> void:
	var hound := _spawner.spawn_from_entity_type("守卫·循声猎犬", 3)
	var sentinel := _spawner.spawn_from_entity_type("Sentinel", 4)
	var std := _spawner.spawn_from_entity_type("Guard Standard", 2)

	assert_eq(hound.get_variant(), VariantParams.Variant.SOUND_HOUND, "row 3 -> hound")
	assert_eq(sentinel.get_variant(), VariantParams.Variant.DARK_SENTINEL, "row 4 -> sentinel")
	assert_eq(std.get_variant(), VariantParams.Variant.STANDARD, "row 2 -> standard")

	# ★ The instantiation must deliver the NUMBERS, not merely an enum tag. A
	# spawner that set `variant` but forgot the params would pass a naive
	# "is it a hound?" test and still behave exactly like a standard guard.
	assert_almost_eq(hound.get_variant_params().kv, VariantParams.HOUND_KV, 0.0001,
		"the spawned hound must carry KV=15, not just the SOUND_HOUND tag")
	assert_almost_eq(hound.get_variant_params().ks, VariantParams.HOUND_KS, 0.0001,
		"the spawned hound must carry KS=30")
	assert_almost_eq(sentinel.get_variant_params().vision_light_floor,
		VariantParams.SENTINEL_VISION_LIGHT_FLOOR, 0.0001,
		"the spawned sentinel must carry the 0.05 dark floor")

	# And it must be observable in behaviour, not only in the field.
	_tick(hound, 1, 1.0)
	_tick(std, 1, 1.0)
	assert_lt(hound.suspicion, std.suspicion,
		"the spawned hound must actually accumulate vision more slowly than the " +
		"spawned standard guard")


func test_spawn_from_inventory_rows() -> void:
	var rows := [
		{"type": "Guard Standard", "guard_id": 1},
		{"type": "Hound", "guard_id": 2},
		{"type": "Sentinel", "guard_id": 3},
		{"type": "Hound"},
	]
	var spawned := _spawner.spawn_from_inventory(rows)
	assert_eq(spawned.size(), 4, "all four inventory rows must spawn")
	assert_eq(_spawner.live_count(), 4, "and all four must count toward G-01")
	assert_eq(spawned[1].guard_id, 2, "an explicit guard_id must be honoured")
	assert_gt(spawned[3].guard_id, 0, "an omitted guard_id must be auto-assigned")
	assert_eq(_spawner.live_count_of_variant(VariantParams.Variant.SOUND_HOUND), 2,
		"per-variant accounting must see both hounds")
	assert_eq(_spawner.unknown_entity_types.size(), 0, "no row here is unknown")


# =============================================================================
# E08-S9 · G-01 guard budget (MVP <= 8 / Tier2 <= 16)
# =============================================================================
func test_guard_budget_mvp_caps_at_eight() -> void:
	_spawner.tier = Spawner.Tier.MVP
	assert_eq(_spawner.budget(), 8, "control-manifest G-01: the MVP cap is 8")

	for i in range(8):
		assert_not_null(_spawner.spawn(VariantParams.Variant.STANDARD),
			"guard #%d must fit inside the MVP budget" % (i + 1))
	assert_eq(_spawner.live_count(), 8, "8 guards must be live")
	assert_false(_spawner.can_spawn(), "the MVP budget must now be full")

	var overflow := _spawner.spawn(VariantParams.Variant.SOUND_HOUND)
	assert_null(overflow,
		"the 9th guard must be REFUSED — G-01 is a cap, not a suggestion")
	assert_eq(_spawner.over_budget_rejections, 1, "and the refusal must be counted")
	assert_eq(_spawner.live_count(), 8, "a refused spawn must not enter the ledger")


func test_guard_budget_tier2_caps_at_sixteen() -> void:
	_spawner.tier = Spawner.Tier.TIER2
	assert_eq(_spawner.budget(), 16, "control-manifest G-01: the Tier2 cap is 16")

	# Variants are Tier2 content (entity-inventory rows 3/4), so fill the tier
	# with them — this is the real shipping shape of a variant level.
	for i in range(16):
		var v: int = VariantParams.Variant.SOUND_HOUND if i % 2 == 0 \
			else VariantParams.Variant.DARK_SENTINEL
		assert_not_null(_spawner.spawn(v), "variant guard #%d must fit Tier2" % (i + 1))
	assert_eq(_spawner.live_count(), 16, "16 variant guards must be live")
	assert_eq(_spawner.live_count_of_variant(VariantParams.Variant.SOUND_HOUND), 8,
		"8 of them are hounds")
	assert_eq(_spawner.live_count_of_variant(VariantParams.Variant.DARK_SENTINEL), 8,
		"8 of them are sentinels")

	assert_null(_spawner.spawn(VariantParams.Variant.STANDARD),
		"the 17th guard must be refused even at Tier2")
	assert_eq(_spawner.over_budget_rejections, 1, "and counted")


func test_despawn_frees_budget_headroom() -> void:
	_spawner.tier = Spawner.Tier.MVP
	var brains: Array = []
	for i in range(8):
		brains.append(_spawner.spawn(VariantParams.Variant.STANDARD))
	assert_false(_spawner.can_spawn(), "full")

	_spawner.despawn(brains[0])
	assert_eq(_spawner.live_count(), 7, "despawn must release a slot")
	assert_true(_spawner.can_spawn(), "and the budget must accept a replacement")
	assert_not_null(_spawner.spawn(VariantParams.Variant.DARK_SENTINEL),
		"the replacement guard must spawn")
	assert_eq(_spawner.over_budget_rejections, 0, "no refusal should have occurred")


func test_guard_budget_warning_surface_actually_fires() -> void:
	# ★ REVERSE ASSERTION for the WARN-ONLY CI scan (tests/ci/budget_assert.gd).
	# A budget scan that can never emit is a scan that rots green: it prints OK
	# forever and nobody notices it stopped measuring. Feed it a real violation
	# and require the warning.
	assert_eq(Spawner.budget_warnings(8, Spawner.Tier.MVP).size(), 0,
		"exactly at the MVP cap must be clean")
	assert_eq(Spawner.budget_warnings(16, Spawner.Tier.TIER2).size(), 0,
		"exactly at the Tier2 cap must be clean")

	var over_mvp := Spawner.budget_warnings(9, Spawner.Tier.MVP)
	assert_eq(over_mvp.size(), 1, "9 guards at MVP must emit exactly one warning")
	assert_eq(over_mvp[0], "guard-instance-budget", "with the G-01 check id")

	var over_t2 := Spawner.budget_warnings(17, Spawner.Tier.TIER2)
	assert_eq(over_t2.size(), 1, "17 guards at Tier2 must emit exactly one warning")

	# The MVP rung must be genuinely stricter, or the two tiers are one tier.
	assert_eq(Spawner.budget_warnings(12, Spawner.Tier.MVP).size(), 1,
		"12 guards breach MVP...")
	assert_eq(Spawner.budget_warnings(12, Spawner.Tier.TIER2).size(), 0,
		"...but are legal at Tier2 — the rungs must not collapse into one")

	assert_lt(Spawner.GUARD_BUDGET_MVP, Spawner.GUARD_BUDGET_TIER2,
		"G-01: the MVP cap must stay below the Tier2 cap")


# =============================================================================
# E08-S10 · merged FSM verification — the threshold contract survives every
#           overlay. This whole section IS the FLAG-B mitigation.
# =============================================================================
func test_overlay_cannot_express_a_threshold() -> void:
	# ★★★ THE STRUCTURAL LOCK ★★★
	# FLAG-B's failure mode is "variant params implemented as runtime-mutable
	# instance constants pollute the locked thresholds". The mitigation is not a
	# careful implementation — it is making the pollution UNREPRESENTABLE. There
	# is no threshold field on the overlay, so no variant can set one, so the
	# contract cannot drift. If someone ever adds one, this goes red immediately
	# and they get to read FLAG-B before proceeding.
	var banned := [
		"thr_susp", "thr_alert", "thr_return", "decision_hz",
		"decay", "grace_rt", "tick_dt", "stim_eps",
	]
	var p := VariantParams.standard()
	var present := PackedStringArray()
	for prop in p.get_property_list():
		present.append(str(prop["name"]).to_lower())
	for field in banned:
		assert_false(present.has(field),
			("GuardVariantParams must NOT own `%s`. Thresholds are a FROZEN " +
			"contract (FLAG-B); putting one on the overlay is how variants " +
			"start rewriting the FSM.") % field)

	# The debug snapshot must not smuggle one in through a side door either.
	var keys: Array = p.to_dict().keys()
	for field in banned:
		assert_false(keys.has(field),
			"to_dict() must not expose `%s` either" % field)


func test_thresholds_identical_across_all_variants() -> void:
	# The merged run: every variant must cross the SAME 25 / 60 / 10 lines.
	var variants := [
		VariantParams.Variant.STANDARD,
		VariantParams.Variant.SOUND_HOUND,
		VariantParams.Variant.DARK_SENTINEL,
	]
	for v in variants:
		var label: String = VariantParams.VARIANT_NAMES[v]

		# Just BELOW THR_SUSP: nobody may transition.
		var b := _brain_of(v, 1)
		b.suspicion = GuardBrain.THR_SUSP - 0.01
		b._step_fsm(0.0, GuardBrain.TICK_DT)
		assert_eq(b.get_state(), EventBus.GuardState.CALM,
			"%s must still be CALM just below THR_SUSP(25)" % label)

		# AT THR_SUSP: everybody transitions.
		b.suspicion = GuardBrain.THR_SUSP
		b._step_fsm(0.0, GuardBrain.TICK_DT)
		assert_eq(b.get_state(), EventBus.GuardState.SUSPICIOUS,
			"%s must reach SUSPICIOUS at exactly THR_SUSP(25)" % label)

		# AT THR_ALERT.
		b.suspicion = GuardBrain.THR_ALERT
		b._step_fsm(0.0, GuardBrain.TICK_DT)
		assert_eq(b.get_state(), EventBus.GuardState.ALERT,
			"%s must reach ALERT at exactly THR_ALERT(60)" % label)

		# Below THR_RETURN, via the only legal downward path.
		b._set_fsm(EventBus.GuardState.SUSPICIOUS)
		b.suspicion = GuardBrain.THR_RETURN - 0.01
		b._step_fsm(0.0, GuardBrain.TICK_DT)
		assert_eq(b.get_state(), EventBus.GuardState.RETURN,
			"%s must fall to RETURN below THR_RETURN(10)" % label)


func test_variant_threshold_values_are_untouched_after_variant_use() -> void:
	# Belt and braces for FLAG-B: exercise all three variants hard, then read
	# the contract back off the class. `const` already guarantees this, which is
	# the point — the assertion documents that the guarantee is structural and
	# will fail loudly the day someone downgrades a const to a var.
	for v in [VariantParams.Variant.STANDARD, VariantParams.Variant.SOUND_HOUND,
			VariantParams.Variant.DARK_SENTINEL]:
		var b := _brain_of(v, 1)
		var s := _wire_sound(b)
		_emit_sound(b, 2.0, 8.0, true)
		_tick(b, 20, 0.8)

	assert_almost_eq(GuardBrain.THR_SUSP, 25.0, 0.0001, "THR_SUSP must still be 25")
	assert_almost_eq(GuardBrain.THR_ALERT, 60.0, 0.0001, "THR_ALERT must still be 60")
	assert_almost_eq(GuardBrain.THR_RETURN, 10.0, 0.0001, "THR_RETURN must still be 10")
	assert_almost_eq(GuardBrain.DECISION_HZ, 10.0, 0.0001, "DECISION_HZ must still be 10")
	assert_almost_eq(GuardBrain.DECAY, 8.0, 0.0001, "DECAY must still be 8")
	assert_almost_eq(GuardBrain.GRACE_RT, 1.2, 0.0001, "GRACE_RT must still be 1.2s")
	# The overlay's own standard mirrors must not have moved either.
	assert_almost_eq(VariantParams.standard().kv, GuardBrain.KV, 0.0001,
		"a freshly built STANDARD overlay must still equal GuardBrain.KV — " +
		"variant construction must never mutate shared state")


func test_variants_respect_the_10hz_decision_ceiling() -> void:
	# G-04 / control-manifest: parameterising the GAINS must not parameterise the
	# CLOCK. 2.0s of real time is 10..20 decisions for every variant.
	for v in [VariantParams.Variant.STANDARD, VariantParams.Variant.SOUND_HOUND,
			VariantParams.Variant.DARK_SENTINEL]:
		var b := _brain_of(v, 1)
		for i in range(120):
			b.tick_real(1.0 / 60.0)
		assert_between(b.decision_count, 10, 20,
			"%s must run 10..20 decisions in 2.0s (G-04, got %d)"
				% [VariantParams.VARIANT_NAMES[v], b.decision_count])


func test_variant_decay_and_grace_are_not_overridden() -> void:
	# The hound's gains change; its FORGETTING must not. A variant that decayed
	# differently would need its own threshold tuning and FLAG-B would be back.
	var std := _brain_of(VariantParams.Variant.STANDARD, 1)
	var hound := _brain_of(VariantParams.Variant.SOUND_HOUND, 2)
	std.suspicion = 50.0
	hound.suspicion = 50.0
	_tick(std, 10, 0.0)
	_tick(hound, 10, 0.0)
	var expect: float = 50.0 - GuardBrain.DECAY * GuardBrain.TICK_DT * 10.0
	assert_almost_eq(std.suspicion, expect, 0.0001, "standard decay is DECAY*dt per tick")
	assert_almost_eq(hound.suspicion, expect, 0.0001,
		"a hound must decay at exactly the same rate — decay is NOT a variant parameter")
	assert_almost_eq(hound.suspicion, std.suspicion, 0.0001,
		"and therefore the two must land on the same value")


func test_variants_emit_no_new_signals() -> void:
	# GDD §9.4 "零新事件" / E01-S9 vocabulary freeze. A hound must communicate
	# through exactly the same four signals a standard guard uses.
	var fsm_events: Array = []
	var sus_events: Array = []
	_bus.guard_fsm_changed.connect(func(gid, o, n): fsm_events.append([gid, o, n]))
	_bus.suspicion_changed.connect(func(gid, val, tier): sus_events.append([gid, val, tier]))

	var hound := _brain_of(VariantParams.Variant.SOUND_HOUND, 5)
	hound.suspicion = GuardBrain.THR_SUSP
	_tick(hound, 1, 1.0)

	assert_gt(sus_events.size(), 0,
		"a hound must report through the EXISTING suspicion_changed signal")
	assert_eq(sus_events[-1][0], 5, "carrying its own guard_id")
	assert_gt(fsm_events.size(), 0,
		"and change state through the EXISTING guard_fsm_changed signal")

	# The variant must NOT have leaked into the shared event vocabulary.
	assert_false(_bus.has_signal("guard_spawned"),
		"Sprint 3 Batch A adds ZERO event vocabulary — `guard_spawned` is parked " +
		"in GDD §9.1 pending an E01-S9 decision and must not appear here")
	assert_false(_bus.has_signal("guard_variant_changed"),
		"no variant-specific signal may be introduced")
