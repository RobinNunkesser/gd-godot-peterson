extends Node3D

# ==============================================================================
# PETERSON 3D CRASH SIMULATOR (Godot 4)
# Didactic showcase for Operating Systems (Betriebssysteme)
# Visualizing Mutual Exclusion, Race Conditions, and Peterson's Algorithm
# ==============================================================================

enum ScenarioMode {
	PETERSON_SAFE,
	UNSYNCHRONIZED_CRASH,
	DEADLOCK_NO_TURN,
	STEP_BY_STEP
}

enum ThreadState {
	IDLE,
	APPROACHING,
	DECLARED_INTEREST,
	YIELDED_TURN,
	BUSY_WAITING,
	IN_CRITICAL_SECTION,
	EXITED
}

# --- Tuning & Geometry ---
const TRACK_START_Z: float = -32.0
const SENSOR_Z: float = -22.0
const BARRIER_Z: float = -12.5
const BRIDGE_ENTRY_Z: float = -11.0
const BRIDGE_EXIT_Z: float = 11.0
const TRACK_END_Z: float = 32.0
const LATERAL_OFFSET: float = 6.5
const TRAIN_SPEED: float = 12.0

# --- State Variables ---
var current_mode: ScenarioMode = ScenarioMode.PETERSON_SAFE
var is_running: bool = false
var is_paused: bool = false
var sim_speed: float = 1.0

# Peterson Shared Variables
var interested: Array[bool] = [false, false]
var turn: int = -1 # -1: None, 0: T0, 1: T1

# Thread Execution States
var thread_states: Array[ThreadState] = [ThreadState.IDLE, ThreadState.IDLE]
var train_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var train_active: Array[bool] = [false, false]
var train_crashed: Array[bool] = [false, false]

# Simulation Metrics & Tracking
var in_cs_count: int = 0
var collision_detected: bool = false
var deadlock_detected: bool = false
var deadlock_timer: float = 0.0
var step_index: int = 0
var screen_shake_amount: float = 0.0

# --- Node References ---
var camera: Camera3D
var world_env: WorldEnvironment
var sun: DirectionalLight3D

# 3D Visual Elements
var bridge_mesh: MeshInstance3D
var sensor_0_mesh: MeshInstance3D
var sensor_1_mesh: MeshInstance3D
var turn_turntable: Node3D
var turn_arrow: MeshInstance3D
var barrier_0: Node3D
var barrier_1: Node3D
var train_0: CharacterBody3D
var train_1: CharacterBody3D
var train_0_mesh: MeshInstance3D
var train_1_mesh: MeshInstance3D
var debris_container: Node3D
var status_billboard_label: Label3D

# Materials
var mat_sensor_0_on: StandardMaterial3D
var mat_sensor_0_off: StandardMaterial3D
var mat_sensor_1_on: StandardMaterial3D
var mat_sensor_1_off: StandardMaterial3D
var mat_barrier_open: StandardMaterial3D
var mat_barrier_closed: StandardMaterial3D

# UI Nodes
var ui_layer: CanvasLayer
var status_banner: PanelContainer
var status_label: Label
var narration_label: Label
var code_t0_labels: Array[Label] = []
var code_t1_labels: Array[Label] = []
var state_label_t0: Label
var state_label_t1: Label
var state_label_turn: Label
var state_label_cs: Label

func _ready() -> void:
	setup_materials()
	setup_environment()
	setup_track_and_bridge()
	setup_signals_and_barriers()
	setup_trains()
	setup_ui()
	reset_simulation(ScenarioMode.PETERSON_SAFE)

# ==============================================================================
# 3D WORLD & ENVIRONMENT SETUP
# ==============================================================================

func setup_materials() -> void:
	mat_sensor_0_off = StandardMaterial3D.new()
	mat_sensor_0_off.albedo_color = Color(0.1, 0.2, 0.3)
	
	mat_sensor_0_on = StandardMaterial3D.new()
	mat_sensor_0_on.albedo_color = Color(0.0, 0.8, 1.0)
	mat_sensor_0_on.emission_enabled = true
	mat_sensor_0_on.emission = Color(0.0, 0.85, 1.0)
	mat_sensor_0_on.emission_energy_multiplier = 3.0

	mat_sensor_1_off = StandardMaterial3D.new()
	mat_sensor_1_off.albedo_color = Color(0.3, 0.2, 0.1)

	mat_sensor_1_on = StandardMaterial3D.new()
	mat_sensor_1_on.albedo_color = Color(1.0, 0.5, 0.0)
	mat_sensor_1_on.emission_enabled = true
	mat_sensor_1_on.emission = Color(1.0, 0.55, 0.0)
	mat_sensor_1_on.emission_energy_multiplier = 3.0

	mat_barrier_closed = StandardMaterial3D.new()
	mat_barrier_closed.albedo_color = Color(0.9, 0.1, 0.1)
	mat_barrier_closed.emission_enabled = true
	mat_barrier_closed.emission = Color(1.0, 0.1, 0.1)
	mat_barrier_closed.emission_energy_multiplier = 2.0

	mat_barrier_open = StandardMaterial3D.new()
	mat_barrier_open.albedo_color = Color(0.1, 0.9, 0.2)
	mat_barrier_open.emission_enabled = true
	mat_barrier_open.emission = Color(0.1, 1.0, 0.2)
	mat_barrier_open.emission_energy_multiplier = 2.0

