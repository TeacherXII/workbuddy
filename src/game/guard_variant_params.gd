class_name GuardVariantParams
extends RefCounted

# ASHEN STEP — Sprint 3 Batch A. E08-S7 guard variant parameter object.
#
# Stories: E08-S7 (hound / sentinel parameter overrides) · E08-S9 (entity-type
#          binding, consumed by GuardSpawner) · E08-S10 (threshold contract must
#          survive the overlay).
#
# ★★★ WHY THIS CLASS EXISTS AT ALL — FLAG-B (sprint2-stories.md §5, 中-高) ★★★
# The obvious implementation of "variant parameter override" is to make
# GuardBrain's frozen constants (KV / KS / THR_SUSP / THR_ALERT / THR_RETURN /
# DECISION_HZ) into runtime-mutable instance vars and let each variant rewrite
# them. That is EXACTLY the failure FLAG-B names: the moment KV stops being a
# `const`, every Sprint 1 threshold assertion that reads `GuardBrain.THR_SUSP`
# is reading a value that some other guard may already have rewritten, and the
# locked 25/60/10/10Hz contract silently becomes per-instance mush.
#
# So: variants NEVER touch a class constant. A guard carries an immutable-by-
# convention parameter OBJECT; GuardBrain reads its tunables from that object,
# and the class constants stay frozen as the STANDARD defaults. The thresholds
# are deliberately NOT fields here — there is no field to override, so the
# contract cannot be polluted even by accident. That absence is the mitigation.
#
# Dependency shape: this file preloads / references NOTHING. It is pure data, so
# there is no cycle with patrol_ai.gd (which references GuardVariantParams) and
# no load-order hazard. The price is that the STANDARD defaults below are
# LITERAL MIRRORS of constants owned elsewhere; every mirror is drift-locked by
# an assertion in tests/unit/test_guard_variants.gd, so a divergence goes red
# instead of rotting green.
#
# Authority: design/gdd/systems/patrol-ai.md §9 (§9.1 overlay mechanism, §9.2
# parameter table, §9.3 behavioural semantics, §9.4 boundaries) + architecture
# §3.4 (variant parameter override, no new system) + control-manifest G-01/G-04.


# ── Variant vocabulary (GDD §9.1 `enum GuardVariant`) ────────────────────────
# INTERNAL to E08. This is NOT an EventBus value domain and MUST NOT become one
# without an E01-S9 vocabulary decision — Sprint 3 Batch A ships ZERO new event
# vocabulary (GDD §9.4 "零新事件").
enum Variant {
	STANDARD = 0,
	SOUND_HOUND = 1,
	DARK_SENTINEL = 2,
}

const VARIANT_NAMES := {
	Variant.STANDARD: "STANDARD",
	Variant.SOUND_HOUND: "SOUND_HOUND",
	Variant.DARK_SENTINEL: "DARK_SENTINEL",
}


# ── STANDARD defaults — literal mirrors, drift-locked by tests ───────────────
# Each line names the constant it mirrors. test_guard_variants.gd asserts every
# pair is equal, so retuning the owner without retuning the mirror fails CI.
const STD_KV := 35.0                      # mirrors GuardBrain.KV
const STD_KS := 15.0                      # mirrors GuardBrain.KS
const STD_PERCEPTION_RADIUS_MULT := 1.0   # neutral: no owner to mirror
const STD_CONE_RANGE_M := 14.0            # mirrors VisionCone.RANGE
const STD_CONE_ANGLE_DEG := 35.0          # mirrors VisionCone.HALF_ANGLE_DEG (HALF angle)
const STD_LIGHT_BRIGHT := 0.60            # mirrors LightModel.L_BRIGHT

# ⚠ READ THIS BEFORE "CORRECTING" THE VALUE BELOW TO 0.0 ⚠
# GDD §9.2's table prints `vision_light_floor = 0.0` for STANDARD, but §9.3 —
# the normative prose right underneath it — describes the sentinel's 0.05 as
# lowering the floor from "标准 0.20 等效地板", i.e. the STANDARD equivalent
# floor is L_DARK = 0.20. The two readings are not interchangeable:
#   floor = 0.20 -> (L-0.20)/(0.60-0.20) == LightModel.light_sensitivity(L)
#                   EXACTLY, for every L. Standard guards are unchanged.
#   floor = 0.00 -> (L-0.00)/(0.60-0.00) gives vis 0.167 in a shadow where a
#                   standard guard must read 0.0. That silently grants EVERY
#                   standard guard dark vision and quietly deletes shadow as a
#                   stealth resource — a core-pillar regression disguised as a
#                   default.
# The table's 0.0 is read as "no override"; 0.20 is what "no override" means in
# absolute terms. Locked by test_standard_light_floor_matches_light_model().
const STD_VISION_LIGHT_FLOOR := 0.20      # mirrors LightModel.L_DARK

