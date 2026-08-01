class_name LightModel
extends RefCounted

# ASHEN STEP — Sprint 0 vertical slice (Phase 5). E04 cover-shadow.
# Mock LightLevel provider for the vertical slice. get_light_level returns a
# binary dark/light value driven by registered shadow boxes. In production this
# is replaced by baked LightmapGI probes + dynamic light overlays (ADR-004),
# but the public API (get_light_level / light_sensitivity) is stable so the
# vision cone and AI consume it unchanged.

const L_DARK := 0.20
const L_BRIGHT := 0.60

var _shadow_boxes: Array = []   # each: {"center": Vector3, "radius": float}


func add_shadow_box(center: Vector3, radius: float) -> void:
	_shadow_boxes.append({"center": center, "radius": radius})


func get_light_level(point: Vector3) -> float:
	for box in _shadow_boxes:
		var c: Vector3 = box["center"]
		var r: float = box["radius"]
		if point.distance_to(c) <= r:
			return 0.1   # inside a shadow box -> dark
	return 1.0          # light pool


func light_sensitivity(level: float) -> float:
	if level >= L_BRIGHT:
		return 1.0
	if level <= L_DARK:
		return 0.0
	return (level - L_DARK) / (L_BRIGHT - L_DARK)
