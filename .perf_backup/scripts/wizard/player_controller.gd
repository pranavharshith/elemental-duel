class_name PlayerController
extends Node3D
## Competitive third-person controller.
##
## The controller deliberately separates the three things that often get
## coupled incorrectly in small third-person games:
##   1. Mouse look is immediate and owns camera yaw/pitch.
##   2. WASD is evaluated in camera yaw space, with deliberate forward/side/
##      back speed bands rather than an accidental tank-control mapping.
##   3. The centre reticle is resolved from the rendered camera projection,
##      then checked again from the cast origin. This makes cover, shoulder
##      offset and camera shake honest: a spell cannot leave the wizard through
##      a wall just because the camera can see around it.

# Camera tune: a compact over-the-shoulder view that still leaves room to read
# incoming projectiles. Rotation is never damped; that would add aim latency.
const PITCH_MIN := -48.0
const PITCH_MAX := 32.0
const ARM_LENGTH := 4.35
const PIVOT_HEIGHT := 1.45
const SHOULDER := 0.58
const FOV := 72.0
const DEFAULT_PITCH := -10.0
const CAMERA_NEAR := 0.08
const CAMERA_MARGIN := 0.14
const CAMERA_PROBE_RADIUS := 0.22
const AIM_DISTANCE := 80.0

# Camera collides with the floor and the VISIBLE rim only. The boundary ring
# (16) is an invisible 12 m wall and earth walls (8) sit behind you when you
# retreat; colliding with either pushed the camera into the wizard's head.
# Earth walls fade instead (EarthWall._process), and aim stays honest because
# the view ray starts at the wizard's depth and the cast ray is re-checked.
const CAMERA_COLLISION_MASK := 1 | 32
const AIM_COLLISION_MASK := 1 | 2 | 8 | 16

# The wizard always turns and runs in the direction of travel, so every
# direction moves at the same speed.
const FORWARD_MULTIPLIER := 1.00
const STRAFE_MULTIPLIER := 1.00
const BACKWARD_MULTIPLIER := 1.00
# Soft aim assist: if the crosshair is within this angle of the rival's
# chest (and the path is clear), spells go to the chest.
const AIM_ASSIST_DEG := 5.0

var wizard: Wizard
var yaw := 0.0
var pitch := DEFAULT_PITCH
var camera: ShakeCamera
var _yaw_node: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var input_enabled := true
## Online joiner: casts and jumps go to the host for validation.
var net_client := false

func setup(w: Wizard) -> void:
	wizard = w
	if is_inside_tree():
		_exclude_wizard_from_camera()
		snap_behind()

func _ready() -> void:
	# Feed aim/input to the character before its default-priority physics tick.
	process_physics_priority = -100
	_yaw_node = Node3D.new()
	_yaw_node.name = "CameraYaw"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "CameraPitch"
	_yaw_node.add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.name = "CameraCollisionArm"
	_arm.spring_length = ARM_LENGTH
	_arm.collision_mask = CAMERA_COLLISION_MASK
	_arm.margin = CAMERA_MARGIN
	var probe := SphereShape3D.new()
	probe.radius = CAMERA_PROBE_RADIUS
	_arm.shape = probe
	_arm.position = Vector3(SHOULDER, 0, 0)
	_pitch_node.add_child(_arm)
	camera = ShakeCamera.new()
	camera.name = "PlayerCamera"
	camera.fov = FOV
	camera.near = CAMERA_NEAR
	camera.current = true
	_arm.add_child(camera)
	_exclude_wizard_from_camera()

func _exclude_wizard_from_camera() -> void:
	if _arm and wizard and is_instance_valid(wizard):
		_arm.add_excluded_object(wizard.get_rid())

## Put the camera directly behind the wizard at round start. This is the only
## automatic reorientation; ordinary play never steals mouse yaw from a player.
func snap_behind() -> void:
	if wizard == null:
		return
	var direction := -wizard.global_transform.basis.z
	direction.y = 0
	if direction.length_squared() > 0.001:
		yaw = rad_to_deg(atan2(-direction.x, -direction.z))
	pitch = DEFAULT_PITCH
	if is_inside_tree():
		global_position = wizard.visual_position() + Vector3.UP * PIVOT_HEIGHT
		_apply_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# screen_relative is not affected by stretch/viewport scaling.
		# The relative fallback keeps automated/headless input fixtures usable;
		# real windowed mouse input always supplies screen_relative.
		var mouse_delta := motion.screen_relative if not motion.screen_relative.is_zero_approx() else motion.relative
		apply_look_delta(mouse_delta)
		return
	if wizard == null:
		return
	for element in SpellBook.ELEMENTS:
		if event.is_action_pressed("elem_" + element):
			if net_client:
				# Online joiner: the host owns mana/cooldowns and fires the spell.
				# Give instant local feedback; the host echoes the result.
				if wizard.alive and wizard.controls_enabled and wizard.stun_time <= 0.0:
					Sfx.play_at("elem_" + element, wizard.global_position, -6.0)
					Net.send_element(element, wizard.aim_point)
			else:
				wizard.queue_element(element)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cast"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		release_buffer()
	elif event.is_action_pressed("spatial_jump"):
		# A dodge/teleport inherits the player's intended move direction. With no
		# movement input, it goes toward the reticle/camera forward direction.
		var move_direction := _move_vector()
		if move_direction.length_squared() < 0.01:
			move_direction = _flat_forward()
		if net_client:
			wizard.net_predict_jump(move_direction)
		else:
			wizard.try_spatial_jump(move_direction)

