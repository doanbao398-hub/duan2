extends Entity

# --- THÔNG SỐ CẤU HÌNH ---
@export var move_speed: float = 180.0         # Có thể thoải mái tăng tốc độ ở đây mà không sợ bị đứng yên
@export var jump_force: float = -420.0
@export var skill_jump_force: float = -750.0  # Lực nhảy cao hơn khi dùng skill
@export var gravity: float = 980.0
@export var attack_damage: int = 20
@export var skill_damage: int = 40            # Sát thương đòn Jump Skill
@export var skill_chance: float = 0.1       # Tỷ lệ kích hoạt skill khi đánh
@export var heal_chance: float = 0.3         # 20% tỷ lệ hồi máu khi máu dưới 60%
@export var heal_percent: float = 0.15       # Hồi 15% máu tối đa

# --- CÁC NODE LIÊN QUAN ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var patrol_area: Area2D = $PatrolArea
@onready var melee_range: Area2D = $MeleeRange
@onready var wall_detector: RayCast2D = $WallDetector

# --- TRẠNG THÁI AI ---
enum State { 
	PRAY_LOOP, 
	STANDING_UP, 
	CHASE, 
	ATTACK, 
	HEAL,           # Trạng thái hồi máu
	SKILL_JUMP,     # Nhảy vọt lên
	SKILL_HOVER,    # Lơ lửng trên không
	SKILL_FALLING,  # Lao xuống (Loop frame 0-3 & Tracking siêu nhanh)
	SKILL_LANDING,  # Chạm đất/chạm player (Chạy từ frame 4 trở đi)
	DEAD 
}
var current_state: State = State.PRAY_LOOP

var player_ref: Node2D = null
var is_player_in_patrol: bool = false
var is_player_in_melee: bool = false
var is_attacking: bool = false

# Biến bổ trợ cho Jump Skill
var skill_has_target: bool = false

func _ready() -> void:
	super._ready()
	add_to_group("Enemy")

	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	patrol_area.body_entered.connect(_on_patrol_area_body_entered)
	patrol_area.body_exited.connect(_on_patrol_area_body_exited)
	
	melee_range.body_entered.connect(_on_melee_range_body_entered)
	melee_range.body_exited.connect(_on_melee_range_body_exited)
	
	wall_detector.enabled = true
	animated_sprite.play("pray")

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	# Áp dụng trọng lực (Trừ lúc đang lơ lửng gồng SKILL_HOVER)
	if not is_on_floor() and current_state != State.SKILL_HOVER:
		velocity.y += gravity * delta

	match current_state:
		State.PRAY_LOOP, State.STANDING_UP, State.HEAL:
			velocity.x = 0

		State.CHASE:
			if player_ref and is_instance_valid(player_ref):
				# Nếu Player đang ở trong vùng MeleeRange thì chuyển sang ATTACK
				if is_player_in_melee:
					current_state = State.ATTACK
					velocity.x = 0
				else:
					var direction = player_ref.global_position.x - global_position.x
					
					# Kiểm tra nếu cách đủ xa thì di chuyển
					if abs(direction) > 5.0:
						var facing_left = direction < 0
						if animated_sprite.flip_h != facing_left:
							animated_sprite.flip_h = facing_left
							melee_range.position.x = -abs(melee_range.position.x) if facing_left else abs(melee_range.position.x)
							var ray_len = abs(wall_detector.target_position.x)
							if ray_len == 0: ray_len = 30.0
							wall_detector.target_position = Vector2(-ray_len if facing_left else ray_len, 0)
						
						velocity.x = sign(direction) * move_speed
					else:
						velocity.x = 0

					wall_detector.force_raycast_update()
					if is_on_floor() and (wall_detector.is_colliding() or is_on_wall()):
						velocity.y = jump_force

					if not is_on_floor():
						if animated_sprite.animation != "jump":
							animated_sprite.play("jump")
					else:
						if animated_sprite.animation != "idle":
							animated_sprite.play("idle")
			else:
				velocity.x = 0

		State.ATTACK:
			velocity.x = 0
			if not is_attacking:
				start_random_attack()

		# --- CÁC TRẠNG THÁI SKILL ---
		State.SKILL_JUMP:
			pass

		State.SKILL_HOVER:
			# Khóa cố định trên không
			velocity = Vector2.ZERO

		State.SKILL_FALLING:
			# ĐỊNH VỊ SIÊU TỐC THEO PLAYER TRONG KHI ĐANG LAO XUỐNG
			if skill_has_target and player_ref and is_instance_valid(player_ref):
				var diff_x = player_ref.global_position.x - global_position.x
				
				if abs(diff_x) > 5.0:
					var facing_left = diff_x < 0
					if animated_sprite.flip_h != facing_left:
						animated_sprite.flip_h = facing_left
						melee_range.position.x = -abs(melee_range.position.x) if facing_left else abs(melee_range.position.x)
					
					# Di chuyển nhanh theo trục X đuổi theo Player
					velocity.x = sign(diff_x) * (move_speed * 1.8)
				else:
					velocity.x = 0
			else:
				velocity.x = 0

			# Tăng tốc độ rơi Y
			velocity.y += gravity * 2.5 * delta

			# Tự động chuyển sang SKILL_LANDING khi chạm đất hoặc chạm vào Player
			if is_on_floor() or is_player_in_melee:
				trigger_skill_landing()

		State.SKILL_LANDING:
			velocity.x = 0

	move_and_slide()

