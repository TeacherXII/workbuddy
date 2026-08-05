class_name SmokeField
extends RefCounted

# ASHEN STEP — Sprint 2, Batch B. E07-S4: the temporary smoke regions that
# rewrite E05 visibility (consistency-review C3).
#
# interactables.md §9.4 / sprint2-stories E07-S4:
#   vis = base_vis x cover_factor x smoke_factor,  smoke_factor = 0.3,  ~4s.
#
# ★ NO new event vocabulary and NO new system. This is a tiny spatial registry
#   that VisionCone consults through a duck-typed setter — the same
#   "orchestrate, don't repaint" pattern E09-S3 uses for set_readability_boost.
#   VisionCone must NOT preload this file (that would create a cycle); this file
#   preloads nothing and reads the multiplier off the E05 owner by global class
#   name at call time.
#
# ★ 0.3 is NOT re-declared here. VisionCone.VIS_MULT_SMOKE (vision_cone.gd:36)
#   is the single source of truth; two copies of a balance number is how smoke
#   ends up 0.3 in the cone and 0.35 in the thrower.
#
# ★ Overlapping puffs do NOT stack. Two clouds still read 0.3, never 0.09 —
#   R-03 forbids any path that converges on invisibility. Smoke lowers
#   visibility; it never grants it.

# interactables.md §9.4 "限时 ≈4s". Measured on the REAL clock, matching the
# E04 extinction ramp convention (light_model.gd FOG_RAMP_RT), NOT on
# Engine.time_scale. See the handoff note: if design wants the puff to linger
# through FOCUS, this becomes a scaled accumulator instead.
const DURATION_RT := 4.0

# Puff footprint in metres. Deliberately smaller than the 8m decoy ring: smoke
# is a local screen, not an area denial tool.
const RADIUS := 4.0

var _regions: Array = []       # [{ "center": Vector3, "radius": float, "expires_rt": float }]
# Determinism hook for headless tests: >= 0.0 replaces the wall clock, so a 4s
# expiry can be proven without a 4s sleep (and without touching time_scale).
var _clock_override: float = -1.0


# --- clock -------------------------------------------------------------------
func set_clock_override(now_rt: float) -> void:
	_clock_override = now_rt


func clear_clock_override() -> void:
	_clock_override = -1.0


func advance_clock(seconds: float) -> void:
	# Only meaningful while overridden; a no-op on the real clock (which the
	# engine advances on its own).
	if _clock_override >= 0.0:
		_clock_override += seconds


func now_rt() -> float:
	if _clock_override >= 0.0:
		return _clock_override
	return Time.get_ticks_msec() / 1000.0


# --- regions -----------------------------------------------------------------
## Drop a puff. Returns the region record so a caller/test can inspect it.
func spawn(center: Vector3, radius: float = RADIUS, duration_rt: float = DURATION_RT) -> Dictionary:
	var r: float = radius if radius > 0.0 else RADIUS
	var d: float = duration_rt if duration_rt > 0.0 else DURATION_RT
	var rec := {
		"center": center,
		"radius": r,
		"expires_rt": now_rt() + d,
	}
	_regions.append(rec)
	return rec


## The E05 injection point. Returns VIS_MULT_SMOKE inside any LIVE puff, else
## 1.0 (a neutral multiplier, so an empty field costs the cone nothing).
func smoke_factor_at(pos: Vector3) -> float:
	prune()
	for rec in _regions:
		var center: Vector3 = rec["center"]
		var radius: float = float(rec["radius"])
		if center.distance_to(pos) <= radius:
			return factor()
	return 1.0


## Drop expired puffs. Returns how many were retired.
func prune() -> int:
	var now := now_rt()
	var kept: Array = []
	var dropped := 0
	for rec in _regions:
		if float(rec["expires_rt"]) > now:
			kept.append(rec)
		else:
			dropped += 1
	_regions = kept
	return dropped


func active_count() -> int:
	prune()
	return _regions.size()


func clear() -> void:
	_regions.clear()


## The one legal source of the smoke multiplier (E05 owns the number).
static func factor() -> float:
	return VisionCone.VIS_MULT_SMOKE