func setup_environment() -> void:
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.position = Vector3(0.0, 18.0, 26.0)
	camera.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_color = Color(0.95, 0.98, 1.0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.08)
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.ambient_light_color = Color(0.15, 0.18, 0.25)

	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	debris_container = Node3D.new()
	debris_container.name = "DebrisContainer"
	add_child(debris_container)

func setup_track_and_bridge() -> void:
	# Ground / Canyon Abyss
	var ground = MeshInstance3D.new()
	var ground_plane = PlaneMesh.new()
	ground_plane.size = Vector2(80.0, 90.0)
	ground.mesh = ground_plane
	ground.position = Vector3(0.0, -8.0, 0.0)
	var ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.015, 0.02, 0.04)
	ground.material_override = ground_mat
	add_child(ground)

	# Central Bridge (The Critical Section)
	bridge_mesh = MeshInstance3D.new()
	var bridge_box = BoxMesh.new()
	bridge_box.size = Vector3(3.2, 0.5, 23.0)
	bridge_mesh.mesh = bridge_box
	bridge_mesh.position = Vector3(0.0, 0.0, 0.0)
	var bridge_mat = StandardMaterial3D.new()
	bridge_mat.albedo_color = Color(0.12, 0.15, 0.22)
	bridge_mat.roughness = 0.4
	bridge_mesh.material_override = bridge_mat
	add_child(bridge_mesh)

	# Bridge Glowing Laser Rails
	for x_side in [-1.55, 1.55]:
		var rail = MeshInstance3D.new()
		var r_box = BoxMesh.new()
		r_box.size = Vector3(0.12, 0.4, 23.0)
		rail.mesh = r_box
		rail.position = Vector3(x_side, 0.35, 0.0)
		var r_mat = StandardMaterial3D.new()
		r_mat.albedo_color = Color(0.2, 0.8, 0.9)
		r_mat.emission_enabled = true
		r_mat.emission = Color(0.2, 0.8, 0.9)
		r_mat.emission_energy_multiplier = 1.5
		rail.material_override = r_mat
		add_child(rail)

	# Approach Approach Platforms (Z < -11 and Z > +11)
	create_track_platform(-LATERAL_OFFSET, TRACK_START_Z, -LATERAL_OFFSET, BARRIER_Z - 1.0, Color(0.08, 0.12, 0.18))
	create_track_platform(LATERAL_OFFSET, TRACK_START_Z, LATERAL_OFFSET, BARRIER_Z - 1.0, Color(0.08, 0.12, 0.18))
	create_track_platform(-LATERAL_OFFSET, BRIDGE_EXIT_Z + 1.0, -LATERAL_OFFSET, TRACK_END_Z, Color(0.08, 0.12, 0.18))
	create_track_platform(LATERAL_OFFSET, BRIDGE_EXIT_Z + 1.0, LATERAL_OFFSET, TRACK_END_Z, Color(0.08, 0.12, 0.18))

	# Floating 3D Billboard above the Critical Section
	status_billboard_label = Label3D.new()
	status_billboard_label.position = Vector3(0.0, 4.2, 0.0)
	status_billboard_label.text = "[ KRITISCHER ABSCHNITT: FREI ]"
	status_billboard_label.font_size = 40
	status_billboard_label.modulate = Color(0.2, 1.0, 0.4)
	status_billboard_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(status_billboard_label)

func create_track_platform(x1: float, z1: float, x2: float, z2: float, color: Color) -> void:
	var length = abs(z2 - z1)
	var mid_z = (z1 + z2) * 0.5
	var platform = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3.0, 0.4, length)
	platform.mesh = box
	platform.position = Vector3(x1, 0.0, mid_z)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	platform.material_override = mat
	add_child(platform)

