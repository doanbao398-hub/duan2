extends Entity

const SPEED = 90.0
var jump_velocity: float = -350.0

@export var attack_damage: int = 5

# --- ONREADY NODES DÀNH CHO QUÁI ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D
@onready var melee_range: Area2D = $MeleeRange
@onready var wall_detector: RayCast2D = $WallDetector

var start_x: float = 0.0
var patrol_distance: float = 150.0
var direction: int = 1

var player: Node2D = null
var is_in_melee_range: bool = false
var is_attacking: bool = false
var is_dead: bool = false # Chặn hành động khi đã chết
var combo_step: int = 0

var skill_timer: float = 0.0
const SKILL_COOLDOWN: float = 4.0

func _ready() -> void:
	super._ready()
	
	start_x = global_position.x
	
	if area_2d:
		area_2d.body_entered.connect(_on_detect_entered)
		area_2d.body_exited.connect(_on_detect_exited)
	
	if melee_range:
		melee_range.body_entered.connect(_on_melee_entered)
		melee_range.body_exited.connect(_on_melee_exited)

func _physics_process(delta: float) -> void:
	# Nếu đã chết thì dừng di chuyển
	if is_dead:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if player:
		skill_timer += delta

	if is_attacking:
		move_and_slide()
		return

	if player:
		var dist_x = player.global_position.x - global_position.x
		
		if dist_x != 0:
			var facing_dir = sign(dist_x)
			if anim_sprite: anim_sprite.flip_h = (facing_dir < 0)
			update_wall_detector_direction(facing_dir)

		if is_in_melee_range:
			velocity.x = 0
			if skill_timer >= SKILL_COOLDOWN:
				use_skill_attack3()
			else:
				use_combo_attack()
		else:
			velocity.x = sign(dist_x) * SPEED
			if anim_sprite: anim_sprite.play("walk")
			check_and_jump()
	else:
		velocity.x = direction * SPEED
		if anim_sprite: anim_sprite.play("walk")
		
		if anim_sprite: anim_sprite.flip_h = (direction < 0)
		update_wall_detector_direction(direction)
		
		if direction > 0 and global_position.x >= start_x + patrol_distance:
			direction = -1
		elif direction < 0 and global_position.x <= start_x - patrol_distance:
			direction = 1

		check_and_jump()

	move_and_slide()

# --- HIỆU ỨNG CHẾT NỐI TIẾP (cbdie -> die2) ---
func die() -> void:
	if is_dead: return
	is_dead = true
	
	set_physics_process(false)
	velocity = Vector2.ZERO
	
	# Ẩn thanh máu và tắt va chạm khi chết
	if health_bar:
		health_bar.hide()
	
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
		
	# 1. Chạy animation cbdie trước
	if anim_sprite and anim_sprite.sprite_frames.has_animation("cbdie"):
		anim_sprite.play("cbdie")
		await anim_sprite.animation_finished
		
	# 2. Chạy tiếp animation die2
	if anim_sprite and anim_sprite.sprite_frames.has_animation("die2"):
		anim_sprite.play("die2")
		await anim_sprite.animation_finished

	# Gọi hàm die() của Entity cha để thực hiện xóa quái (queue_free)
	super.die()

func check_and_jump() -> void:
	if wall_detector and (wall_detector.is_colliding() or is_on_wall()) and is_on_floor():
		velocity.y = jump_velocity

func update_wall_detector_direction(dir: float) -> void:
	if wall_detector:
		wall_detector.target_position.x = abs(wall_detector.target_position.x) * dir

func deal_damage_if_in_range(damage_amount: int) -> void:
	if is_in_melee_range and player and player.has_method("take_damage"):
		player.take_damage(damage_amount)

func use_combo_attack() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity.x = 0
	
	combo_step = 1 if combo_step >= 2 else combo_step + 1
	anim_sprite.play("attack" if combo_step == 1 else "attack2")
	
	deal_damage_if_in_range(attack_damage)
		
	await anim_sprite.animation_finished
	is_attacking = false

func use_skill_attack3() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity.x = 0
	skill_timer = 0.0
	
	anim_sprite.play("cbattack3")
	await anim_sprite.animation_finished
	
	if is_dead: return
	anim_sprite.play("attack3")
	deal_damage_if_in_range(attack_damage)
	
	await anim_sprite.animation_finished
	is_attacking = false

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
