@tool
extends CharacterBody3D

# Add this scene as a sub scene of your XRController3D node to implement a teleport function on that controller.

# Is this active?
@export var enabled = true:
	set(new_value):
		enabled = new_value
		if enabled:
			# make sure our physics process is on
			set_physics_process(true)
		else:
			# we turn this off in physics process just in case we want to do some cleanup
			pass

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

@export var teleport_button: Buttons = Buttons.VR_TRIGGER
@export var can_teleport_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var cant_teleport_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var no_collision_color: Color = Color(45.0 / 255.0, 80.0 / 255.0, 220.0 / 255.0, 1.0)

@export var player_height: float = 1.8:
	set(new_value):
		player_height = new_value
		_update_player_height()

@export var player_radius: float = 0.4:
	set(new_value):
		player_radius = new_value
		_update_player_radius()

@export var strength: float = 5.0
@export var max_slope: float = 20.0

# once this is no longer a kinematic body, we'll need this..
# @export_flags_3d_physics var collision_mask = 1

# We don't know the name of the camera node...
@export var camera: NodePath = NodePath()

@onready var ws: float = XRServer.world_scale
var origin_node: XROrigin3D = null
var camera_node: XRCamera3D = null
var is_on_floor = true
var is_teleporting = false
var can_teleport = true
var teleport_rotation = 0.0;
var floor_normal = Vector3(0.0, 1.0, 0.0)
var last_target_transform: Transform3D = Transform3D()
var collision_shape: Shape3D = null
var step_size = 0.5

# By default we show a capsule to indicate where the player lands.
# Turn on editable children,
# hide the capsule,
# and add your own player character as child.
@onready var capsule: MeshInstance3D = get_node("Target/Player_figure/Capsule")

func _update_player_height():
	if collision_shape:
		collision_shape.height = player_height - (2.0 * player_radius)

	if capsule:
		capsule.mesh.mid_height = player_height - (2.0 * player_radius)
		capsule.position = Vector3(0.0, player_height/2.0, 0.0)

func _update_player_radius():
	if collision_shape:
		collision_shape.height = player_height - (2.0 * player_radius)
		collision_shape.radius = player_radius

	if capsule:
		capsule.mesh.mid_height = player_height - (2.0 * player_radius)
		capsule.mesh.radius = player_radius

func _get_configuration_warning():
	if camera == NodePath():
		return "You need to assign a camera"
	
	return ""

func _ready():
	if !Engine.editor_hint:
		# We should be a child of an XRController3D and it should be a child or our XROrigin3D
		origin_node = get_node("../..")
		
		# It's inactive when we start
		$Teleport.visible = false
		$Target.visible = false
		
		# Scale to our world scale
		$Teleport.mesh.size = Vector2(0.05 * ws, 1.0)
		$Target.mesh.size = Vector2(ws, ws)
		$Target/Player_figure.scale = Vector3(ws, ws, ws)
		
		if camera:
			camera_node = get_node(camera)
		else:
			# see if we can find our default
			camera_node = origin_node.get_node('XRCamera')
		
		# get our capsule shape
		collision_shape = $CollisionShape3D.shape
		$CollisionShape3D.shape = null
		
		# now remove our collision shape, we are not using our kinematic body
		remove_child($CollisionShape3D)
	else:
		# don't run the physics process in the editor
		set_physics_process(false)
	
	# call set player to ensure our collision shape is sized
	_update_player_height()
	_update_player_radius()