# --- HÀM CHỌN TẤN CÔNG HOẶC HỒI MÁU ---
func start_random_attack() -> void:
	is_attacking = true
	
	# Kiểm tra điều kiện: Máu < 60% (dùng current_health từ Entity) và random trúng 20%
	if float(current_health) < float(max_health) * 0.6 and randf() <= heal_chance:
		start_heal_sequence()
		return
	
	# Kiểm tra tỷ lệ kích hoạt Jump Skill
	if randf() <= skill_chance:
		start_jump_skill_sequence()
		return

	# Đánh thường ngẫu nhiên
	var attack_list = ["attack1", "attack2"]
	var random_attack = attack_list.pick_random()
	animated_sprite.play(random_attack)
	deal_damage_to_player(attack_damage)

# --- CHUỖI XỬ LÝ HỒI MÁU ---
func start_heal_sequence() -> void:
	current_state = State.HEAL
	animated_sprite.play("Health")

# --- CHUỖI XỬ LÝ JUMP SKILL ---
func start_jump_skill_sequence() -> void:
	current_state = State.SKILL_JUMP
	velocity.y = skill_jump_force
	animated_sprite.play("jump")

# --- KÍCH HOẠT TIẾP ĐẤT / CHẠM MỤC TIÊU ---
func trigger_skill_landing() -> void:
	current_state = State.SKILL_LANDING
	deal_damage_to_player(skill_damage)
	
	if animated_sprite.animation == "jumpskill" and animated_sprite.frame <= 3:
		animated_sprite.frame = 4
		animated_sprite.play("jumpskill")

# --- GÂY SÁT THƯƠNG CHO PLAYER ---
func deal_damage_to_player(damage_amount: int) -> void:
	if not melee_range: return
	var bodies = melee_range.get_overlapping_bodies()
	for body in bodies:
		if _is_player(body) and body.has_method("take_damage"):
			body.take_damage(damage_amount)

# --- XỬ LÝ FRAME CHANGED ---
func _on_frame_changed() -> void:
	if current_state == State.DEAD: return

	if animated_sprite.animation == "pray" and current_state == State.PRAY_LOOP:
		if animated_sprite.frame == 8:
			if is_player_in_patrol:
				current_state = State.STANDING_UP
			else:
				animated_sprite.frame = 4

	if current_state == State.SKILL_FALLING and animated_sprite.animation == "jumpskill":
		if animated_sprite.frame > 3:
			animated_sprite.frame = 0

