class_name HudColors
extends RefCounted

# ASHEN STEP — Sprint 1 Batch C. E09 HUD colour authority (decision D7).
# Extended by Sprint 2 Batch C (E09-S5a) with the C-06 colour-blind mapping.
#
# 色值权威 / colour authority: design/art/hud-a11y-signature.md (林绘澄 Art
# Sign-off, D7 PASS) + docs/architecture/control-manifest.md v0.2.
# Engineering must NOT invent or retune values here — the palette is signed art,
# and hud_slice.gd is forbidden from carrying any hard-coded colour literal of
# its own.
#
# Contrast is computed against the reference panel #16181D; the two shipped
# panel variants (#1B1B1F / #1C1F26) also clear their gates — see PANEL_VARIANTS.
#
# ★ HARD RULE (landmine 3): #7A2E2E is 1.91:1 against the panel. It is
# mathematically incapable of ever satisfying C-02 (7:1) or C-03 (3:1). It may
# be used ONLY as a background fill at alpha <= ALARM_FILL_ALPHA_MAX, never as
# text, never as a bar body, never as a border, never as an icon. The reverse
# assertion in tests/unit/test_hud_slice.gd::test_suspicion_bar_contrast exists
# to break the build if anyone promotes it.
#
# ── Spec deviation (exactly one, values identical) ──────────────────────────
# batchc-impl-spec §2.3.1 writes these as `Color.from_string("#16181D", ...)`.
# GDScript 4.4 only accepts CONSTANT EXPRESSIONS in a `const`, and a static
# method call is not one — `Color.from_string()` fails to compile with
# "Assigned value for constant isn't a constant expression" (verified against
# Godot_v4.4-stable). The constant-foldable `Color("#hex")` constructor is used
# instead: the hex literals are copied verbatim from the signature document and
# the runtime values are identical; only the compile-time evaluation differs.

# The colour-blind enum lives with the field model it belongs to (E09-S7).
# Mirroring it here would be a second source of truth, so it is imported.
const A11yModel := preload("res://src/core/a11y_settings.gd")

const HUD_COLOR_PANEL_BASE := Color("#16181D")   #  ----   contrast reference panel
const HUD_COLOR_CARRIER := Color("#DCE3EC")      # 13.74:1  C-02 ✅ every carrier
const HUD_COLOR_CALM := Color("#3E5C76")         #  2.53:1  decorative stroke only
const HUD_COLOR_CAUTION := Color("#C8862F")      #  5.84:1  C-01/C-03 ✅
const HUD_COLOR_ALARM := Color("#D64545")        #  4.06:1  C-03 ✅ borders + icons
const HUD_COLOR_ALARM_FILL := Color("#7A2E2E")   #  1.91:1  ★ FILL ONLY, a <= 0.35
# HUD_COLOR_ALARM_CB stood here until Sprint 2 Batch C. It is RETIRED, not
# renamed and not moved — see the tombstone below before re-adding anything
# that maps danger onto an existing semantic hue.

# Pre-approved alternative, used ONLY if an audit demands the alarm border clear
# C-01 on its own. Do not invent a different one.
const HUD_COLOR_ALARM_ALT := Color("#E0584F")    #  4.80:1  C-01 ✅

# ── E09-S5a · C-06 substitute, v0.2 口径 ────────────────────────────────────
# † TOMBSTONE · HUD_COLOR_ALARM_CB (Sprint 1 → retired Sprint 2 Batch C)
#
#   WHY IT EXISTED. Sprint 1 shipped the C-06 substitute as
#   `HUD_COLOR_ALARM_CB := HUD_COLOR_CAUTION` — "in colour-blind mode, draw
#   danger in the Caution amber". batchc-impl-spec (§H17) and the original
#   brief both specified that mapping in those words, so it was implemented
#   as written and pinned by a test.
#
#   WHY IT IS VOID. control-manifest v0.2 C-06 strikes it in as many words:
#  「旧口径「→#C8862F」作废：警戒本就是 #C8862F，映射后两档亮度比塌缩至 1.00:1」.
#   Caution IS #C8862F, so the mapping painted 警戒 and 警报 the SAME colour:
#   a 1.00:1 collapse, and a C-05 violation committed inside the very feature
#   meant to prevent it. A substitute that erases the distinction it exists to
#   preserve is strictly worse than no substitute at all.
#
#   CURRENT AUTHORITY. HUD_COLOR_DANGER_CB (below) is the sole C-06 substitute,
#   and danger_color() is the sole decision point for what danger looks like.
#   The reverse assertions live in
#   test_a11y_settings.gd::test_colorblind_enum_maps_danger_color and in
#   test_hud_slice.gd (C-06 reverse lock): both fail the build if the
#   substitute is ever collapsed back onto Caution.
#
#   Retired by principal ruling 2026-08-05, closing the migration item at
#   design/art/accessibility-matrix.md:199 and CONCERN 1 in
#   production/sprints/sprint2-batchc-impl-notes.md. The NAME was deleted
#   deliberately rather than repointed: keeping it alive would have left a
#   test asserting a value the signature document had already withdrawn.
#
#   NOTE WHEN DIFFING AGAINST ART. hud-a11y-signature §4 keeps the OLD NAME
#   carrying the NEW value (`HUD_COLOR_ALARM_CB := #F0C070`). The VALUE here is
#   identical; only the name differs. "ALARM_CB" would read as "the alarm
#   colour, colour-blind variant", but the substitute is deliberately NOT in
#   the alarm family — it is an amber luminance variant. This is an
#   engineering-side naming clarification, not a value deviation.
#
# #F0C070 is 10.55:1 on the reference panel (clears C-02 as well as C-03) and is
# a LUMINANCE variant inside the existing amber family (hue 37.5° vs Caution's
# 34.1°), so it introduces no new hue to the signed palette. Its separation from
# both semantic hues is carried by BRIGHTNESS, which is what makes it work for
# protan, deutan AND tritan alike:
#   vs HUD_COLOR_ALARM   2.60:1
#   vs HUD_COLOR_CAUTION 1.81:1   (the retired substitute scored exactly 1.00:1)
const HUD_COLOR_DANGER_CB := Color("#F0C070")