# ── SOUND_HOUND overrides (GDD §9.2 / §9.3) ─────────────────────────────────
# Hearing-first: half the vision gain, double the sound gain, 1.6x hearing
# reach, and a slightly tighter cone (11m / 30 deg) so a silent shadow detour
# stays viable. Design intent: force sound management, not pure visual evasion.
const HOUND_KV := 15.0
const HOUND_KS := 30.0
const HOUND_PERCEPTION_RADIUS_MULT := 1.6
const HOUND_CONE_RANGE_M := 11.0
const HOUND_CONE_ANGLE_DEG := 30.0

# ── DARK_SENTINEL overrides (GDD §9.2 / §9.3) ───────────────────────────────
# Everything default EXCEPT the light floor: 0.05 instead of 0.20, so a shadow
# is no longer a free safe zone in a sentinel's patrol.
const SENTINEL_VISION_LIGHT_FLOOR := 0.05


# ── E08-S9 · entity-inventory type binding ──────────────────────────────────
# design/assets/entity-inventory.md rows 2/3/4 are the three guard character
# assets ("守卫·标准 Guard Standard" / "守卫·循声猎犬 Hound" / "守卫·暗视哨兵
# Sentinel"). A level/asset row names its guard by TYPE FIELD; this table is the
# single place that maps that string onto a variant.
#
# Keys are stored in NORMALISED form (see normalize_entity_type): upper-cased,
# with spaces / hyphens / middots / dots collapsed to underscores. Both the
# English and Chinese asset names are accepted because entity-inventory.md
# prints them together in one cell and neither half is authoritative.
const ENTITY_TYPE_TO_VARIANT := {
	# row 2 — 守卫·标准 Guard Standard
	"GUARD_STANDARD": Variant.STANDARD,
	"STANDARD": Variant.STANDARD,
	"GUARD": Variant.STANDARD,
	"守卫_标准": Variant.STANDARD,
	# row 3 — 守卫·循声猎犬 Hound
	"GUARD_HOUND": Variant.SOUND_HOUND,
	"HOUND": Variant.SOUND_HOUND,
	"SOUND_HOUND": Variant.SOUND_HOUND,
	"守卫_循声猎犬": Variant.SOUND_HOUND,
	# row 4 — 守卫·暗视哨兵 Sentinel
	"GUARD_SENTINEL": Variant.DARK_SENTINEL,
	"SENTINEL": Variant.DARK_SENTINEL,
	"DARK_SENTINEL": Variant.DARK_SENTINEL,
	"守卫_暗视哨兵": Variant.DARK_SENTINEL,
}

## Returned by variant_for_entity_type() when the type field is not in the
## table. Callers MUST test for this instead of letting an unknown string fall
## through to STANDARD in silence — a typo'd asset row that quietly spawns a
## standard guard is precisely the "variant silently does nothing" failure this
## batch is built to prevent. GuardSpawner keeps a ledger of these.
const VARIANT_UNKNOWN := -1


# ── Instance fields (the overlay itself) ────────────────────────────────────
# Plain vars, but treated as WRITE-ONCE at construction: build with a factory,
# never retune a live guard. GDD §9.1 — "运行时不可切换（关卡布置决定）".
var variant: int = Variant.STANDARD
var kv: float = STD_KV
var ks: float = STD_KS
var perception_radius_mult: float = STD_PERCEPTION_RADIUS_MULT
var cone_range_m: float = STD_CONE_RANGE_M
var cone_angle_deg: float = STD_CONE_ANGLE_DEG            # HALF angle, degrees
var vision_light_floor: float = STD_VISION_LIGHT_FLOOR
var light_bright: float = STD_LIGHT_BRIGHT


# ── Factories ───────────────────────────────────────────────────────────────
static func standard() -> GuardVariantParams:
	return GuardVariantParams.new()


