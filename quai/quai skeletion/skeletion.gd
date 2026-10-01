extends Entity

const SPEED = 90.0
var jump_velocity: float = -350.0

@export var attack_damage: int = 5

# --- ONREADY NODES (Cây Scene Skeleton) ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D
@onready var melee_range: Area2D = $MeleeRange
@onready var wall_detector: RayCast2D = $WallDetector

# Onready các Marker2D định vị thanh máu
@onready var hp_right_marker: Marker2D = get_node_or_null("HealthBarRight")
@onready var hp_left_marker: Marker2D = get_node_or_null("HealthBarLeft")

# Biến lưu vị trí X ban đầu của MeleeRange để lật hướng
var melee_range_initial_x: float = 0.0

# Ranh giới tuần tra tự động lấy theo Area2D
var min_x: float = 0.0
var max_x: float = 0.0
var direction: int = 1

var player: Node2D = null
var is_in_melee_range: bool = false
var is_attacking: bool = false
var is_dead: bool = false 
var combo_step: int = 0

# Cooldown cho chiêu attack3
var skill_timer: float = 0.0
const SKILL_COOLDOWN: float = 4.0

func _ready() -> void:
	super._ready()
	
	if melee_range:
		melee_range_initial_x = abs(melee_range.position.x)
	
	_setup_patrol_bounds()
	
	if area_2d:
		area_2d.body_entered.connect(_on_detect_entered)
		area_2d.body_exited.connect(_on_detect_exited)
	
	if melee_range:
		melee_range.body_entered.connect(_on_melee_entered)
		melee_range.body_exited.connect(_on_melee_exited)

func _setup_patrol_bounds() -> void:
	if area_2d and area_2d.has_node("CollisionShape2D"):
		var shape_node = area_2d.get_node("CollisionShape2D")
		if shape_node.shape is RectangleShape2D:
			var width = shape_node.shape.size.x
			var center_x = shape_node.global_position.x
			
			min_x = center_x - (width / 2.0)
			max_x = center_x + (width / 2.0)
			return

	min_x = global_position.x - 150.0
	max_x = global_position.x + 150.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Tích thời gian hồi chiêu khi nhìn thấy Player
	if player:
		skill_timer += delta

	if is_attacking:
		move_and_slide()
		return

	# TRƯỜNG HỢP 1: PHÁT HIỆN PLAYER
	if player:
		var dist_x = player.global_position.x - global_position.x
		
		if dist_x != 0:
			var facing_dir = sign(dist_x)
			update_facing_direction(facing_dir < 0)

		# Đã vào tầm đánh -> Dừng di chuyển & dùng Skill hoặc Combo đánh thường
		if is_in_melee_range:
			velocity.x = 0
			if skill_timer >= SKILL_COOLDOWN:
				use_skill_attack3()
			else:
				use_combo_attack()
		else:
			velocity.x = sign(dist_x) * SPEED
			if anim_sprite and anim_sprite.sprite_frames.has_animation("walk"):
				anim_sprite.play("walk")
			check_and_jump()

	# TRƯỜNG HỢP 2: TUẦN TRA
	else:
		velocity.x = direction * SPEED
		if anim_sprite and anim_sprite.sprite_frames.has_animation("walk"):
			anim_sprite.play("walk")
		
		update_facing_direction(direction < 0)
		
		if direction > 0 and global_position.x >= max_x:
			direction = -1
		elif direction < 0 and global_position.x <= min_x:
			direction = 1

		check_and_jump()

	move_and_slide()

# --- HÀM CẬP NHẬT HƯỚNG QUAY MẶT, MELEERANGE, HEALTHBAR VÀ WALLDETECTOR ---
func update_facing_direction(is_facing_left: bool) -> void:
	var dir_factor = -1.0 if is_facing_left else 1.0
	
	if is_facing_left:
		if anim_sprite:
			anim_sprite.flip_h = true
		if melee_range:
			melee_range.position.x = -melee_range_initial_x
		if health_bar and hp_left_marker:
			health_bar.position = hp_left_marker.position
	else:
		if anim_sprite:
			anim_sprite.flip_h = false
		if melee_range:
			melee_range.position.x = melee_range_initial_x
		if health_bar and hp_right_marker:
			health_bar.position = hp_right_marker.position

	# Cập nhật hướng cho RayCast2D phát hiện tường
	if wall_detector:
		wall_detector.target_position.x = abs(wall_detector.target_position.x) * dir_factor

# --- HÀM COMBO ĐÁNH THƯỜNG (attack -> attack2) ---
func use_combo_attack() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity.x = 0
	
	# Luân phiên giữa attack và attack2
	combo_step = 1 if combo_step >= 2 else combo_step + 1
	var anim_name = "attack" if combo_step == 1 else "attack2"
	
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
		deal_damage_if_in_range(attack_damage)
		await anim_sprite.animation_finished
		
	is_attacking = false

# --- HÀM CHIÊU ĐẶC BIỆT (attack3) ---
func use_skill_attack3() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity.x = 0
	skill_timer = 0.0 # Reset đếm giờ hồi chiêu
	
	if anim_sprite.sprite_frames.has_animation("attack3"):
		anim_sprite.play("attack3")
		deal_damage_if_in_range(attack_damage * 2) # Đòn 3 gây gấp đôi sát thương
		await anim_sprite.animation_finished
		
	is_attacking = false

# --- XỬ LÝ CHẾT ---
func die() -> void:
	if is_dead: return
	is_dead = true
	
	set_physics_process(false)
	velocity = Vector2.ZERO
	
	if health_bar:
		health_bar.hide()
	
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
		
	if anim_sprite and anim_sprite.sprite_frames.has_animation("die"):
		anim_sprite.play("die")
		await anim_sprite.animation_finished

	super.die()

func check_and_jump() -> void:
	if wall_detector and (wall_detector.is_colliding() or is_on_wall()) and is_on_floor():
		velocity.y = jump_velocity

func deal_damage_if_in_range(damage_amount: int) -> void:
	if is_in_melee_range and player and player.has_method("take_damage"):
		player.take_damage(damage_amount)

func _is_player(body: Node) -> bool:
	return body.is_in_group("Player") or body.name in ["ngoaihinh", "player", "Player"]

func _on_detect_entered(body: Node) -> void:
	if _is_player(body):
		player = body

func _on_detect_exited(body: Node) -> void:
	if _is_player(body) and body == player:
		player = null
		is_in_melee_range = false

func _on_melee_entered(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = true

func _on_melee_exited(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = false