# Information-boundary stroke (control-manifest v0.2 §C note): 3.32:1 on the
# reference panel, a luminance variant of HUD_COLOR_CALM. Use it for「须被感知
# 的 UI 组件边界」; purely decorative strokes stay on HUD_COLOR_CALM, which is
# exempt from C-03.
const HUD_COLOR_BOUNDARY := Color("#4E6E8A")

# C-07「危险提示绝不单独使用」. The glyph is returned for EVERY colour-blind mode
# INCLUDING OFF: the shape channel is permanent, not a colour-blind fallback.
const DANGER_ICON := "!"

# The substitute must stay this far from the two semantic hues it has to be told
# apart from. 1.2:1 is deliberately low — it is a COLLAPSE detector, not a
# contrast gate; C-02/C-03 are asserted separately.
const DANGER_CB_MIN_SEPARATION := 1.2

# ★ The hard ceiling on #7A2E2E (signature document §3).
const ALARM_FILL_ALPHA_MAX := 0.35

# Cross-check panels from the signature document §1. Every carrier must clear
# its gate on these too, not just on the reference panel.
const PANEL_VARIANTS := [Color("#1B1B1F"), Color("#1C1F26")]


# --- E09-S5a: C-06 danger mapping -------------------------------------------
# Pure functions of the colour-blind mode. hud_slice.gd calls these instead of
# branching on the mode itself, so there is exactly ONE place that decides what
# "danger" looks like.

## Is a substitution active? OFF means "ship the signed alarm hue unchanged".
static func is_colorblind(colorblind_mode: int) -> bool:
	return colorblind_mode != A11yModel.ColorBlindMode.OFF


## C-06: the semantic DANGER carrier (borders, icons, alert strokes).
## PROTAN / DEUTAN / TRITAN share one substitute by design — the manifest note
## is explicit that the three types are separated by the always-on shape and
## pulse channels, not by three different hues.
static func danger_color(colorblind_mode: int) -> Color:
	if is_colorblind(colorblind_mode):
		return HUD_COLOR_DANGER_CB
	return HUD_COLOR_ALARM


## C-07: the danger glyph. Independent of the mode ON PURPOSE — returning ""
## for OFF would make the un-substituted state colour-only, which is the exact
## failure C-07 forbids.
static func danger_icon(_colorblind_mode: int) -> String:
	return DANGER_ICON


## C-05/C-07 self-check, exposed so both the unit suite and any future runtime
## audit can ask the palette the same question: is the danger read still carried
## by more than hue at this mode? True only when the substitute is separated
## from BOTH semantic hues by luminance and the glyph is non-empty.
static func danger_read_is_multi_channel(colorblind_mode: int) -> bool:
	if danger_icon(colorblind_mode) == "":
		return false
	var danger := danger_color(colorblind_mode)
	if not is_colorblind(colorblind_mode):
		return wcag_contrast(danger, HUD_COLOR_CAUTION) >= DANGER_CB_MIN_SEPARATION
	return (wcag_contrast(danger, HUD_COLOR_CAUTION) >= DANGER_CB_MIN_SEPARATION
		and wcag_contrast(danger, HUD_COLOR_ALARM) >= DANGER_CB_MIN_SEPARATION)


# --- WCAG 2.x pure functions -------------------------------------------------
# Headless-safe by construction: these are arithmetic on Color values and never
# sample a pixel, so C-02/C-03 can be asserted in a GUT unit test rather than in
# a screenshot diff.

static func relative_luminance(c: Color) -> float:
	return 0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b)


static func wcag_contrast(fg: Color, bg: Color) -> float:
	var l1 := relative_luminance(fg)
	var l2 := relative_luminance(bg)
	var hi := maxf(l1, l2)
	var lo := minf(l1, l2)
	return (hi + 0.05) / (lo + 0.05)


# Pre-composite a translucent colour over an opaque one. Used to evaluate the
# contrast of carriers drawn ON TOP of a semi-transparent fill (the exposure
# overlay, the suspicion-bar alpha ladder) without ever reading the framebuffer.
static func composite(fg: Color, bg: Color, alpha: float) -> Color:
	var a := clampf(alpha, 0.0, 1.0)
	return Color(
		fg.r * a + bg.r * (1.0 - a),
		fg.g * a + bg.g * (1.0 - a),
		fg.b * a + bg.b * (1.0 - a),
		1.0)


static func _linearize(channel: float) -> float:
	if channel <= 0.03928:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
