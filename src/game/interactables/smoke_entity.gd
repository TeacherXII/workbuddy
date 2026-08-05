class_name SmokeEntity
extends InteractableEntity

# ASHEN STEP — Sprint 2, Batch B. E07-S4: the smoke screen (carried item).
#
# sprint2-stories E07-S4:
#   Throwing smoke drops a TEMPORARY region at the landing point; E05
#   compute_visibility multiplies by smoke_factor = 0.3 (vis = base x cover x
#   smoke) for ~4s, then the puff expires; charges[SMOKE] -= 1.
#
# ★ This entity emits NO domain signal of its own — there is no "smoke" verb in
#   the frozen vocabulary and none is being added. The world effect is a
#   MULTIPLIER handed to E05 through SmokeField, exactly the injection seam
#   E05-S6 already built for consistency-review C3. The only signal that leaves
#   here is interactable_triggered, for the HUD slot.

const SmokeFieldScript = preload("res://src/game/interactables/smoke_field.gd")

var _field: SmokeField = null


func _init() -> void:
	type = EventBus.InteractableType.SMOKE


func set_smoke_field(field: SmokeField) -> void:
	_field = field


## Throw at an explicit world point. Returns false when the backpack is empty.
func throw(aim_point: Vector3, radius: float = SmokeFieldScript.RADIUS,
		duration_rt: float = SmokeFieldScript.DURATION_RT) -> bool:
	return trigger({
		"aim_point": aim_point,
		"radius": radius,
		"duration": duration_rt,
	})


## Throw at whatever the E03 aim logic is pointing at (duck-typed, see
## DecoyEntity.throw_from_aim for why).
func throw_from_aim(aim_source: Object) -> bool:
	if aim_source == null:
		return false
	var point: Vector3 = aim_source.get("aim_point")
	return throw(point)


func _fire(ctx: Dictionary) -> Dictionary:
	var landing: Vector3 = ctx.get("aim_point", position)
	var radius: float = float(ctx.get("radius", SmokeFieldScript.RADIUS))
	var duration: float = float(ctx.get("duration", SmokeFieldScript.DURATION_RT))
	position = landing
	var expires := 0.0
	if _field != null:
		var rec := _field.spawn(landing, radius, duration)
		expires = float(rec.get("expires_rt", 0.0))
	else:
		# Not a refusal (the charge is still spent and the HUD still updates),
		# but a level that forgot to wire the field gets a loud breadcrumb
		# instead of a puff that silently does nothing.
		push_warning("SmokeEntity %d: no SmokeField wired; the throw has no visibility effect"
			% entity_id)
	return {
		"pos": landing,
		"radius": radius,
		"duration": duration,
		"smoke_factor": SmokeFieldScript.factor(),
		"expires_rt": expires,
	}
