extends Area2D

# --- CONFIGURATION ---
@export var speed: float = 280.0              # Tốc độ bay của đạn
@export var damage: int = 15                  # Sát thương
@export var homing_steer_speed: float = 12.0   # Tốc độ bẻ góc ngắm
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
	
	body_entered.connect(_on_hitbox_body_entered)
	area_entered.connect(_on_hitbox_body_entered)
	
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.area_entered.connect(_on_detection_body_entered)
	
	deactivate()

func _physics_process(delta: float) -> void:
	if not is_active or is_exploding:
		return

	# 1. Hết thời gian sống -> Nổ
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		explode_and_deactivate()
		return

	# 2. BẺ GÓC ĐẮM THẲNG VÀO PLAYER (TÂM BỤNG)
	if is_instance_valid(target_player):
		# Lấy vị trí thực giữa thân Player (Tránh ngắm vào HealthBar trên đầu)
		var target_pos: Vector2 = target_player.global_position
		
		# Nếu player có CollisionShape2D thì lấy đúng tâm va chạm của Player
		if target_player.has_node("CollisionShape2D"):
			target_pos = target_player.get_node("CollisionShape2D").global_position

		# Tính góc xoay hướng thẳng về Player
		var desired_angle: float = (target_pos - global_position).angle()
		
		# Bẻ góc mượt nhưng không bị xèo lướt qua
		rotation = lerp_angle(rotation, desired_angle, homing_steer_speed * delta)

	# Bay thẳng về phía trước theo góc xoay
	var move_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	global_position += move_direction * speed * delta

# Kích hoạt bắn đạn
func fire(player_ref: Node2D, _facing_direction: int = 1) -> void:
	is_active = true
	is_exploding = false
	lifetime_timer = 0.0
	target_player = null
	
	show()
	
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
		
	if detection_area:
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", false)
		
	if anim_sprite:
		anim_sprite.play("danbay")
		anim_sprite.flip_h = false

	# Lấy đúng node Player chính
	var valid_p = _find_player_node(player_ref)
	if valid_p:
		target_player = valid_p
	else:
		_scan_overlapping_targets()

# CƠ CHẾ NỔ
func explode_and_deactivate() -> void:
	if is_exploding:
		return
		
	is_exploding = true
	is_active = false
	target_player = null
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if detection_area:
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)

	if anim_sprite and anim_sprite.sprite_frames.has_animation("danno"):
		anim_sprite.play("danno")
		await anim_sprite.animation_finished
		
	deactivate()

# Tắt và reset đạn
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

# --- SIGNALS DETECTION ---
func _on_detection_body_entered(node: Node) -> void:
	if not is_active or is_exploding:
		return
	var found_player = _find_player_node(node)
	if found_player:
		target_player = found_player

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
	elif node is TileMap or node is TileMapLayer or node is StaticBody2D:
		explode_and_deactivate()

# BỘ LỌC CHUẨN: Bỏ qua HealthBar, UI, chỉ nhận duy nhất Node nhân vật Player
func _find_player_node(node: Node) -> Node2D:
	if node == null or not is_instance_valid(node):
		return null
		
	# Bỏ qua nếu lỡ va vào HealthBar hoặc UI
	var node_name = node.name.to_lower()
	if "health" in node_name or "bar" in node_name or "ui" in node_name:
		if node.get_parent():
			return _find_player_node(node.get_parent())
		return null

	if node.is_in_group("player") or node.is_in_group("Player"):
		return node as Node2D
		
	if node is CharacterBody2D and "player" in node_name:
		return node as Node2D
		
	if node.get_parent() and is_instance_valid(node.get_parent()):
		if node.get_parent().is_in_group("player") or node.get_parent().is_in_group("Player"):
			return node.get_parent() as Node2D
			
	return null