func _physics_process(delta):
	if !Engine.editor_hint:
		# We should be the child or the controller on which the teleport is implemented
		var controller = get_parent()
		
		if !origin_node:
			return
		
		if !camera_node:
			return
		
		# if we're not enabled no point in doing mode
		if !enabled:
			# reset these
			is_teleporting = false;
			$Teleport.visible = false
			$Target.visible = false
			
			# and stop this from running until we enable again
			set_physics_process(false)
			return
		
		# check if our world scale has changed..
		var new_ws = XRServer.world_scale
		if ws != new_ws:
			ws = new_ws
			$Teleport.mesh.size = Vector2(0.05 * ws, 1.0)
			$Target.mesh.size = Vector2(ws, ws)
			$Target/Player_figure.scale = Vector3(ws, ws, ws)
		
		if controller and controller.get_is_active() and controller.is_button_pressed(teleport_button):
			if !is_teleporting:
				is_teleporting = true
				$Teleport.visible = true
				$Target.visible = true
				teleport_rotation = 0.0
			
			# get our physics engine state
			var space = PhysicsServer3D.body_get_space(self.get_rid())
			var state = PhysicsServer3D.space_get_direct_state(space)
			var query = PhysicsShapeQueryParameters3D.new()
			
			# init stuff about our query that doesn't change
			query.collision_mask = collision_mask
			query.margin = get_safe_margin()
			query.shape_rid = collision_shape.get_rid()
			
			# make a transform for offseting our shape
			var shape_transform = Transform3D(Basis(), Vector3(0.0, player_height / 2.0, 0.0))
			
			# update location
			var teleport_global_transform = $Teleport.global_transform
			var target_global_origin = teleport_global_transform.origin
			var down = Vector3(0.0, -1.0 / ws, 0.0)
			
			############################################################
			# New teleport logic
			# We're going to use test move in steps to find out where we hit something...
			# This can be optimised loads by determining the lenght based on the angle between sections extending the length when we're in a flat part of the arch
			# Where we do get a collission we may want to fine tune the collision
			var cast_length = 0.0
			var fine_tune = 1.0
			var hit_something = false
			var max_slope_cos = cos(deg2rad(max_slope))
			for i in range(1,26):
				var new_cast_length = cast_length + (step_size / fine_tune)
				var global_target = Vector3(0.0, 0.0, -new_cast_length)
				
				# our quadratic values
				var t = global_target.z / strength
				var t2 = t * t
				
				# target to world space
				global_target = teleport_global_transform * global_target
				
				# adjust for gravity
				global_target += down * t2
				
				# test our new location for collisions
				query.transform = Transform3D(Basis(), global_target) * shape_transform
				var cast_result = state.collide_shape(query, 10)
				if cast_result.is_empty():
					# we didn't collide with anything so check our next section...
					cast_length = new_cast_length
					target_global_origin = global_target
				elif (fine_tune <= 16.0):
					# try again with a small step size
					fine_tune *= 2.0
				else:
					# if we don't collide make sure we keep using our current origin point
					var collided_at = target_global_origin
					
					# check for collision
					if global_target.y > target_global_origin.y:
						# if we're moving up, we hit the ceiling of something, we don't really care what
						is_on_floor = false
					else:
						# now we cast a ray downwards to see if we're on a surface
						var start_pos = target_global_origin + (Vector3.UP * 0.5 * player_height)
						var end_pos = target_global_origin - (Vector3.UP * 1.1 * player_height)
						
						var intersects = state.intersect_ray(start_pos, end_pos, [], collision_mask)
						if intersects.is_empty():
							is_on_floor = false
						else:
							# did we collide with a floor or a wall?
							floor_normal = intersects["normal"]
							var dot = floor_normal.dot(Vector3.UP)
							
							if dot > max_slope_cos:
								is_on_floor = true
							else:
								is_on_floor = false
							
							# Update our collision point if it's moved enough, this solves a little bit of jittering
							var diff = collided_at - intersects["position"]
							
							if diff.length() > 0.1:
								collided_at = intersects["position"]
					
					# we are colliding, find our if we're colliding on a wall or floor, one we can do, the other nope...
					cast_length += (collided_at - target_global_origin).length()
					target_global_origin = collided_at
					hit_something = true
					break
			
			# and just update our shader
			var teleport_material = $Teleport.get_surface_override_material(0)
			var target_material = $Target.get_surface_override_material(0)
			teleport_material.set_shader_param("scale_t", 1.0 / strength)
			teleport_material.set_shader_param("ws", ws)
			teleport_material.set_shader_param("length", cast_length)
			if hit_something:
				var color = can_teleport_color
				var normal = Vector3.UP
				if is_on_floor:
					# if we're on the floor we'll reorientate our target to match.
					normal = floor_normal
					can_teleport = true
				else:
					can_teleport = false
					color = cant_teleport_color
				
				# check our axis to see if we need to rotate
				teleport_rotation += (delta * controller.get_joystick_axis(0) * -4.0)
				
				# update target and colour
				var target_basis = Basis()
				target_basis.z = Vector3(teleport_global_transform.basis.z.x, 0.0, teleport_global_transform.basis.z.z).normalized()
				target_basis.y = normal
				target_basis.x = target_basis.y.cross(target_basis.z)
				target_basis.z = target_basis.x.cross(target_basis.y)
				
				target_basis = target_basis.rotated(normal, teleport_rotation)
				last_target_transform.basis = target_basis
				last_target_transform.origin = target_global_origin + Vector3(0.0, 0.001, 0.0)
				$Target.global_transform = last_target_transform
				
				teleport_material.set_shader_param("mix_color", color)
				target_material.albedo_color = color
				$Target.visible = can_teleport
			else:
				can_teleport = false
				$Target.visible = false
				teleport_material.set_shader_param("mix_color", no_collision_color)
		elif is_teleporting:
			if can_teleport:
				
				# make our target horizontal again
				var new_transform = last_target_transform
				new_transform.basis.y = Vector3(0.0, 1.0, 0.0)
				new_transform.basis.x = new_transform.basis.y.cross(new_transform.basis.z).normalized()
				new_transform.basis.z = new_transform.basis.x.cross(new_transform.basis.y).normalized()
				
				# find out our user's feet's transformation
				var cam_transform = camera_node.transform
				var user_feet_transform = Transform3D()
				user_feet_transform.origin = cam_transform.origin
				user_feet_transform.origin.y = 0 # the feet are on the ground, but have the same X,Z as the camera
				
				# ensure this transform is upright
				user_feet_transform.basis.y = Vector3(0.0, 1.0, 0.0)
				user_feet_transform.basis.x = user_feet_transform.basis.y.cross(cam_transform.basis.z).normalized()
				user_feet_transform.basis.z = user_feet_transform.basis.x.cross(user_feet_transform.basis.y).normalized()
				
				# now move the origin such that the new global user_feet_transform would be == new_transform
				origin_node.global_transform = new_transform * user_feet_transform.inverse()
			
			# and disable
			is_teleporting = false;
			$Teleport.visible = false
			$Target.visible = false