func setup_signals_and_barriers() -> void:
	# Sensor 0 (Interested[0])
	sensor_0_mesh = MeshInstance3D.new()
	var s_box = BoxMesh.new()
	s_box.size = Vector3(3.4, 0.08, 2.2)
	sensor_0_mesh.mesh = s_box
	sensor_0_mesh.position = Vector3(-LATERAL_OFFSET, 0.22, SENSOR_Z)
	sensor_0_mesh.material_override = mat_sensor_0_off
	add_child(sensor_0_mesh)

	var label_s0 = Label3D.new()
	label_s0.position = Vector3(-LATERAL_OFFSET, 1.2, SENSOR_Z)
	label_s0.text = "Sensor: Interested[0]"
	label_s0.font_size = 28
	label_s0.modulate = Color(0.0, 0.85, 1.0)
	label_s0.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label_s0)

	# Sensor 1 (Interested[1])
	sensor_1_mesh = MeshInstance3D.new()
	sensor_1_mesh.mesh = s_box
	sensor_1_mesh.position = Vector3(LATERAL_OFFSET, 0.22, SENSOR_Z)
	sensor_1_mesh.material_override = mat_sensor_1_off
	add_child(sensor_1_mesh)

	var label_s1 = Label3D.new()
	label_s1.position = Vector3(LATERAL_OFFSET, 1.2, SENSOR_Z)
	label_s1.text = "Sensor: Interested[1]"
	label_s1.font_size = 28
	label_s1.modulate = Color(1.0, 0.6, 0.1)
	label_s1.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label_s1)

	# The Courtesy Turntable / Indicator (_turn)
	turn_turntable = Node3D.new()
	turn_turntable.position = Vector3(0.0, 0.3, SENSOR_Z + 4.0)
	add_child(turn_turntable)

	var base_cyl = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = 1.4
	cyl_mesh.bottom_radius = 1.5
	cyl_mesh.height = 0.3
	base_cyl.mesh = cyl_mesh
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.18, 0.22, 0.3)
	base_cyl.material_override = base_mat
	turn_turntable.add_child(base_cyl)

	turn_arrow = MeshInstance3D.new()
	var arr_mesh = PrismMesh.new()
	arr_mesh.size = Vector3(1.2, 1.8, 0.3)
	turn_arrow.mesh = arr_mesh
	turn_arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	turn_arrow.position = Vector3(0.0, 0.3, 0.0)
	var arr_mat = StandardMaterial3D.new()
	arr_mat.albedo_color = Color(1.0, 0.85, 0.1)
	arr_mat.emission_enabled = true
	arr_mat.emission = Color(1.0, 0.85, 0.1)
	arr_mat.emission_energy_multiplier = 2.0
	turn_arrow.material_override = arr_mat
	turn_turntable.add_child(turn_arrow)

	var label_turn_3d = Label3D.new()
	label_turn_3d.position = Vector3(0.0, 1.8, 0.0)
	label_turn_3d.text = "Höflichkeits-Weiche (_turn)"
	label_turn_3d.font_size = 26
	label_turn_3d.modulate = Color(1.0, 0.9, 0.2)
	label_turn_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	turn_turntable.add_child(label_turn_3d)

	# Barriers
	barrier_0 = create_barrier(Vector3(-LATERAL_OFFSET + 1.2, 0.0, BARRIER_Z))
	barrier_1 = create_barrier(Vector3(LATERAL_OFFSET - 1.2, 0.0, BARRIER_Z))

func create_barrier(pos: Vector3) -> Node3D:
	var root = Node3D.new()
	root.position = pos

	var post = MeshInstance3D.new()
	var post_mesh = BoxMesh.new()
	post_mesh.size = Vector3(0.3, 1.6, 0.3)
	post.mesh = post_mesh
	post.position = Vector3(0.0, 0.8, 0.0)
	root.add_child(post)

	var arm = MeshInstance3D.new()
	var arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(2.5, 0.2, 0.15)
	arm.mesh = arm_mesh
	arm.name = "Arm"
	arm.position = Vector3(-1.1, 1.3, 0.0)
	arm.material_override = mat_barrier_closed
	root.add_child(arm)

	add_child(root)
	return root

func setup_trains() -> void:
	# Train 0 (Blue / Thread 0)
	train_0 = CharacterBody3D.new()
	train_0.name = "Train0"
	var col_0 = CollisionShape3D.new()
	var box_0 = BoxShape3D.new()
	box_0.size = Vector3(1.6, 1.0, 3.2)
	col_0.shape = box_0
	train_0.add_child(col_0)

	train_0_mesh = MeshInstance3D.new()
	var mesh_0 = BoxMesh.new()
	mesh_0.size = Vector3(1.6, 1.0, 3.2)
	train_0_mesh.mesh = mesh_0
	var mat_t0 = StandardMaterial3D.new()
	mat_t0.albedo_color = Color(0.05, 0.6, 1.0)
	mat_t0.emission_enabled = true
	mat_t0.emission = Color(0.05, 0.6, 1.0)
	mat_t0.emission_energy_multiplier = 1.2
	train_0_mesh.material_override = mat_t0
	train_0.add_child(train_0_mesh)

	var badge_0 = Label3D.new()
	badge_0.position = Vector3(0.0, 1.2, 0.0)
	badge_0.text = "Thread 0 (T0)"
	badge_0.font_size = 28
	badge_0.modulate = Color(0.2, 0.8, 1.0)
	badge_0.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	train_0.add_child(badge_0)

	add_child(train_0)

	# Train 1 (Orange / Thread 1)
	train_1 = CharacterBody3D.new()
	train_1.name = "Train1"
	var col_1 = CollisionShape3D.new()
	var box_1 = BoxShape3D.new()
	box_1.size = Vector3(1.6, 1.0, 3.2)
	col_1.shape = box_1
	train_1.add_child(col_1)

	train_1_mesh = MeshInstance3D.new()
	var mesh_1 = BoxMesh.new()
	mesh_1.size = Vector3(1.6, 1.0, 3.2)
	train_1_mesh.mesh = mesh_1
	var mat_t1 = StandardMaterial3D.new()
	mat_t1.albedo_color = Color(1.0, 0.45, 0.05)
	mat_t1.emission_enabled = true
	mat_t1.emission = Color(1.0, 0.45, 0.05)
	mat_t1.emission_energy_multiplier = 1.2
	train_1_mesh.material_override = mat_t1
	train_1.add_child(train_1_mesh)

	var badge_1 = Label3D.new()
	badge_1.position = Vector3(0.0, 1.2, 0.0)
	badge_1.text = "Thread 1 (T1)"
	badge_1.font_size = 28
	badge_1.modulate = Color(1.0, 0.6, 0.1)
	badge_1.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	train_1.add_child(badge_1)

	add_child(train_1)

