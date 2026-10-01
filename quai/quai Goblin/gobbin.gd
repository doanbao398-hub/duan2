extends Entity

const SPEED = 90.0
var jump_velocity: float = -350.0

@export var attack_damage: int = 5

# --- ONREADY NODES ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D
@onready var melee_range: Area2D = $MeleeRange
@onready var skill_range: Area2D = $SkillRange
@onready var wall_detector: RayCast2D = $WallDetector
@onready var bomb_node: Area2D = $Boom

# Ranh giới tuần tra
var min_x: float = 0.0
var max_x: float = 0.0
var direction: int = 1

var player: Node2D = null
var is_in_melee_range: bool = false
var is_in_skill_range: bool = false
var is_attacking: bool = false
var is_dead: bool = false 
var combo_step: int = 0

var skill_timer: float = 0.0
const SKILL_COOLDOWN: float = 4.0

func _ready() -> void:
	super._ready()
	
	_setup_patrol_bounds()
	
	if area_2d:
		area_2d.body_entered.connect(_on_detect_entered)
		area_2d.body_exited.connect(_on_detect_exited)
	
	if melee_range:
		melee_range.body_entered.connect(_on_melee_entered)
		melee_range.body_exited.connect(_on_melee_exited)

	if skill_range:
		skill_range.body_entered.connect(_on_skill_entered)
		skill_range.body_exited.connect(_on_skill_exited)

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

		# ƯU TIÊN 1: Trong SkillRange + Hồi CD -> Ném bom (attack3)
		if is_in_skill_range and skill_timer >= SKILL_COOLDOWN:
			use_skill_attack3()
		# ƯU TIÊN 2: Trong MeleeRange -> Đánh cận chiến (attack / attack2)
		elif is_in_melee_range:
			use_combo_attack()
		# ƯU TIÊN 3: Chưa tới tầm -> Tiến lại gần Player
		else:
			velocity.x = sign(dist_x) * SPEED
			if anim_sprite and anim_sprite.sprite_frames.has_animation("walk"):
				anim_sprite.play("walk")
			check_and_jump()
	else:
		velocity.x = direction * SPEED
		if anim_sprite and anim_sprite.sprite_frames.has_animation("walk"):
			anim_sprite.play("walk")
		
		if anim_sprite: anim_sprite.flip_h = (direction < 0)
		update_wall_detector_direction(direction)
		
		if direction > 0 and global_position.x >= max_x:
			direction = -1
		elif direction < 0 and global_position.x <= min_x:
			direction = 1

		check_and_jump()

	move_and_slide()

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
	var anim_name = "attack" if combo_step == 1 else "attack2"
	
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
		deal_damage_if_in_range(attack_damage)
		await anim_sprite.animation_finished
		
	if is_dead: return
	is_attacking = false

func use_skill_attack3() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity.x = 0
	skill_timer = 0.0
	
	if anim_sprite.sprite_frames.has_animation("attack3"):
		anim_sprite.play("attack3")
		await anim_sprite.animation_finished
		
		if not is_dead:
			throw_bomb()
		
	if is_dead: return
	is_attacking = false

func throw_bomb() -> void:
	if not bomb_node: return
	
	var dir: int = -1 if (anim_sprite and anim_sprite.flip_h) else 1
	if bomb_node.has_method("activate_bomb"):
		# Truyền hướng và vị trí toàn cục hiện tại của Goblin
		bomb_node.activate_bomb(dir, global_position)

func _is_player(body: Node) -> bool:
	return body.is_in_group("Player") or body.name in ["ngoaihinh", "player", "Player"]

func _on_detect_entered(body: Node) -> void:
	if _is_player(body):
		player = body

func _on_detect_exited(body: Node) -> void:
	if _is_player(body) and body == player:
		player = null
		is_in_melee_range = false
		is_in_skill_range = false

func _on_melee_entered(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = true

func _on_melee_exited(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = false

func _on_skill_entered(body: Node) -> void:
	if _is_player(body):
		is_in_skill_range = true

func _on_skill_exited(body: Node) -> void:
	if _is_player(body):
		is_in_skill_range = false