func _flat_forward() -> Vector3:
	var radians := deg_to_rad(yaw)
	return Vector3(-sin(radians), 0, -cos(radians))

## Kept public so deterministic/headless tests can validate the same look path
## without relying on an operating system cursor capture.
func apply_look_delta(mouse_delta: Vector2) -> void:
	yaw = wrapf(yaw - mouse_delta.x * Game.mouse_sensitivity, -180.0, 180.0)
	pitch = clampf(pitch - mouse_delta.y * Game.mouse_sensitivity, PITCH_MIN, PITCH_MAX)
	_apply_camera_transform() # avoid a frame of stale camera/aim orientation

func release_buffer() -> void:
	if wizard == null:
		return
	if net_client:
		Net.send_release(wizard.aim_point)
	else:
		wizard.release_buffer()

## Returns a camera-relative direction whose magnitude already carries the
## intentional forward/strafe/back speed band. Input.get_vector keeps diagonal
## input circular, so diagonal movement can never exceed the configured speed.
func _move_vector() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward_axis := -axes.y # W is positive forward in local movement space.
	var forward_scale := FORWARD_MULTIPLIER if forward_axis >= 0.0 else BACKWARD_MULTIPLIER
	var local_x := axes.x * STRAFE_MULTIPLIER
	var local_z := forward_axis * forward_scale
	var forward := _flat_forward()
	var right := Vector3(-forward.z, 0, forward.x)
	return (right * local_x + forward * local_z).limit_length(1.0)

func _physics_process(_delta: float) -> void:
	if wizard == null:
		return
	# Camera rotation is driven by state, not by a smoothed transform. Apply it
	# before raycasting so the reticle and spell target agree in this physics tick.
	global_position = wizard.global_position + Vector3.UP * PIVOT_HEIGHT
	_apply_camera_transform()
	wizard.move_input = _move_vector()
	_update_aim()

func _process(_delta: float) -> void:
	if wizard == null:
		return
	# Wizard.visual_position already interpolates physics states. A second follow
	# lag made the previous camera feel delayed and detached from the crosshair.
	global_position = wizard.visual_position() + Vector3.UP * PIVOT_HEIGHT
	_apply_camera_transform()

func _apply_camera_transform() -> void:
	if _yaw_node == null or _pitch_node == null:
		return
	_yaw_node.rotation.y = deg_to_rad(yaw)
	_pitch_node.rotation.x = deg_to_rad(pitch)

func _raycast(from: Vector3, to: Vector3, mask: int, excluded: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, excluded)
	query.collide_with_areas = false
	return wizard.get_world_3d().direct_space_state.intersect_ray(query)

## Two-stage third-person aim resolution:
##  - view ray: the exact centre pixel of the current projection (including
##    temporary camera shake offsets) finds what the reticle sees;
##  - cast ray: checks that the hand/chest origin has a clear path to that
##    point. If shoulder geometry blocks it, spells correctly strike the cover.
func _update_aim() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var rect := get_viewport().get_visible_rect()
	var centre := rect.get_center()
	var from := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre).normalized()
	# Skip anything between the camera and the wizard (e.g. your own earth wall
	# behind you) so it can never capture the reticle and fire spells backwards.
	var pivot := wizard.global_position + Vector3.UP * PIVOT_HEIGHT
	from += direction * maxf(0.0, (pivot - from).dot(direction))
	var view_hit := _raycast(from, from + direction * AIM_DISTANCE, AIM_COLLISION_MASK, [wizard.get_rid()])
	var view_target: Vector3 = view_hit["position"] if not view_hit.is_empty() else from + direction * AIM_DISTANCE
	var cast_origin := wizard.cast_origin_toward(direction)
	var cast_hit := _raycast(cast_origin, view_target, AIM_COLLISION_MASK, [wizard.get_rid()])
	wizard.aim_point = cast_hit["position"] if not cast_hit.is_empty() else view_target
	wizard.reticle_target = view_hit.get("collider", null)
	wizard.aim_blocked = not cast_hit.is_empty() and cast_hit.get("collider", null) != wizard.reticle_target
	# Soft aim assist toward the rival's chest when the crosshair is close and
	# nothing solid is in the way. Turns the reticle red so you know it's on.
	var opp := wizard.opponent
	if opp and opp.alive:
		var chest := opp.global_position + Vector3(0, 1.1, 0)
		var cam_from := camera.global_position
		if direction.angle_to((chest - cam_from).normalized()) < deg_to_rad(AIM_ASSIST_DEG):
			var blocked := _raycast(cast_origin, chest, 1 | 8 | 16, [wizard.get_rid(), opp.get_rid()])
			if blocked.is_empty():
				wizard.aim_point = chest
				wizard.reticle_target = opp
				wizard.aim_blocked = false