# ==============================================================================
# UI CREATION & LAYOUT
# ==============================================================================

func setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 16.0
	main_vbox.offset_top = 12.0
	main_vbox.offset_right = -16.0
	main_vbox.offset_bottom = -12.0
	ui_layer.add_child(main_vbox)

	# --- Header Bar ---
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title_lbl = Label.new()
	title_lbl.text = "🚦 Peterson 3D Crash Simulator"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header_hbox.add_child(title_lbl)

	header_hbox.add_spacer(false)

	# Scenario Preset Buttons
	var btn_p1 = create_button("🛡️ 1. Peterson (Sicher)", Callable(self, "_on_select_peterson"))
	var btn_p2 = create_button("💥 2. Unsynchronisiert (Crash)", Callable(self, "_on_select_unsynchronized"))
	var btn_p3 = create_button("⚠️ 3. Ohne Turn (Deadlock)", Callable(self, "_on_select_deadlock"))
	var btn_p4 = create_button("⏯️ 4. Einzelschritt", Callable(self, "_on_select_step_by_step"))
	header_hbox.add_child(btn_p1)
	header_hbox.add_child(btn_p2)
	header_hbox.add_child(btn_p3)
	header_hbox.add_child(btn_p4)

	# --- Status Banner ---
	status_banner = PanelContainer.new()
	status_banner.custom_minimum_size = Vector2(0.0, 42.0)
	main_vbox.add_child(status_banner)

	status_label = Label.new()
	status_label.text = "BEREIT ZUR SIMULATION"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_banner.add_child(status_label)

	# --- Middle Row: Swimlanes (T0 | Central State | T1) ---
	var mid_hbox = HBoxContainer.new()
	mid_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(mid_hbox)

	# Left: Thread 0 Card
	var t0_card = create_swimlane_card("🧵 Thread 0 (T0 - Blau)", Color(0.0, 0.7, 1.0), [
		"1: interested[0] = true;",
		"2: _turn = 1;",
		"3: while (interested[1] && _turn == 1) { wait; }",
		"4: // --- KRITISCHER ABSCHNITT ---",
		"5: interested[0] = false;"
	], code_t0_labels)
	t0_card.custom_minimum_size = Vector2(280.0, 0.0)
	mid_hbox.add_child(t0_card)

	mid_hbox.add_spacer(false)

	# Center: Shared State HUD
	var center_panel = PanelContainer.new()
	center_panel.custom_minimum_size = Vector2(360.0, 0.0)
	var c_vbox = VBoxContainer.new()
	c_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_panel.add_child(c_vbox)

	var sh_title = Label.new()
	sh_title.text = "💾 Geteilter Zustand (Shared State)"
	sh_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sh_title.add_theme_font_size_override("font_size", 15)
	c_vbox.add_child(sh_title)

	state_label_t0 = Label.new()
	state_label_t0.text = "Interested[0]: FALSE"
	state_label_t0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_vbox.add_child(state_label_t0)

	state_label_t1 = Label.new()
	state_label_t1.text = "Interested[1]: FALSE"
	state_label_t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_vbox.add_child(state_label_t1)

	state_label_turn = Label.new()
	state_label_turn.text = "Variable _turn: None (-1)"
	state_label_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label_turn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	c_vbox.add_child(state_label_turn)

	state_label_cs = Label.new()
	state_label_cs.text = "Brücke: 🔓 FREI"
	state_label_cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label_cs.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	c_vbox.add_child(state_label_cs)

	mid_hbox.add_child(center_panel)

	mid_hbox.add_spacer(false)

	# Right: Thread 1 Card
	var t1_card = create_swimlane_card("🧵 Thread 1 (T1 - Orange)", Color(1.0, 0.5, 0.0), [
		"1: interested[1] = true;",
		"2: _turn = 0;",
		"3: while (interested[0] && _turn == 0) { wait; }",
		"4: // --- KRITISCHER ABSCHNITT ---",
		"5: interested[1] = false;"
	], code_t1_labels)
	t1_card.custom_minimum_size = Vector2(280.0, 0.0)
	mid_hbox.add_child(t1_card)

	# --- Bottom Row: Narration & Controls ---
	var bot_vbox = VBoxContainer.new()
	main_vbox.add_child(bot_vbox)

	var narr_panel = PanelContainer.new()
	narration_label = Label.new()
	narration_label.text = "Klicken Sie auf '▶ Start' oder wählen Sie ein Szenario."
	narration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narr_panel.add_child(narration_label)
	bot_vbox.add_child(narr_panel)

	var ctrl_hbox = HBoxContainer.new()
	bot_vbox.add_child(ctrl_hbox)

	var btn_start = create_button("▶ Start", Callable(self, "_on_click_start"))
	var btn_step = create_button("⏭ Einzelschritt", Callable(self, "_on_click_step"))
	var btn_reset = create_button("↺ Zurücksetzen", Callable(self, "_on_click_reset"))
	ctrl_hbox.add_child(btn_start)
	ctrl_hbox.add_child(btn_step)
	ctrl_hbox.add_child(btn_reset)

	ctrl_hbox.add_spacer(false)

	var speed_label = Label.new()
	speed_label.text = "Tempo:"
	ctrl_hbox.add_child(speed_label)

	var btn_s1 = create_button("1.0x", func(): sim_speed = 1.0)
	var btn_s2 = create_button("2.0x", func(): sim_speed = 2.0)
	ctrl_hbox.add_child(btn_s1)
	ctrl_hbox.add_child(btn_s2)

