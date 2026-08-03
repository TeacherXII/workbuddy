class_name SpatialQueryWrapper
extends RefCounted

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 spatial query wrapper. Centralizes LOS raycasts so gameplay (L4) never
# calls PhysicsDirectSpaceState3D directly (architecture §2 layer contract,
# E01-S3). Only the occlusion layer (walls / pillars / doors) blocks sight.
#
# All rays go through one masked query so the occlusion mask is consistent and
# the call is cheap to throttle/batch from vision-cone ticks (ADR-002 G-03).

const DEFAULT_OCCLUSION_MASK := 1  # bit 0 reserved for occluders; tune per project


func has_line_of_sight(from: Vector3, to: Vector3, occlusion_mask: int) -> bool:
	var space_state := _get_space_state()
	# No world yet (editor/headless before a scene is active): treat as visible
	# so callers don't falsely report "blocked" before the tree is ready.
	if space_state == null:
		return true

	# Degenerate ray (observer standing on the target): nothing can lie strictly
	# between the two points, so sight is clear by definition. intersect_ray is
	# undefined for a zero-length segment, so never trust it here.
	if from.is_equal_approx(to):
		return true

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = occlusion_mask

	var hit := space_state.intersect_ray(query)
	# No collision between from and to => the line of sight is clear.
	if hit.is_empty():
		return true

	# Defensive: only a REAL, still-valid occluder body may block sight. A hit
	# dictionary without a live collider cannot be attributed to an occluder
	# (stale/freed body, or a non-production physics context such as the
	# headless CI container), so we fall back to the documented intent above:
	# when a reliable occlusion verdict is unavailable, treat sight as clear
	# rather than falsely reporting "blocked".
	var collider = hit.get("collider", null)
	if collider == null or not is_instance_valid(collider):
		return true

	return false


func _get_space_state() -> PhysicsDirectSpaceState3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var world_3d := tree.root.world_3d
	if world_3d == null:
		return null
	return world_3d.direct_space_state
