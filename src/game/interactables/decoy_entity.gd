class_name DecoyEntity
extends InteractableEntity

# ASHEN STEP — Sprint 2, Batch B. E07-S1: the DECOY throwable (carried item).
#
# interactables.md §2 / sprint2-stories E07-S1:
#   Given charges[DECOY] > 0, the player reuses the E03 aim logic to pick a
#   landing point; throwing emits decoy_landed(pos, surface, radius≈8m), which
#   E06 (SoundPropagator._on_decoy_landed) turns into a real DECOY sound ring;
#   charges[DECOY] -= 1; exhausted means the throw simply does not happen.
#
# ★ The signal already exists and is FROZEN (event_bus.gd:69) — Sprint 1 closed
#   it in Batch D. This story adds the physical entity that emits it, nothing
#   else. No new vocabulary, no second sound path: E06 stays the sole owner of
#   the ring + the G-02 FIFO.
#
# ★ radius is NOT re-declared here. SoundPropagator.DECOY_RADIUS (8.0) is the
#   single source of truth; duplicating "8.0" in the thrower is exactly how the
#   ring and the gameplay radius drift apart.
#
# ★ [D11-A] `surface` selects foley/subtitle variant ONLY. It MUST NOT modulate
#   the radius — sound_propagation.gd:136 documents the same rule on the
#   consumer side, and test_sound_propagation.gd reverse-asserts it.

const SoundPropagatorScript = preload("res://src/game/sound_propagation.gd")
const StepCommitScript = preload("res://src/game/step_commit.gd")

# Surface used when the level/aim source did not supply one. STONE is the
# canonical gameplay surface (step_commit.gd:15).
const DEFAULT_SURFACE := "STONE"


func _init() -> void:
	type = EventBus.InteractableType.DECOY


## Nominal throw radius in METRES, read from the E06 owner constant.
static func nominal_radius() -> float:
	return SoundPropagatorScript.DECOY_RADIUS


## Is `surface` a real StepCommit surface key? Used to keep a typo'd level from
## silently degrading to STONE foley.
static func is_known_surface(surface: String) -> bool:
	return StepCommitScript.SURFACE_FACTOR.has(surface)


## Throw at an explicit world point. Returns false when the backpack is empty.
func throw(aim_point: Vector3, surface: String = DEFAULT_SURFACE) -> bool:
	return trigger({"aim_point": aim_point, "surface": surface})


## Throw at whatever the E03 aim logic is currently pointing at. Duck-typed on
## purpose: StepCommit is a Node and this entity is a RefCounted — reaching for
## the class would drag a scene-tree dependency into a headless object.
func throw_from_aim(aim_source: Object, surface: String = DEFAULT_SURFACE) -> bool:
	if aim_source == null:
		return false
	var point: Vector3 = aim_source.get("aim_point")
	return throw(point, surface)


func _fire(ctx: Dictionary) -> Dictionary:
	var landing: Vector3 = ctx.get("aim_point", position)
	var surface: String = str(ctx.get("surface", DEFAULT_SURFACE))
	if not is_known_surface(surface):
		push_warning("DecoyEntity: unknown surface `%s`, foley falls back to %s"
			% [surface, DEFAULT_SURFACE])
		surface = DEFAULT_SURFACE
	# Edge: a non-positive radius (uninitialised level data) falls back to the
	# nominal value. Mirrors the same guard on the consumer side
	# (sound_propagation.gd:143) — a 0m ring is a silent dud no guard can hear.
	var radius: float = float(ctx.get("radius", nominal_radius()))
	if radius <= 0.0:
		radius = nominal_radius()
	# The pebble now lies where it landed; a later announce/save reads this.
	position = landing
	if _bus != null:
		# NO short emit: every declared parameter is passed (N-8, event_bus.gd:65).
		_bus.decoy_landed.emit(landing, surface, radius)
	return {
		"pos": landing,
		"surface": surface,
		"radius": radius,
	}


# E07-S8: a thrown decoy always costs one slot of the E06 ring FIFO (G-02 <=8).
func emits_sound_ring() -> bool:
	return true
