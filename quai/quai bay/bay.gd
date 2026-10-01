extends Entity

const SPEED = 80.0
@export var attack_damage: int = 5

# Mức độ hạ độ cao trục Y khi truy đuổi Player
@export var target_y_offset: float = 25.0

# --- ONREADY NODES ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D
@onready var melee_range: Area2D = $MeleeRange

# Onready các Marker2D định vị thanh máu
@onready var hp_right_marker: Marker2D = get_node_or_null("HealthBarRight")
@onready var hp_left_marker: Marker2D = get_node_or_null("HealthBarLeft")

# Biến lưu vị trí X ban đầu của MeleeRange để lật hướng
var melee_range_initial_x: float = 0.0

# --- BIẾN TUẦN TRA BAY XÉO ---
var start_position: Vector2 = Vector2.ZERO
@export var patrol_distance: float = 120.0 # Bán kính bay ngang
@export var patrol_height: float = 60.0     # Độ chênh lệch chiều cao bay xéo
var direction_x: int = 1
var direction_y: int = 1                    # 1: Bay xéo xuống, -1: Bay xéo lên

var player: Node2D = null
var is_in_melee_range: bool = false
var is_attacking: bool = false
var is_dead: bool = false

var skill_timer: float = 0.0
const SKILL_COOLDOWN: float = 4.0

func _ready() -> void:
	super._ready()
	start_position = global_position
	
	if melee_range:
		melee_range_initial_x = abs(melee_range.position.x)
	
	if area_2d:
		area_2d.body_entered.connect(_on_detect_entered)
		area_2d.body_exited.connect(_on_detect_exited)
	
	if melee_range:
		melee_range.body_entered.connect(_on_melee_entered)
		melee_range.body_exited.connect(_on_melee_exited)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if player:
		skill_timer += delta

	# 1. NẾU ĐANG TẤN CÔNG: Dừng di chuyển
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 2. XỬ LÝ KHI CÓ PLAYER TRONG VÙNG PHÁT HIỆN:
	if player:
		var vector_to_player = player.global_position - global_position
		
		# Lật mặt và cập nhật vị trí HealthBar / MeleeRange theo Player
		if abs(vector_to_player.x) > 2.0:
			update_facing_direction(vector_to_player.x < 0)

		# ĐIỀU KIỆN KÍCH HOẠT ĐÁNH: Player thực sự chạm vào MeleeRange
		if is_in_melee_range:
			velocity = Vector2.ZERO # Dừng lại ngay khi chạm MeleeRange
			
			if skill_timer >= SKILL_COOLDOWN:
				use_skill_attack3()
			else:
				use_combo_attack()
		else:
			# CHƯA VÀO MELEERANGE: Bay truy đuổi
			var target_pos = player.global_position + Vector2(0, target_y_offset)
			var target_dir = (target_pos - global_position).normalized()
			
			velocity = target_dir * SPEED
			_play_anim("Flight")
			
	# 3. KHI KHÔNG CÓ PLAYER: Bay tuần tra xéo Lên / Xuống
	else:
		# Tạo vector hướng bay xéo (kết hợp X và Y)
		var dir_vector = Vector2(direction_x, direction_y * 0.6).normalized()
		velocity = dir_vector * (SPEED * 0.7) # Bay tuần tra chậm hơn tốc độ đuổi
		
		# Lật mặt và cập nhật vị trí HealthBar / MeleeRange theo hướng tuần tra
		update_facing_direction(direction_x < 0)
		_play_anim("Flight")

		# Kiểm tra giới hạn trục X để đảo chiều ngang
		if direction_x > 0 and global_position.x >= start_position.x + patrol_distance:
			direction_x = -1
			direction_y *= -1 # Đổi hướng xéo Y luôn cho đường bay tự nhiên
		elif direction_x < 0 and global_position.x <= start_position.x - patrol_distance:
			direction_x = 1
			direction_y *= -1

		# Kiểm tra giới hạn trục Y để đảo chiều dọc (không cho bay chệch quá xa điểm xuất phát)
		if direction_y > 0 and global_position.y >= start_position.y + patrol_height:
			direction_y = -1
		elif direction_y < 0 and global_position.y <= start_position.y - patrol_height:
			direction_y = 1

	move_and_slide()

# --- HÀM CẬP NHẬT HƯỚNG QUAY MẶT VÀ VỊ TRÍ HEALTHBAR / MELEERANGE ---
func update_facing_direction(is_facing_left: bool) -> void:
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

# --- CHIÊU 3 (CẬN CHIẾN TĂNG SÁT THƯƠNG) ---
func use_skill_attack3() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity = Vector2.ZERO
	skill_timer = 0.0
	
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("cbattack3"):
		anim_sprite.play("cbattack3")
		await anim_sprite.animation_finished
	
	if is_dead: 
		is_attacking = false
		return
		
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("attack3"):
		anim_sprite.play("attack3")
		deal_damage_if_in_range(int(attack_damage * 1.5))
		await anim_sprite.animation_finished
	
	is_attacking = false

# --- COMBO ATTACK 1 VÀ ATTACK 2 ---
var combo_step: int = 0
func use_combo_attack() -> void:
	if is_attacking or is_dead or not anim_sprite: return
	is_attacking = true
	velocity = Vector2.ZERO
	
	combo_step = 1 if combo_step >= 2 else combo_step + 1
	var anim_name = "attack" if combo_step == 1 else "attack2"
	
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
		deal_damage_if_in_range(attack_damage)
		await anim_sprite.animation_finished
		
	is_attacking = false

# --- GÂY SÁT THƯƠNG (Chỉ gây sát thương khi Player ĐANG ở trong MeleeRange) ---
func deal_damage_if_in_range(damage_amount: int) -> void:
	if is_in_melee_range and player and player.has_method("take_damage"):
		player.take_damage(damage_amount)

# --- XỬ LÝ KHI CHẾT ---
func die() -> void:
	if is_dead: return
	is_dead = true
	
	set_physics_process(false)
	velocity = Vector2.ZERO
	
	if has_node("HealthBar"):
		$HealthBar.hide()
	
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
		
	if anim_sprite and anim_sprite.sprite_frames:
		if anim_sprite.sprite_frames.has_animation("cbdie"):
			anim_sprite.play("cbdie")
			await anim_sprite.animation_finished
			
		if anim_sprite.sprite_frames.has_animation("die"):
			anim_sprite.play("die")
			await anim_sprite.animation_finished

	super.die()

# --- HÀM CHẠY ANIMATION CHỐNG RESET FRAME ---
func _play_anim(anim_name: String) -> void:
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(anim_name):
		if anim_sprite.animation != anim_name:
			anim_sprite.play(anim_name)

func _is_player(body: Node) -> bool:
	return body.is_in_group("Player") or body.name in ["ngoaihinh", "player", "Player"]

# --- TÍN HIỆU AREA2D (VÙNG PHÁT HIỆN ĐUỔI) ---
func _on_detect_entered(body: Node) -> void:
	if _is_player(body):
		player = body

func _on_detect_exited(body: Node) -> void:
	if _is_player(body) and body == player:
		player = null
		is_in_melee_range = false

# --- TÍN HIỆU MELEERANGE (VÙNG KÍCH HOẠT TẤN CÔNG) ---
func _on_melee_entered(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = true

func _on_melee_exited(body: Node) -> void:
	if _is_player(body):
		is_in_melee_range = false
