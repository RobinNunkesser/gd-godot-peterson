extends SceneTree

# ==============================================================================
# HEADLESS TEST SUITE: Peterson 3D Crash Simulator
# ==============================================================================

func _init() -> void:
	print("🧪 Starting Headless Test Suite for Peterson 3D Crash Simulator...")
	var test_passed = true

	test_passed = test_passed and test_scene_initialization()
	test_passed = test_passed and test_step_by_step_execution()
	test_passed = test_passed and test_peterson_mutual_exclusion()
	test_passed = test_passed and test_unsynchronized_crash()
	test_passed = test_passed and test_deadlock_detection()

	if test_passed:
		print("✅ ALL TESTS PASSED! Peterson 3D Crash Simulator is 100% verified.")
		quit(0)
	else:
		printerr("❌ TEST SUITE FAILED!")
		quit(1)

func test_scene_initialization() -> bool:
	print("\n--- Test 1: Scene Initialization ---")
	var main_scene = load("res://main.tscn")
	if not main_scene:
		printerr("FAIL: Could not load res://main.tscn")
		return false

	var instance = main_scene.instantiate()
	if not instance:
		printerr("FAIL: Could not instantiate main.tscn")
		return false

	root.add_child(instance)
	instance._ready()

	if not instance.get_node_or_null("MainCamera"):
		printerr("FAIL: MainCamera not found")
		instance.queue_free()
		return false

	if not instance.get_node_or_null("Train0") or not instance.get_node_or_null("Train1"):
		printerr("FAIL: Trains not found")
		instance.queue_free()
		return false

	print("PASS: Scene graph and core 3D nodes verified.")
	instance.queue_free()
	return true

func test_step_by_step_execution() -> bool:
	print("\n--- Test 2: Step-by-Step Deterministic Trace ---")
	var main_scene = load("res://main.tscn")
	var sim = main_scene.instantiate()
	root.add_child(sim)
	sim._ready()

	sim.reset_simulation(sim.ScenarioMode.STEP_BY_STEP)

	# Step 1: T0 interest
	sim.execute_single_step(1)
	if not sim.interested[0] or sim.interested[1]:
		printerr("FAIL Step 1: interested[0] should be true")
		sim.queue_free()
		return false

	# Step 2: T1 interest
	sim.execute_single_step(2)
	if not sim.interested[0] or not sim.interested[1]:
		printerr("FAIL Step 2: both interested should be true")
		sim.queue_free()
		return false

	# Step 3: T0 yields turn
	sim.execute_single_step(3)
	if sim.turn != 1:
		printerr("FAIL Step 3: turn should be 1")
		sim.queue_free()
		return false

	# Step 4: T1 yields turn (overwrites turn to 0)
	sim.execute_single_step(4)
	if sim.turn != 0:
		printerr("FAIL Step 4: turn should be 0")
		sim.queue_free()
		return false

	# Step 5: T0 enters Critical Section, T1 waits
	sim.execute_single_step(5)
	if sim.thread_states[0] != sim.ThreadState.IN_CRITICAL_SECTION:
		printerr("FAIL Step 5: T0 should be IN_CRITICAL_SECTION")
		sim.queue_free()
		return false
	if sim.thread_states[1] != sim.ThreadState.BUSY_WAITING:
		printerr("FAIL Step 5: T1 should be BUSY_WAITING")
		sim.queue_free()
		return false

	# Step 6: T0 exits, T1 enters
	sim.execute_single_step(6)
	if sim.interested[0] != false:
		printerr("FAIL Step 6: interested[0] should be released (false)")
		sim.queue_free()
		return false
	if sim.thread_states[1] != sim.ThreadState.IN_CRITICAL_SECTION:
		printerr("FAIL Step 6: T1 should now be IN_CRITICAL_SECTION")
		sim.queue_free()
		return false

	# Step 7: T1 exits
	sim.execute_single_step(7)
	if sim.interested[1] != false:
		printerr("FAIL Step 7: interested[1] should be released (false)")
		sim.queue_free()
		return false

	print("PASS: Step-by-Step execution verified accurately.")
	sim.queue_free()
	return true

func test_peterson_mutual_exclusion() -> bool:
	print("\n--- Test 3: Peterson Algorithm Safety & Mutual Exclusion ---")
	var main_scene = load("res://main.tscn")
	var sim = main_scene.instantiate()
	root.add_child(sim)
	sim._ready()

	sim.reset_simulation(sim.ScenarioMode.PETERSON_SAFE)
	sim.is_running = true
	sim.thread_states[0] = sim.ThreadState.APPROACHING
	sim.thread_states[1] = sim.ThreadState.APPROACHING

	# Simulate 200 physics ticks with dt = 0.05
	var dt = 0.05
	var max_simultaneous_cs = 0

	for frame in range(300):
		sim.process_peterson(dt)
		sim.check_critical_section()
		if sim.in_cs_count > max_simultaneous_cs:
			max_simultaneous_cs = sim.in_cs_count

		if sim.collision_detected:
			printerr("FAIL: Collision occurred in Peterson safe mode at frame ", frame)
			sim.queue_free()
			return false

	if max_simultaneous_cs > 1:
		printerr("FAIL: Mutual exclusion violated! Max simultaneous in CS: ", max_simultaneous_cs)
		sim.queue_free()
		return false

	if max_simultaneous_cs == 0:
		printerr("FAIL: Neither thread entered CS")
		sim.queue_free()
		return false

	if sim.thread_states[0] != sim.ThreadState.EXITED or sim.thread_states[1] != sim.ThreadState.EXITED:
		printerr("FAIL: Not both threads reached EXITED state")
		sim.queue_free()
		return false

	print("PASS: Peterson algorithm safely guarantees mutual exclusion (Max in CS = %d, Crashes = 0)." % max_simultaneous_cs)
	sim.queue_free()
	return true

func test_unsynchronized_crash() -> bool:
	print("\n--- Test 4: Unsynchronized Race Condition (Crash Detection) ---")
	var main_scene = load("res://main.tscn")
	var sim = main_scene.instantiate()
	root.add_child(sim)
	sim._ready()

	sim.reset_simulation(sim.ScenarioMode.UNSYNCHRONIZED_CRASH)
	sim.is_running = true

	var dt = 0.05
	var crashed = false

	for frame in range(120):
		sim.process_unsynchronized(dt)
		if sim.collision_detected:
			crashed = true
			break

	if not crashed:
		printerr("FAIL: Unsynchronized mode failed to detect a collision!")
		sim.queue_free()
		return false

	print("PASS: Unsynchronized mode accurately triggers 3D collision upon simultaneous entry.")
	sim.queue_free()
	return true

func test_deadlock_detection() -> bool:
	print("\n--- Test 5: Deadlock / Livelock Detection (Without Turn) ---")
	var main_scene = load("res://main.tscn")
	var sim = main_scene.instantiate()
	root.add_child(sim)
	sim._ready()

	sim.reset_simulation(sim.ScenarioMode.DEADLOCK_NO_TURN)
	sim.is_running = true
	sim.thread_states[0] = sim.ThreadState.APPROACHING
	sim.thread_states[1] = sim.ThreadState.APPROACHING

	var dt = 0.05
	for frame in range(150):
		sim.process_deadlock(dt)
		if sim.deadlock_detected:
			break

	if not sim.deadlock_detected:
		printerr("FAIL: Deadlock was not detected in mode DEADLOCK_NO_TURN")
		sim.queue_free()
		return false

	print("PASS: Deadlock condition accurately identified (Cyclic busy-wait).")
	sim.queue_free()
	return true
