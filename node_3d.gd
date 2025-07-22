extends Node3D
class_name SimpleCamera

@export var move_speed: float = 5.0
@export var look_sensitivity: float = 0.002
@export var vertical_move_speed: float = 5.0

@export var camera_path: NodePath
var camera: Camera3D

var yaw: float = 0.0
var pitch: float = 0.0

func _ready():
	# Create and add a camera if not already existing
	camera = get_node(camera_path)
	camera.current = true
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if not DisplayServer.window_is_focused() or Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			if event is InputEventKey and event.pressed and not event.echo:
				if event.keycode == KEY_ESCAPE:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseMotion:
		yaw -= event.relative.x * look_sensitivity
		pitch -= event.relative.y * look_sensitivity# * -1
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89)) # Prevent flipping over


func _process(delta):
	# Rotation
	var up = Vector3.UP
	var current_basis = global_transform.basis
	var forward = -current_basis.z.normalized()
	var right = up.cross(forward).normalized()
	
	#if yaw != 0.0:
		#forward = forward.rotated(up, -yaw)
		#right = up.cross(forward).normalized()
		#yaw = 0.0
		
	var pitch_forward = forward.rotated(right, pitch)
	var camera_up = pitch_forward.cross(right).normalized()

	# Apply new basis
	#global_transform.basis = Basis(right, up, -forward).orthonormalized()
	#camera.global_transform.basis = Basis(right, camera_up, -pitch_forward).orthonormalized()
	var rotation_basis := Basis()
	rotation_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

	camera.global_transform = Transform3D(rotation_basis, global_position)

	# Movement
	var direction = Vector3.ZERO
	var camera_forward = -camera.global_transform.basis.z.normalized()
	var camera_right = camera.global_transform.basis.x.normalized()

	if Input.is_action_pressed("move_forward"):
		direction += camera_forward
	if Input.is_action_pressed("move_backward"):
		direction -= camera_forward
	if Input.is_action_pressed("move_left"):
		direction -= camera_right
	if Input.is_action_pressed("move_right"):
		direction += camera_right
	if Input.is_action_pressed("move_up"):
		direction += up
	if Input.is_action_pressed("move_down"):
		direction -= up

	#var speed_multiplier = 10.0 if Input.is_action_pressed("move_fast") else 1.0
	var speed_multiplier = 1.0

	if direction != Vector3.ZERO:
		global_position += direction.normalized() * move_speed * speed_multiplier * delta