func create_button(text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	return btn

func create_swimlane_card(title: String, title_col: Color, lines: Array, out_labels: Array[Label]) -> PanelContainer:
	var card = PanelContainer.new()
	var vbox = VBoxContainer.new()
	card.add_child(vbox)

	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", title_col)
	lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl)

	for line in lines:
		var code_lbl = Label.new()
		code_lbl.text = line
		code_lbl.add_theme_font_size_override("font_size", 12)
		code_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		vbox.add_child(code_lbl)
		out_labels.append(code_lbl)

	return card

# ==============================================================================
# SIMULATION LOGIC & STATE MACHINE
# ==============================================================================

func reset_simulation(mode: ScenarioMode) -> void:
	current_mode = mode
	is_running = false
	is_paused = false
	in_cs_count = 0
	collision_detected = false
	deadlock_detected = false
	deadlock_timer = 0.0
	step_index = 0
	screen_shake_amount = 0.0

	interested = [false, false]
	turn = -1
	thread_states = [ThreadState.IDLE, ThreadState.IDLE]
	train_active = [false, false]
	train_crashed = [false, false]

	train_positions[0] = Vector3(-LATERAL_OFFSET, 0.5, TRACK_START_Z)
	train_positions[1] = Vector3(LATERAL_OFFSET, 0.5, TRACK_START_Z)

	train_0.position = train_positions[0]
	train_1.position = train_positions[1]
	train_0.visible = true
	train_1.visible = true

	# Clear debris
	for child in debris_container.get_children():
		child.queue_free()

	update_visuals()
	update_hud()

	match current_mode:
		ScenarioMode.PETERSON_SAFE:
			narration_label.text = "Modus: Peterson Algorithmus. Beide Threads setzen interested und turn. Die Höflichkeits-Variable verhindert Deadlocks und gewährleistet Mutual Exclusion."
			status_label.text = "MODUS 1: PETERSON (SICHERER WECHSELSEITIGER AUSSCHLUSS)"
		ScenarioMode.UNSYNCHRONIZED_CRASH:
			narration_label.text = "Modus: Unsynchronisiert (Race Condition). Keine Sperren vorhanden – beide Züge rasen ungebremst auf die Brücke zu!"
			status_label.text = "MODUS 2: UNSYNCHRONISIERT (KOLLISIONS-GEFAHR)"
		ScenarioMode.DEADLOCK_NO_TURN:
			narration_label.text = "Modus: Ohne Turn. Beide Threads bekunden Interesse, aber keiner weicht aus. Zyklisches Warten führt zum Stillstand."
			status_label.text = "MODUS 3: OHNE TURN (VERKLEMMUNG / DEADLOCK)"
		ScenarioMode.STEP_BY_STEP:
			narration_label.text = "Modus: Einzelschritt. Klicken Sie auf '⏭ Einzelschritt', um jede Codezeile sequentiell auszuführen."
			status_label.text = "MODUS 4: EINZELSCHRITT-ANALYSE"

func _physics_process(delta: float) -> void:
	if screen_shake_amount > 0.0:
		screen_shake_amount = max(0.0, screen_shake_amount - delta * 3.0)
		camera.position = Vector3(
			randf_range(-screen_shake_amount, screen_shake_amount),
			18.0 + randf_range(-screen_shake_amount, screen_shake_amount),
			26.0
		)

	if not is_running or is_paused:
		return

	var dt = delta * sim_speed

	# Update trains
	if current_mode == ScenarioMode.UNSYNCHRONIZED_CRASH:
		process_unsynchronized(dt)
	elif current_mode == ScenarioMode.PETERSON_SAFE:
		process_peterson(dt)
	elif current_mode == ScenarioMode.DEADLOCK_NO_TURN:
		process_deadlock(dt)

	update_visuals()
	update_hud()

# --- Unsynchronized Execution ---
func process_unsynchronized(dt: float) -> void:
	for id in [0, 1]:
		if train_crashed[id]:
			continue

		train_positions[id].z += TRAIN_SPEED * dt

		# Curve towards center bridge
		if train_positions[id].z > BARRIER_Z and train_positions[id].z < BRIDGE_EXIT_Z:
			var lateral_factor = clamp((train_positions[id].z - BARRIER_Z) / 2.0, 0.0, 1.0)
			train_positions[id].x = lerp(train_positions[id].x, 0.0, lateral_factor * 0.25)
		elif train_positions[id].z >= BRIDGE_EXIT_Z:
			var target_x = -LATERAL_OFFSET if id == 0 else LATERAL_OFFSET
			train_positions[id].x = lerp(train_positions[id].x, target_x, 0.1)

		if id == 0:
			train_0.position = train_positions[0]
		else:
			train_1.position = train_positions[1]

	# Check Critical Section occupancy & collision
	check_critical_section()

	if train_0.position.distance_to(train_1.position) < 2.2 and not collision_detected:
		trigger_crash()

	if train_positions[0].z > TRACK_END_Z and train_positions[1].z > TRACK_END_Z:
		is_running = false