# --- XỬ LÝ KHI KẾT THÚC ANIMATION ---
func _on_animation_finished() -> void:
	if current_state == State.DEAD: return

	match animated_sprite.animation:
		"pray":
			if current_state == State.STANDING_UP:
				if is_player_in_melee:
					current_state = State.ATTACK
					start_random_attack()
				elif is_player_in_patrol:
					current_state = State.CHASE

		"attack1", "attack2":
			is_attacking = false
			if is_player_in_melee:
				start_random_attack()
			elif is_player_in_patrol:
				current_state = State.CHASE
			else:
				reset_to_pray()

		"Health":
			# Gọi hàm heal() có sẵn của class cha Entity để hồi 15% máu
			heal(int(float(max_health) * heal_percent))
			is_attacking = false
			if is_player_in_melee:
				current_state = State.ATTACK
			elif is_player_in_patrol:
				current_state = State.CHASE
			else:
				reset_to_pray()

		"jump":
			if current_state == State.SKILL_JUMP:
				current_state = State.SKILL_HOVER
				animated_sprite.play("jump2")

		"jump2":
			if current_state == State.SKILL_HOVER:
				current_state = State.SKILL_FALLING
				if is_player_in_patrol and player_ref and is_instance_valid(player_ref):
					skill_has_target = true
				else:
					skill_has_target = false

				animated_sprite.play("jumpskill")
				animated_sprite.frame = 0

		"jumpskill":
			if current_state == State.SKILL_LANDING:
				is_attacking = false
				if is_player_in_melee:
					current_state = State.ATTACK
				elif is_player_in_patrol:
					current_state = State.CHASE
				else:
					reset_to_pray()

# --- SỰ KIỆN PATROL AREA ---
func _on_patrol_area_body_entered(body: Node) -> void:
	if current_state == State.DEAD: return
	if _is_player(body):
		is_player_in_patrol = true
		player_ref = body

func _on_patrol_area_body_exited(body: Node) -> void:
	if current_state == State.DEAD: return
	if _is_player(body):
		is_player_in_patrol = false
		player_ref = null
		
		if current_state not in [State.ATTACK, State.HEAL, State.PRAY_LOOP, State.SKILL_JUMP, State.SKILL_HOVER, State.SKILL_FALLING, State.SKILL_LANDING]:
			reset_to_pray()

# --- SỰ KIỆN MELEE RANGE ---
func _on_melee_range_body_entered(body: Node) -> void:
	if current_state == State.DEAD: return
	if _is_player(body):
		is_player_in_melee = true
		
		if current_state == State.SKILL_FALLING:
			trigger_skill_landing()
		elif current_state == State.CHASE:
			current_state = State.ATTACK

func _on_melee_range_body_exited(body: Node) -> void:
	if current_state == State.DEAD: return
	if _is_player(body):
		is_player_in_melee = false

# --- KIỂM TRA NHẬN DẠNG PLAYER ---
func _is_player(body: Node) -> bool:
	return body.is_in_group("Player") or body.name == "ngoaihinh" or body.name == "player" or body.get_parent().name == "player"

# --- KHÔI PHỤC TRẠNG THÁI PRAY BAN ĐẦU ---
func reset_to_pray() -> void:
	is_attacking = false
	current_state = State.PRAY_LOOP
	animated_sprite.play("pray")
	animated_sprite.frame = 0

# --- GHI ĐÈ HÀM DIE CỦA ENTITY (NẾU CẦN CHẠY ANIMATION CHẾT) ---
func die() -> void:
	current_state = State.DEAD
	set_physics_process(false)
	velocity = Vector2.ZERO
	
	if has_node("vungvacham"):
		$vungvacham.set_deferred("disabled", true)
	if health_bar:
		health_bar.hide()

	if animated_sprite and animated_sprite.sprite_frames.has_animation("die"):
		animated_sprite.play("die")
		await animated_sprite.animation_finished

	super.die()