static func hound() -> GuardVariantParams:
	var p := GuardVariantParams.new()
	p.variant = Variant.SOUND_HOUND
	p.kv = HOUND_KV
	p.ks = HOUND_KS
	p.perception_radius_mult = HOUND_PERCEPTION_RADIUS_MULT
	p.cone_range_m = HOUND_CONE_RANGE_M
	p.cone_angle_deg = HOUND_CONE_ANGLE_DEG
	# light floor deliberately left at STANDARD — the hound is not a night eye.
	return p


static func sentinel() -> GuardVariantParams:
	var p := GuardVariantParams.new()
	p.variant = Variant.DARK_SENTINEL
	# Everything else deliberately left at STANDARD (GDD §9.2: the sentinel row
	# is default in every column but this one).
	p.vision_light_floor = SENTINEL_VISION_LIGHT_FLOOR
	return p


static func for_variant(v: int) -> GuardVariantParams:
	match v:
		Variant.SOUND_HOUND:
			return hound()
		Variant.DARK_SENTINEL:
			return sentinel()
		_:
			return standard()


# ── E08-S9 · entity-type helpers ────────────────────────────────────────────
## Collapse an entity-inventory type field to a table key. Tolerates the shapes
## the asset sheet actually uses: "Guard Standard", "guard-hound",
## "守卫·暗视哨兵", "  SENTINEL  ".
static func normalize_entity_type(type_field: String) -> String:
	var s := type_field.strip_edges().to_upper()
	for sep in [" ", "-", "·", ".", "/"]:
		s = s.replace(sep, "_")
	while s.contains("__"):
		s = s.replace("__", "_")
	return s.trim_prefix("_").trim_suffix("_")


## Variant id for an entity-inventory type field, or VARIANT_UNKNOWN.
static func variant_for_entity_type(type_field: String) -> int:
	var key := normalize_entity_type(type_field)
	if key == "":
		return VARIANT_UNKNOWN
	return int(ENTITY_TYPE_TO_VARIANT.get(key, VARIANT_UNKNOWN))


static func is_known_entity_type(type_field: String) -> bool:
	return variant_for_entity_type(type_field) != VARIANT_UNKNOWN


## Params for an entity-inventory type field. An unknown field falls back to
## STANDARD so a bad asset row degrades to a playable guard instead of a crash —
## but callers are expected to have screened it with is_known_entity_type()
## first and to record the miss (GuardSpawner does exactly that).
static func from_entity_type(type_field: String) -> GuardVariantParams:
	var v := variant_for_entity_type(type_field)
	if v == VARIANT_UNKNOWN:
		return standard()
	return for_variant(v)


# ── Read-only helpers ───────────────────────────────────────────────────────
func variant_name() -> String:
	return str(VARIANT_NAMES.get(variant, "STANDARD"))


func is_standard() -> bool:
	return variant == Variant.STANDARD


## E08-S7 / GDD §9.3 — light sensitivity under this variant's dark floor.
##
## Generalises LightModel.light_sensitivity() by making the dark floor a
## parameter instead of the L_DARK constant:
##     vis = clamp((L - floor) / (L_BRIGHT - floor), 0, 1)
## With floor == STD_VISION_LIGHT_FLOOR (0.20) this is arithmetically IDENTICAL
## to LightModel.light_sensitivity() for every L, which is what lets the same
## code path serve standard guards and variants without a branch. The sentinel
## simply supplies a lower floor.
func light_sensitivity(level: float) -> float:
	var lo := vision_light_floor
	var hi := light_bright
	if hi <= lo:
		# Degenerate band: treat anything at/above the floor as fully lit rather
		# than dividing by zero.
		return 1.0 if level >= hi else 0.0
	return clampf((level - lo) / (hi - lo), 0.0, 1.0)


## Debug/inspection snapshot. Deliberately a plain Dictionary — it is NEVER put
## on the EventBus (GDD §9.4 zero new events).
func to_dict() -> Dictionary:
	return {
		"variant": variant,
		"variant_name": variant_name(),
		"kv": kv,
		"ks": ks,
		"perception_radius_mult": perception_radius_mult,
		"cone_range_m": cone_range_m,
		"cone_angle_deg": cone_angle_deg,
		"vision_light_floor": vision_light_floor,
		"light_bright": light_bright,
	}
