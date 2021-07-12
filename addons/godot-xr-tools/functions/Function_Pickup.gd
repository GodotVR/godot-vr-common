extends Area3D

signal has_picked_up(what)
signal has_dropped

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

@export var pickup_range = 0.5:
	set(new_value):
		pickup_range = new_value
		_update_pickup_range()

@export var impulse_factor = 1.0
@export var pickup_button_id: Buttons = Buttons.VR_GRIP
@export var action_button_id: Buttons = Buttons.VR_TRIGGER
@export var max_samples = 5

var objects_in_area: Array
var closest_object: Variant = null
var picked_up_object: Variant = null

var last_transform: Transform3D
var linear_velocities: Array
var angular_velocities: Array

func _update_pickup_range():
	if $CollisionShape3D:
		$CollisionShape3D.shape.radius = pickup_range

func _get_linear_velocity():
	var velocity = Vector3(0.0, 0.0, 0.0)
	var count = linear_velocities.size()
	
	if count > 0:
		for v in linear_velocities:
			velocity = velocity + v
		
		velocity = velocity / count
	
	return velocity

func _get_angular_velocity():
	var velocity = Vector3(0.0, 0.0, 0.0)
	var count = angular_velocities.size()
	
	if count > 0:
		for v in angular_velocities:
			velocity = velocity + v
		
		velocity = velocity / count
	
	return velocity

func _on_Function_Pickup_entered(object):
	# add our object to our array if required
	if object.has_method('pick_up') and objects_in_area.find(object) == -1:
		objects_in_area.push_back(object)
		_update_closest_object()

func _on_Function_Pickup_exited(object):
	# remove our object from our array
	if objects_in_area.find(object) != -1:
		objects_in_area.erase(object)
		_update_closest_object()

func _update_closest_object():
	var new_closest_obj: Variant = null
	if !picked_up_object and !objects_in_area.is_empty():
		var new_closest_distance: float = 1000.0
		for object in objects_in_area:
			# only check objects that aren't already picked up
			if object.is_picked_up() == false:
				var delta_pos = object.global_transform.origin - global_transform.origin
				var distance = delta_pos.length()
				if distance < new_closest_distance:
					new_closest_obj = object
					new_closest_distance = distance
	
	if closest_object != new_closest_obj:
		# remove highlight on old object
		if closest_object:
			closest_object.decrease_is_closest()
		
		# add highlight to new object
		closest_object = new_closest_obj
		if closest_object:
			closest_object.increase_is_closest()

func drop_object():
	if picked_up_object:
		# let go of this object
		picked_up_object.let_go(_get_linear_velocity() * impulse_factor, _get_angular_velocity())
		picked_up_object = null
		emit_signal("has_dropped")

func _pick_up_object(p_object):
	# already holding this object, nothing to do
	if picked_up_object == p_object:
		return
	
	# holding something else? drop it
	if picked_up_object:
		drop_object()
	
	# and pick up our new object
	if p_object:
		picked_up_object = p_object
		picked_up_object.pick_up(self, get_parent())
		emit_signal("has_picked_up", picked_up_object)

func _on_button_pressed(p_button):
	if p_button == pickup_button_id:
		if picked_up_object and !picked_up_object.press_to_hold:
			drop_object()
		elif closest_object:
			_pick_up_object(closest_object)
	elif p_button == action_button_id:
		if picked_up_object and picked_up_object.has_method("action"):
			picked_up_object.action()

func _on_button_released(p_button):
	if p_button == pickup_button_id:
		if picked_up_object and picked_up_object.press_to_hold:
			drop_object()

func _ready():
	get_parent().connect("button_pressed", _on_button_pressed)
	get_parent().connect("button_released", _on_button_released)
	last_transform = global_transform
	
	# update now that our collision shape has been constructed
	_update_pickup_range()

func _process(delta):
	# Calculate our linear velocity
	var linear_velocity = (global_transform.origin - last_transform.origin) / delta
	linear_velocities.push_back(linear_velocity)
	if linear_velocities.size() > max_samples:
		linear_velocities.pop_front()
	
	# Calculate our angular velocity
	var delta_basis = global_transform.basis * last_transform.basis.inverse()
	var angular_velocity = delta_basis.get_euler() / delta
	angular_velocities.push_back(angular_velocity)
	if angular_velocities.size() > max_samples:
		angular_velocities.pop_front()
	
	last_transform = global_transform
	_update_closest_object()

