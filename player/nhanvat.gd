extends Entity

# --- THÔNG SỐ CẤU HÌNH ---
@export var SPEED: float = 400.0
@export var FLY_SPEED: float = 400.0
@export var JUMP_VELOCITY: float = -400.0
@export var DECELERATION: float = 3000.0
const DOUBLE_TAP_TIME = 0.3

# --- SÁT THƯƠNG CỦA PLAYER ---
@export var normal_attack_damage: int = 15
@export var skill_damage: int = 35

# --- ONREADY NODES ---
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $hinh
@onready var skill_timer: Timer = get_node_or_null("SkillTimer") if has_node("SkillTimer") else get_node_or_null("../SkillTimer")
@onready var melee_range: Area2D = $MeleeRange

# Quản lý trạng thái
var normal_attack_step: int = 0
var is_attacking: bool = false
var is_flying: bool = false
var last_jump_press_time: float = -1.0

func _ready() -> void:
	super._ready()
	add_to_group("Player")

	# RESET TRẠNG THÁI BAN ĐẦU (Tránh bị kẹt đứng yên khi vừa load scene)
	is_attacking = false
	velocity = Vector2.ZERO

	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

func _physics_process(delta: float) -> void:
	# 1. Bấm chuột phải: Dùng Skill 4
	if Input.is_action_just_pressed("skill") and not is_attacking:
		use_skill()

	# 2. Bấm chuột trái: Đánh thường
	if Input.is_action_just_pressed("attack") and not is_attacking:
		use_normal_attack()

	# 3. Tự động hủy trạng thái bay nếu chạm đất
	if is_on_floor():
		is_flying = false

	# 4. Xử lý logic Nhấn Space (Nhảy / Bay)
	if Input.is_action_just_pressed("ui_accept") and not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_jump_press_time <= DOUBLE_TAP_TIME:
			is_flying = !is_flying
			if is_flying:
				velocity.y = 0
		else:
			if is_on_floor() and not is_flying:
				velocity.y = JUMP_VELOCITY
		last_jump_press_time = current_time

	# 5. Xử lý di chuyển (Tương tự logic DarkHero - không cho phép bị hãm dừng khi đang nhấn phím)
	if not is_attacking:
		if is_flying:
			var direction_x := Input.get_axis("ui_left", "ui_right")
			var direction_y := Input.get_axis("ui_up", "ui_down")
			velocity.x = direction_x * FLY_SPEED
			velocity.y = direction_y * FLY_SPEED
		else:
			if not is_on_floor():
				velocity.y += get_gravity().y * delta

			var direction := Input.get_axis("ui_left", "ui_right")
			if direction != 0:
				velocity.x = direction * SPEED
			else:
				# Giảm tốc từ từ thay vì ngắt đột ngột
				velocity.x = move_toward(velocity.x, 0, DECELERATION * delta)
	else:
		# Khi đang đánh chỉ dừng di chuyển ngang, vẫn giữ trọng lực rơi nếu đang ở trên không
		velocity.x = 0
		if not is_on_floor() and not is_flying:
			velocity.y += get_gravity().y * delta

	move_and_slide()
	
	var dir_x := Input.get_axis("ui_left", "ui_right")
	update_animation(dir_x)

# --- QUẢN LÝ GÂY SÁT THƯƠNG ---
func deal_damage_to_enemies(amount: int) -> void:
	if not melee_range: return
	var bodies = melee_range.get_overlapping_bodies()
	for body in bodies:
		if body == self or body.is_in_group("Player"): 
			continue # Bỏ qua chính mình và đồng minh
		if body.has_method("take_damage"):
			body.take_damage(amount)

# --- QUẢN LÝ TẤN CÔNG ---
func use_normal_attack() -> void:
	is_attacking = true
	
	normal_attack_step += 1
	if normal_attack_step > 3:
		normal_attack_step = 1
		
	if anim_player and anim_player.has_animation("attack" + str(normal_attack_step)):
		anim_player.play("attack" + str(normal_attack_step))
	else:
		# Lớp bảo vệ: Nếu không có animation thì tự mở khóa trạng thái sau 0.2s
		get_tree().create_timer(0.2).timeout.connect(func(): is_attacking = false)
	
	await get_tree().create_timer(0.05).timeout
	if is_attacking:
		deal_damage_to_enemies(normal_attack_damage)

func use_skill() -> void:
	if skill_timer and skill_timer.time_left > 0:
		print("Chiêu đang hồi: ", str(snapped(skill_timer.time_left, 0.1)), "s")
		return

	is_attacking = true
	
	if anim_player and anim_player.has_animation("attack4"):
		anim_player.play("attack4")
	else:
		get_tree().create_timer(0.3).timeout.connect(func(): is_attacking = false)
	
	await get_tree().create_timer(0.1).timeout
	if is_attacking:
		deal_damage_to_enemies(skill_damage)
	
	if skill_timer:
		skill_timer.start()

func _on_animation_finished(anim_name: String) -> void:
	# Giải phóng trạng thái đánh ngay khi animation chạy xong
	if anim_name.begins_with("attack"):
		is_attacking = false

func update_animation(direction: float) -> void:
	if not anim_player or not sprite: return

	# Lật hình bằng scale/flip để không làm lệch tâm va chạm MeleeRange
	if direction > 0:
		sprite.flip_h = false
		if melee_range:
			melee_range.scale.x = 1
	elif direction < 0:
		sprite.flip_h = true
		if melee_range:
			melee_range.scale.x = -1

	if is_attacking:
		return

	if is_flying:
		anim_player.stop()
		return

	if not is_on_floor():
		if velocity.y < 0:
			if anim_player.has_animation("jump"): anim_player.play("jump")
		else:
			if anim_player.has_animation("fall"): anim_player.play("fall")
	else:
		if direction != 0:
			if anim_player.has_animation("walk"): anim_player.play("walk")
		else:
			if anim_player.has_animation("idle"): anim_player.play("idle")

# --- XỬ LÝ KHI PLAYER CHẾT ---
func die() -> void:
	died.emit()
	set_physics_process(false)
	is_attacking = true
	velocity = Vector2.ZERO
	
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if health_bar:
		health_bar.hide()

	if has_node("Camera2D"):
		var cam: Camera2D = $Camera2D
		var global_cam_pos = cam.global_position
		cam.reparent(get_parent())
		cam.global_position = global_cam_pos

	if anim_player and anim_player.has_animation("die"):
		anim_player.play("die")
		await anim_player.animation_finished

	queue_free()