# --- Peterson Execution ---
func process_peterson(dt: float) -> void:
	for id in [0, 1]:
		var other = 1 - id
		var pos = train_positions[id]

		match thread_states[id]:
			ThreadState.IDLE:
				pass

			ThreadState.APPROACHING:
				pos.z += TRAIN_SPEED * dt
				if pos.z >= SENSOR_Z:
					# Step 1: interested[id] = true
					interested[id] = true
					thread_states[id] = ThreadState.DECLARED_INTEREST
					narration_label.text = "Thread %d setzt interested[%d] = true (Sensor aktiviert)." % [id, id]

			ThreadState.DECLARED_INTEREST:
				pos.z += TRAIN_SPEED * dt
				if pos.z >= SENSOR_Z + 3.0:
					# Step 2: turn = other (yield priority)
					turn = other
					thread_states[id] = ThreadState.YIELDED_TURN
					narration_label.text = "Thread %d überlässt den Vortritt: turn = %d." % [id, other]

			ThreadState.YIELDED_TURN:
				pos.z += TRAIN_SPEED * dt
				if pos.z >= BARRIER_Z:
					pos.z = BARRIER_Z
					# Step 3: while (interested[other] && turn == other)
					if interested[other] and turn == other:
						thread_states[id] = ThreadState.BUSY_WAITING
						narration_label.text = "Thread %d muss warten: Bedingung (interested[%d] && turn == %d) ist WAHR!" % [id, other, other]
					else:
						thread_states[id] = ThreadState.IN_CRITICAL_SECTION
						narration_label.text = "Thread %d erhält Vorrang und betritt die Brücke!" % id

			ThreadState.BUSY_WAITING:
				# Re-evaluate while-condition
				if not (interested[other] and turn == other):
					thread_states[id] = ThreadState.IN_CRITICAL_SECTION
					narration_label.text = "Thread %d: Bedingung falsch ➔ Schranke öffnet sich!" % id

			ThreadState.IN_CRITICAL_SECTION:
				pos.z += TRAIN_SPEED * dt
				# Curve to center
				if pos.z < BRIDGE_EXIT_Z:
					pos.x = lerp(pos.x, 0.0, 0.15)
				else:
					# Step 5: interested[id] = false
					var target_x = -LATERAL_OFFSET if id == 0 else LATERAL_OFFSET
					pos.x = lerp(pos.x, target_x, 0.15)
					interested[id] = false
					thread_states[id] = ThreadState.EXITED
					narration_label.text = "Thread %d verlässt den kritischen Bereich: interested[%d] = false." % [id, id]

			ThreadState.EXITED:
				pos.z += TRAIN_SPEED * dt

		train_positions[id] = pos
		if id == 0:
			train_0.position = pos
		else:
			train_1.position = pos

	check_critical_section()

	if thread_states[0] == ThreadState.EXITED and thread_states[1] == ThreadState.EXITED and train_positions[0].z > TRACK_END_Z and train_positions[1].z > TRACK_END_Z:
		is_running = false
		status_label.text = "✅ ERFOLGREICH: MUTUAL EXCLUSION ERFÜLLT (0 KOLLISIONEN)"

# --- Deadlock Execution (No Turn) ---
func process_deadlock(dt: float) -> void:
	for id in [0, 1]:
		var other = 1 - id
		var pos = train_positions[id]

		match thread_states[id]:
			ThreadState.IDLE:
				pass
			ThreadState.APPROACHING:
				pos.z += TRAIN_SPEED * dt
				if pos.z >= SENSOR_Z:
					interested[id] = true
					thread_states[id] = ThreadState.DECLARED_INTEREST
			ThreadState.DECLARED_INTEREST:
				pos.z += TRAIN_SPEED * dt
				if pos.z >= BARRIER_Z:
					pos.z = BARRIER_Z
					if interested[other]:
						thread_states[id] = ThreadState.BUSY_WAITING

			ThreadState.BUSY_WAITING:
				pass

		train_positions[id] = pos
		if id == 0:
			train_0.position = pos
		else:
			train_1.position = pos

	if thread_states[0] == ThreadState.BUSY_WAITING and thread_states[1] == ThreadState.BUSY_WAITING:
		deadlock_timer += dt
		if deadlock_timer > 1.2 and not deadlock_detected:
			deadlock_detected = true
			status_label.text = "⚠️ DEADLOCK DETEKTIERT: Beide Threads warten endlos aufeinander!"
			narration_label.text = "Verklemmung: Ohne die Höflichkeitsvariable _turn verharren beide Threads in der Warteschleife!"

# ==============================================================================
# MONITORING & CRASH PHYSICS
# ==============================================================================

func check_critical_section() -> void:
	var count = 0
	for id in [0, 1]:
		var z = train_positions[id].z
		if z >= BRIDGE_ENTRY_Z and z <= BRIDGE_EXIT_Z:
			count += 1
	in_cs_count = count

	if in_cs_count > 1 and not collision_detected:
		trigger_crash()

