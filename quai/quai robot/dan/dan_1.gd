extends Area2D

# --- CONFIGURATION ---
@export var speed: float = 290.0              # Tốc độ bay của đạn
@export var damage: int = 15                  # Sát thương
@export var homing_steer_speed: float = 14.0   # Tốc độ bẻ góc cực bén
@export var lifetime: float = 4.0             # Tự động hủy sau 4 giây

# --- NODE REFERENCES ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea

# --- INTERNAL VARIABLES ---
var target_player: Node2D = null
var is_active: bool = false
var is_exploding: bool = false
var initial_local_pos: Vector2 = Vector2.ZERO
var lifetime_timer: float = 0.0

func _ready() -> void:
	initial_local_pos = position
	
	# Signal va chạm gây sát thương (Hitbox)
	body_entered.connect(_on_hitbox_body_entered)
	area_entered.connect(_on_hitbox_body_entered)
	
	# Signal quét vùng DetectionArea
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)
		detection_area.area_entered.connect(_on_detection_body_entered)
		detection_area.area_exited.connect(_on_detection_body_exited)
	
	deactivate()

func _physics_process(delta: float) -> void:
	if not is_active or is_exploding:
		return

	# 1. Tự kích hoạt nổ khi hết thời gian sống (lifetime)
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		explode_and_deactivate()
		return

	# 2. Thuật toán Aim bám đuôi Player
	if is_instance_valid(target_player):
		var target_angle: float = (target_player.global_position - global_position).angle()
		var angle_diff: float = wrapf(target_angle - rotation, -PI, PI)
		rotation += clamp(angle_diff, -homing_steer_speed * delta, homing_steer_speed * delta)
	
	var move_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	global_position += move_direction * speed * delta

# Kích hoạt bắn đạn
func fire(player_ref: Node2D, _facing_direction: int = 1) -> void:
	is_active = true
	is_exploding = false
	lifetime_timer = 0.0
	target_player = null
	
	show()
	
	# Bật lại Va chạm
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
		
	if detection_area:
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", false)
		
	if anim_sprite:
		anim_sprite.play("danbay")
		anim_sprite.flip_h = false

	# Kiểm tra tham chiếu an toàn
	if is_instance_valid(player_ref):
		target_player = player_ref
	else:
		_scan_overlapping_targets()

# CƠ CHẾ NỔ: Phát animation "danno" trước khi biến mất
func explode_and_deactivate() -> void:
	if is_exploding:
		return
		
	is_exploding = true
	is_active = false
	target_player = null
	
	# Tắt va chạm lập tức để không gây sát thương nhiều lần
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if detection_area:
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)

	# Chạy hiệu ứng đạn nổ
	if anim_sprite and anim_sprite.sprite_frames.has_animation("danno"):
		anim_sprite.play("danno")
		await anim_sprite.animation_finished
		
	deactivate()

# Tắt và reset đạn về vị trí ban đầu
func deactivate() -> void:
	is_active = false
	is_exploding = false
	target_player = null
	hide()
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if detection_area:
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)
		
	if anim_sprite:
		anim_sprite.stop()
		
	position = initial_local_pos
	rotation = 0.0

# --- HELPER DETECTION ---
func _scan_overlapping_targets() -> void:
	if not detection_area:
		return
		
	for body in detection_area.get_overlapping_bodies():
		var found_p = _find_player_node(body)
		if found_p:
			target_player = found_p
			return
			
	for area in detection_area.get_overlapping_areas():
		var found_p = _find_player_node(area)
		if found_p:
			target_player = found_p
			return

# --- SIGNALS DETECTION ---
func _on_detection_body_entered(node: Node) -> void:
	if not is_active or is_exploding:
		return
	var found_player = _find_player_node(node)
	if found_player:
		target_player = found_player

func _on_detection_body_exited(node: Node) -> void:
	if not is_active or is_exploding:
		return
	var exited_player = _find_player_node(node)
	if exited_player and exited_player == target_player:
		target_player = null

# --- HITBOX & DAMAGE ---
func _on_hitbox_body_entered(node: Node) -> void:
	if not is_active or is_exploding:
		return
		
	if node == owner or node.is_in_group("enemy") or "robot" in node.name.to_lower():
		return

	var hit_player = _find_player_node(node)
	if hit_player:
		if hit_player.has_method("take_damage"):
			hit_player.take_damage(damage)
		explode_and_deactivate()
	elif node is TileMap or node is StaticBody2D:
		explode_and_deactivate()

func _find_player_node(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.is_in_group("player") or node.is_in_group("Player"):
		return node
	if node.has_method("take_damage") and "player" in node.name.to_lower():
		return node
	if node.get_parent() and is_instance_valid(node.get_parent()) and (node.get_parent().is_in_group("player") or node.get_parent().is_in_group("Player")):
		return node.get_parent()
	return null
