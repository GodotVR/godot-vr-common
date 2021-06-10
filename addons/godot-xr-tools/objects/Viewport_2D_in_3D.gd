@tool
extends Node3D

signal pointer_entered
signal pointer_exited

@export var enabled = true:
	set(new_value):
		enabled = new_value
		_update_enabled()
@export var screen_size = Vector2(3.0, 2.0):
	set(new_value):
		screen_size = new_value
		_update_screen_size()
@export var viewport_size = Vector2(300.0, 200.0):
	set(new_value):
		viewport_size = new_value
		_update_viewport_size()
@export var transparent = true:
	set(new_value):
		transparent = new_value
		_update_transparent()
@export var scene : PackedScene = null:
	set(new_value):
		scene = new_value
		_update_scene()

# Need to replace this with proper solution once support for layer selection has been added
@export_flags_3d_physics var collision_layer = 15:
	set(new_value):
		collision_layer = new_value
		_update_collision_layer()

var is_ready = false
var scene_node : Variant = null

func _update_enabled():
	if is_ready:
		$StaticBody/CollisionShape3D.disabled = !enabled

func _update_screen_size():
	if is_ready:
		$Screen.mesh.size = screen_size
		$StaticBody.screen_size = screen_size
		$StaticBody/CollisionShape3D.shape.extents = Vector3(screen_size.x * 0.5, screen_size.y * 0.5, 0.01)

func _update_viewport_size():
	if is_ready:
		$Viewport.size = viewport_size
		$StaticBody.viewport_size = viewport_size
		var material : StandardMaterial3D = $Screen.get_surface_override_material(0)
		if material:
			material.albedo_texture = $Viewport.get_texture()
		else:
			print_debug("Couldn't access material")

func _update_transparent():
	if is_ready:
		var material : StandardMaterial3D = $Screen.get_surface_override_material(0)
		if material:
			material.flags_transparent = transparent
		else:
			print_debug("Couldn't access material")
		$Viewport.transparent_bg = transparent

func _update_collision_layer():
	if is_ready:
		$StaticBody.collision_layer = collision_layer

func _update_scene():
	if is_ready:
		# out with the old
		if scene_node:
			$Viewport.remove_child(scene_node)
			scene_node.queue_free()

		# in with the new
		if scene:
			scene_node = scene.instantiate()
			$Viewport.add_child(scene_node)

func get_scene_instance():
	return scene_node

func connect_scene_signal(which, on, callback):
	if scene_node:
		scene_node.connect(which, on, callback)

# Called when the node enters the scene tree for the first time.
func _ready():
	# apply properties
	is_ready = true
	_update_enabled()
	_update_screen_size()
	_update_viewport_size()
	_update_scene()
	_update_collision_layer()
	_update_transparent()