func trigger_crash() -> void:
	collision_detected = true
	is_running = false
	screen_shake_amount = 0.8
	status_label.text = "💥 MUTUAL EXCLUSION VERLETZT! KOLLISION IM KRITISCHEN ABSCHNITT!"
	narration_label.text = "RACE CONDITION: Zwei Threads haben gleichzeitig den kritischen Abschnitt betreten!"

	train_0.visible = false
	train_1.visible = false
	train_crashed[0] = true
	train_crashed[1] = true

	# Spawn explosion debris
	for i in range(16):
		var debris = RigidBody3D.new()
		var mesh_inst = MeshInstance3D.new()
		var b = BoxMesh.new()
		b.size = Vector3(randf_range(0.4, 0.8), randf_range(0.3, 0.6), randf_range(0.4, 0.9))
		mesh_inst.mesh = b
		var d_mat = StandardMaterial3D.new()
		d_mat.albedo_color = Color(randf_range(0.8, 1.0), randf_range(0.2, 0.5), 0.0)
		d_mat.emission_enabled = true
		d_mat.emission = d_mat.albedo_color
		d_mat.emission_energy_multiplier = 2.0
		mesh_inst.material_override = d_mat
		debris.add_child(mesh_inst)

		var col = CollisionShape3D.new()
		var bs = BoxShape3D.new()
		bs.size = b.size
		col.shape = bs
		debris.add_child(col)

		debris.position = (train_0.position + train_1.position) * 0.5 + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1))
		debris.linear_velocity = Vector3(randf_range(-6, 6), randf_range(4, 10), randf_range(-6, 6))
		debris.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		debris_container.add_child(debris)

func update_visuals() -> void:
	# Sensor materials
	sensor_0_mesh.material_override = mat_sensor_0_on if interested[0] else mat_sensor_0_off
	sensor_1_mesh.material_override = mat_sensor_1_on if interested[1] else mat_sensor_1_off

	# Turn Arrow Rotation
	if turn == 0:
		turn_turntable.rotation_degrees.y = lerp(turn_turntable.rotation_degrees.y, -90.0, 0.15)
	elif turn == 1:
		turn_turntable.rotation_degrees.y = lerp(turn_turntable.rotation_degrees.y, 90.0, 0.15)
	else:
		turn_turntable.rotation_degrees.y = lerp(turn_turntable.rotation_degrees.y, 0.0, 0.15)

	# Barriers
	var arm_0 = barrier_0.get_node_or_null("Arm") as MeshInstance3D
	var arm_1 = barrier_1.get_node_or_null("Arm") as MeshInstance3D

	var b0_open = (thread_states[0] == ThreadState.IN_CRITICAL_SECTION or thread_states[0] == ThreadState.EXITED)
	var b1_open = (thread_states[1] == ThreadState.IN_CRITICAL_SECTION or thread_states[1] == ThreadState.EXITED)

	if arm_0:
		arm_0.rotation_degrees.z = lerp(arm_0.rotation_degrees.z, 70.0 if b0_open else 0.0, 0.2)
		arm_0.material_override = mat_barrier_open if b0_open else mat_barrier_closed
	if arm_1:
		arm_1.rotation_degrees.z = lerp(arm_1.rotation_degrees.z, -70.0 if b1_open else 0.0, 0.2)
		arm_1.material_override = mat_barrier_open if b1_open else mat_barrier_closed

	# Billboard Text
	if collision_detected:
		status_billboard_label.text = "[ 💥 KOLLISION! MUTUAL EXCLUSION VERLETZT ]"
		status_billboard_label.modulate = Color(1.0, 0.1, 0.1)
	elif in_cs_count == 0:
		status_billboard_label.text = "[ KRITISCHER ABSCHNITT: FREI ]"
		status_billboard_label.modulate = Color(0.2, 1.0, 0.4)
	elif in_cs_count == 1:
		var active_id = 0 if train_positions[0].z >= BRIDGE_ENTRY_Z and train_positions[0].z <= BRIDGE_EXIT_Z else 1
		status_billboard_label.text = "[ 🔒 BELEGT DURCH THREAD %d ]" % active_id
		status_billboard_label.modulate = Color(0.1, 0.8, 1.0) if active_id == 0 else Color(1.0, 0.5, 0.1)

func update_hud() -> void:
	state_label_t0.text = "Interested[0]: %s" % ("TRUE" if interested[0] else "FALSE")
	state_label_t0.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0) if interested[0] else Color(0.6, 0.7, 0.8))

	state_label_t1.text = "Interested[1]: %s" % ("TRUE" if interested[1] else "FALSE")
	state_label_t1.add_theme_color_override("font_color", Color(1.0, 0.55, 0.0) if interested[1] else Color(0.6, 0.7, 0.8))

	var turn_str = "None (-1)"
	if turn == 0: turn_str = "0 (👈 Vorrang für T0)"
	elif turn == 1: turn_str = "1 (👉 Vorrang für T1)"
	state_label_turn.text = "Variable _turn: %s" % turn_str

	if in_cs_count > 1:
		state_label_cs.text = "Brücke: 💥 KOLLISION!"
		state_label_cs.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	elif in_cs_count == 1:
		var id = 0 if train_positions[0].z >= BRIDGE_ENTRY_Z and train_positions[0].z <= BRIDGE_EXIT_Z else 1
		state_label_cs.text = "Brücke: 🔒 BELEGT (T%d)" % id
		state_label_cs.add_theme_color_override("font_color", Color(0.2, 0.7, 1.0) if id == 0 else Color(1.0, 0.6, 0.2))
	else:
		state_label_cs.text = "Brücke: 🔓 FREI"
		state_label_cs.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))

	# Code Highlights
	update_code_highlights(code_t0_labels, thread_states[0])
	update_code_highlights(code_t1_labels, thread_states[1])

