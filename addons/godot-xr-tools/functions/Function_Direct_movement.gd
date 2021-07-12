extends Node

enum MOVEMENT_TYPE { MOVE_AND_ROTATE, MOVE_AND_STRAFE }

# Is this active?
@export var enabled = true:
	set(new_value):
		enabled = new_value
		if collision_shape:
			collision_shape.disabled = !enabled
		if tail:
			tail.enabled = enabled
		if enabled:
			# make sure our physics process is on
			set_physics_process(true)
		else:
			# we turn this off in physics process just in case we want to do some cleanup
			pass

# We don't know the name of the camera node...
@export var camera: NodePath = NodePath()

# size of our player
@export var player_radius = 0.4:
	set(new_value):
		player_radius = new_value

# to combat motion sickness we'll 'step' our left/right turning
@export var smooth_rotation = false
@export var smooth_turn_speed = 2.0
@export var step_turn_delay = 0.2
@export var step_turn_angle = 20.0

# and movement
@export var max_speed = 10.0
@export var drag_factor = 0.1

# enum our buttons, should find a way to put this more central
enum Buttons {
	VR_BUTTON_BY = 1,
	VR_GRIP = 2,
	VR_BUTTON_3 = 3,
	VR_BUTTON_4 = 4,
	VR_BUTTON_5 = 5,
	VR_BUTTON_6 = 6,
	VR_BUTTON_AX = 7,
	VR_BUTTON_8 = 8,
	VR_BUTTON_9 = 9,
	VR_BUTTON_10 = 10,
	VR_BUTTON_11 = 11,
	VR_BUTTON_12 = 12,
	VR_BUTTON_13 = 13,
	VR_PAD = 14,
	VR_TRIGGER = 15
}

# fly mode and strafe movement management
@export var move_type: MOVEMENT_TYPE = MOVEMENT_TYPE.MOVE_AND_ROTATE
@export var canFly = true
@export var fly_move_button_id: Buttons = Buttons.VR_TRIGGER
@export var fly_activate_button_id: Buttons = Buttons.VR_GRIP
var isflying = false

var turn_step = 0.0
var origin_node = null
var camera_node = null
var velocity = Vector3(0.0, 0.0, 0.0)
var gravity = -9.8
@onready var collision_shape: CollisionShape3D = get_node("CharacterBody3D/CollisionShape3D")
@onready var tail: RayCast3D = get_node("CharacterBody3D/Tail")

# Set our collision layer
@export_flags_3d_physics var collision_layer = 1:
	set(new_value):
		collision_layer = new_value
		_update_collision_layer()

# Set our collision mask
@export_flags_3d_physics var collision_mask = 1022:
	set(new_value):
		collision_mask = new_value
		_update_collision_mask()

func _update_collision_layer():
	if $CharacterBody3D:
		$CharacterBody3D.collision_layer = collision_layer

func _update_collision_mask():
	if $CharacterBody3D:
		$CharacterBody3D.collision_mask = collision_mask
		$CharacterBody3D/Tail.collision_mask = collision_mask


func _ready():
	# origin node should always be the parent of our parent
	origin_node = get_node("../..")

	if camera:
		camera_node = get_node(camera)
	else:
		# see if we can find our default
		camera_node = origin_node.get_node('XRCamera')

	# Our properties are set before our children are constructed so just re-issue
	_update_collision_layer()
	_update_collision_mask()

	collision_shape.disabled = !enabled
	tail.enabled = enabled