func update_code_highlights(labels: Array[Label], state: ThreadState) -> void:
	for lbl in labels:
		lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))

	match state:
		ThreadState.DECLARED_INTEREST:
			if labels.size() > 0: labels[0].add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
		ThreadState.YIELDED_TURN:
			if labels.size() > 1: labels[1].add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
		ThreadState.BUSY_WAITING:
			if labels.size() > 2: labels[2].add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
		ThreadState.IN_CRITICAL_SECTION:
			if labels.size() > 3: labels[3].add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		ThreadState.EXITED:
			if labels.size() > 4: labels[4].add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))

# ==============================================================================
# BUTTON EVENT HANDLERS
# ==============================================================================

func _on_select_peterson() -> void:
	reset_simulation(ScenarioMode.PETERSON_SAFE)

func _on_select_unsynchronized() -> void:
	reset_simulation(ScenarioMode.UNSYNCHRONIZED_CRASH)

func _on_select_deadlock() -> void:
	reset_simulation(ScenarioMode.DEADLOCK_NO_TURN)

func _on_select_step_by_step() -> void:
	reset_simulation(ScenarioMode.STEP_BY_STEP)

func _on_click_start() -> void:
	if not is_running:
		is_running = true
		thread_states[0] = ThreadState.APPROACHING
		thread_states[1] = ThreadState.APPROACHING

func _on_click_reset() -> void:
	reset_simulation(current_mode)

func _on_click_step() -> void:
	# Advance step in STEP_BY_STEP mode
	step_index += 1
	execute_single_step(step_index)
	update_visuals()
	update_hud()

func execute_single_step(idx: int) -> void:
	match idx:
		1:
			thread_states[0] = ThreadState.DECLARED_INTEREST
			interested[0] = true
			train_positions[0].z = SENSOR_Z
			train_0.position = train_positions[0]
			narration_label.text = "Schritt 1: Thread 0 meldet Interesse an (interested[0] = true)."
		2:
			thread_states[1] = ThreadState.DECLARED_INTEREST
			interested[1] = true
			train_positions[1].z = SENSOR_Z
			train_1.position = train_positions[1]
			narration_label.text = "Schritt 2: Thread 1 meldet ebenfalls Interesse an (interested[1] = true)."
		3:
			thread_states[0] = ThreadState.YIELDED_TURN
			turn = 1
			narration_label.text = "Schritt 3: Thread 0 ist höflich: turn = 1 (Vortritt an Thread 1 übergeben)."
		4:
			thread_states[1] = ThreadState.YIELDED_TURN
			turn = 0
			narration_label.text = "Schritt 4: Thread 1 überschreibt: turn = 0 (Vortritt an Thread 0 übergeben!). Der Zweite gewährt dem Ersten den Vortritt!"
		5:
			# T0 evaluates while (interested[1] && turn == 1) -> FALSE because turn == 0
			thread_states[0] = ThreadState.IN_CRITICAL_SECTION
			train_positions[0].z = 0.0
			train_positions[0].x = 0.0
			train_0.position = train_positions[0]
			# T1 evaluates while (interested[0] && turn == 0) -> TRUE because turn == 0
			thread_states[1] = ThreadState.BUSY_WAITING
			train_positions[1].z = BARRIER_Z
			train_1.position = train_positions[1]
			narration_label.text = "Schritt 5: Thread 0 betritt die Brücke! Thread 1 muss an der Schranke warten."
		6:
			# T0 leaves
			thread_states[0] = ThreadState.EXITED
			interested[0] = false
			train_positions[0].z = BRIDGE_EXIT_Z + 4.0
			train_positions[0].x = -LATERAL_OFFSET
			train_0.position = train_positions[0]
			# T1 can now enter because interested[0] is false!
			thread_states[1] = ThreadState.IN_CRITICAL_SECTION
			train_positions[1].z = 0.0
			train_positions[1].x = 0.0
			train_1.position = train_positions[1]
			narration_label.text = "Schritt 6: Thread 0 gibt den Bereich frei (interested[0] = false). Thread 1 betritt nun die Brücke!"
		7:
			# T1 leaves
			thread_states[1] = ThreadState.EXITED
			interested[1] = false
			train_positions[1].z = BRIDGE_EXIT_Z + 4.0
			train_positions[1].x = LATERAL_OFFSET
			train_1.position = train_positions[1]
			narration_label.text = "Schritt 7: Beide Threads haben ihre kritischen Abschnitte serialisiert und kollisionsfrei durchlaufen!"
			status_label.text = "✅ EINZELSCHRITT-ABLAUF ERFOLGREICH BEENDET!"