func _physics_process(delta):
	if !origin_node:
		return

	if !camera_node:
		return

	if !enabled:
		set_physics_process(false)
		return

	# Adjust the height of our player according to our camera position
	var player_height = camera_node.transform.origin.y + player_radius
	if player_height < player_radius:
		# not smaller than this
		player_height = player_radius

	collision_shape.shape.radius = player_radius
	collision_shape.shape.height = player_height - (player_radius * 2.0)
	collision_shape.transform.origin.y = (player_height / 2.0)

	# We should be the child or the controller on which the teleport is implemented
	var controller = get_parent()
	if controller.get_is_active():
		var left_right = controller.get_joystick_axis(0)
		var forwards_backwards = controller.get_joystick_axis(1)

		# if fly_action_button_id is pressed it activates the FLY MODE
		# if fly_action_button_id is released it deactivates the FLY MODE
		if controller.is_button_pressed(fly_activate_button_id) && canFly:
			isflying =  true
		else:
			isflying = false

		# if player is flying, he moves following the controller's orientation
		if isflying:
			if controller.is_button_pressed(fly_move_button_id):
				# is flying, so we will use the controller's transform to move the VR capsule follow its orientation
				var curr_transform = $CharacterBody3D.global_transform
				$CharacterBody3D.linear_velocity = -controller.global_transform.basis.z.normalized() * max_speed * XRServer.world_scale
				$CharacterBody3D.move_and_slide()
				velocity = $CharacterBody3D.linear_velocity
				var movement = ($CharacterBody3D.global_transform.origin - curr_transform.origin)
				origin_node.global_transform.origin += movement

		################################################################
		# first process turning, no problems there :)
		# move_type == MOVEMENT_TYPE.move_and_strafe
		else:
			if(abs(left_right) > 0.1): # move_type == MOVEMENT_TYPE.MOVE_AND_ROTATE && 
				if smooth_rotation:
					# we rotate around our Camera, but we adjust our origin, so we need a little bit of trickery
					var t1 : Transform3D = Transform3D()
					var t2 : Transform3D = Transform3D()
					var rot : Transform3D = Transform3D()

					t1.origin = -camera_node.transform.origin
					t2.origin = camera_node.transform.origin
					rot = rot.rotated(Vector3(0.0, -1.0, 0.0), smooth_turn_speed * delta * left_right)
					origin_node.transform = (origin_node.transform * t2 * rot * t1).orthonormalized()

					# reset turn step, doesn't apply
					turn_step = 0.0
				else:
					if left_right > 0.0:
						if turn_step < 0.0:
							# reset step
							turn_step = 0

						turn_step += left_right * delta
					else:
						if turn_step > 0.0:
							# reset step
							turn_step = 0

						turn_step += left_right * delta

					if abs(turn_step) > step_turn_delay:
						# we rotate around our Camera, but we adjust our origin, so we need a little bit of trickery
						var t1 = Transform3D()
						var t2 = Transform3D()
						var rot = Transform3D()

						t1.origin = -camera_node.transform.origin
						t2.origin = camera_node.transform.origin

						# Rotating
						while abs(turn_step) > step_turn_delay:
							if (turn_step > 0.0):
								rot = rot.rotated(Vector3(0.0, -1.0, 0.0), step_turn_angle * PI / 180.0)
								turn_step -= step_turn_delay
							else:
								rot = rot.rotated(Vector3(0.0, 1.0, 0.0), step_turn_angle * PI / 180.0)
								turn_step += step_turn_delay

						origin_node.transform *= t2 * rot * t1
			else:
				# reset turn step, no longer turning
				turn_step = 0.0

			################################################################
			# now we do our movement
			# We start with placing our CharacterBody3D in the right place
			# by centering it on the camera but placing it on the ground
			var curr_transform = $CharacterBody3D.global_transform
			var camera_transform = camera_node.global_transform
			curr_transform.origin = camera_transform.origin
			curr_transform.origin.y = origin_node.global_transform.origin.y

			# now we move it slightly back
			var forward_dir = -camera_transform.basis.z
			forward_dir.y = 0.0
			if forward_dir.length() > 0.01:
				curr_transform.origin += forward_dir.normalized() * -0.75 * player_radius

			$CharacterBody3D.global_transform = curr_transform

			# we'll handle gravity separately
			var gravity_velocity = Vector3(0.0, velocity.y, 0.0)
			velocity.y = 0.0

			# Apply our drag
			velocity *= (1.0 - drag_factor)

			if move_type == MOVEMENT_TYPE.MOVE_AND_ROTATE:
				if (abs(forwards_backwards) > 0.1 and tail.is_colliding()):
					var dir = camera_transform.basis.z
					dir.y = 0.0
					velocity = dir.normalized() * -forwards_backwards * max_speed * XRServer.world_scale
					#velocity = velocity.linear_interpolate(dir, delta * 100.0)
			elif move_type == MOVEMENT_TYPE.MOVE_AND_STRAFE:
				if ((abs(forwards_backwards) > 0.1 ||  abs(left_right) > 0.1) and tail.is_colliding()):
					var dir_forward = camera_transform.basis.z
					dir_forward.y = 0.0
					# VR Capsule will strafe left and right
					var dir_right = camera_transform.basis.x;
					dir_right.y = 0.0
					velocity = (dir_forward * -forwards_backwards + dir_right * left_right).normalized() * max_speed * XRServer.world_scale

			# apply move and slide to our kinematic body
			$CharacterBody3D.linear_velocity = velocity
			$CharacterBody3D.move_and_slide()
			velocity = $CharacterBody3D.linear_velocity

			# apply our gravity
			gravity_velocity.y += 0.5 * gravity * delta
			$CharacterBody3D.linear_velocity = gravity_velocity
			$CharacterBody3D.move_and_slide()
			gravity_velocity = $CharacterBody3D.linear_velocity
			velocity.y = gravity_velocity.y

			# now use our new position to move our origin point
			var movement = ($CharacterBody3D.global_transform.origin - curr_transform.origin)
			origin_node.global_transform.origin += movement

			# Return this back to where it was so we can use its collision shape for other things too
			# $CharacterBody3D.global_transform.origin = curr_transform.origin
