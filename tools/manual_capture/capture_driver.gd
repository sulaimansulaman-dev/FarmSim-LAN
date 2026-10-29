extends Node
## Manual screenshot driver (documentation only - not part of the game).
##
## Started by tools/manual_capture/capture.tscn. With no --cap= argument it is
## the "director": it runs the automated test suite, then starts one copy of the
## game per capture job and waits for each to finish. Each job walks the real
## screens and saves PNGs to test_out/manual_shots/.

const OUT_REL := "res://test_out/manual_shots"
const SCENE := "res://tools/manual_capture/capture.tscn"

var job := ""
var out_dir := ""
var _log: FileAccess = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = ProjectSettings.globalize_path(OUT_REL)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			job = arg.trim_prefix("--cap=")
	_log = FileAccess.open(out_dir.path_join("log_%s.txt" % (job if job != "" else "director")), FileAccess.WRITE)
	note("job=%s mobile=%s" % [job, Config.is_mobile()])
	match job:
		"": _director()
		"desktop": _desktop()
		"lan_host": _lan_host(false)
		"lan_client": _lan_client()
		"mhost": _lan_host(true)
		"mclient": _mobile_client()
		"msolo": _mobile_solo()
		"dsolo": _desktop_solo()
		_: get_tree().quit(2)


func note(text: String) -> void:
	print("[cap:%s] %s" % [job, text])
	if _log != null:
		_log.store_line("%.1f %s" % [Time.get_ticks_msec() / 1000.0, text])
		_log.flush()


# ---------------------------------------------------------------- helpers ---

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func shot(shot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	note("shot %s (%dx%d)" % [shot_name, img.get_width(), img.get_height()])


func scene_named(scene_name: String, timeout := 30.0) -> Node:
	var t := 0.0
	while t < timeout:
		var s := get_tree().current_scene
		if s != null and String(s.name) == scene_name and s.is_node_ready():
			await wait(0.6)
			return get_tree().current_scene
		await wait(0.1)
		t += 0.1
	note("TIMEOUT waiting for %s (current %s)" % [scene_name,
		get_tree().current_scene.name if get_tree().current_scene else "none"])
	return null


func press(scene: Node, path: String) -> void:
	if scene == null:
		return
	var b := scene.get_node_or_null(path) as Button
	if b == null:
		b = scene.find_child(path, true, false) as Button
	if b == null:
		note("no button %s" % path)
		return
	b.pressed.emit()


func q_visible(scene: Node) -> bool:
	var q := scene.find_child("Question", true, false) as Control
	return q != null and q.visible


## Answers the questions currently showing on an assessment screen for one
## player. pick: -1 = correct answer, otherwise that option index.
func answer_player(scene: Node, pick := 0) -> void:
	var guard := 0
	while is_instance_valid(scene) and q_visible(scene) and guard < 30:
		guard += 1
		var idx := pick
		if pick < 0:
			idx = int(scene._current_question().get("correct_index", 0))
		scene._on_option_pressed(idx)
		await get_tree().process_frame
		if not is_instance_valid(scene):
			return
		press(scene, "NextButton")
		await get_tree().process_frame
		await get_tree().process_frame


## Offline two-player assessment: P1, hand-over, P2.
func answer_both(scene: Node, pick := 0) -> void:
	await answer_player(scene, pick)
	if not is_instance_valid(scene):
		return
	await wait(0.2)
	if is_instance_valid(scene) and not q_visible(scene):
		press(scene, "NextButton")
		await wait(0.3)
		if is_instance_valid(scene):
			await answer_player(scene, pick)


func answer_usability(scene: Node, shoot := "") -> void:
	var content := "Page/PageScroll/Row/PageContent"
	var guard := 0
	var shot_done := shoot.is_empty()
	while is_instance_valid(scene) and guard < 60:
		guard += 1
		var statement := scene.get_node(content + "/Statement") as Control
		var handover := scene.get_node(content + "/HandoverButton") as Button
		if statement.visible:
			if not shot_done:
				shot_done = true
				(scene.get_node(content + "/Answers").get_child(0) as Button).grab_focus()
				await shot(shoot)
			(scene.get_node(content + "/Answers").get_child(guard % 2) as Button).pressed.emit()
		elif handover.visible and not handover.disabled:
			handover.pressed.emit()
		else:
			await wait(0.3)
		await wait(0.1)


func act(farm: Node, p: int, tool_id: int, tile: Node, move := true) -> Dictionary:
	var pl: Node = farm.players[p]
	if move:
		pl.global_position = tile.global_position + Vector2(0, 10)
	if tool_id in pl.tools:
		pl.select_tool(tool_id)
	return farm.perform_action(pl, tool_id, tile)


func tiles(farm: Node, coords: Array) -> Array:
	var out := []
	for c in coords:
		out.append(farm.field.tile_at(c.x, c.y))
	return out


func sow(farm: Node, p: int, list: Array, crop_tool := Config.Tool.SEED) -> void:
	for t in list:
		act(farm, p, Config.Tool.HOE, t)
		act(farm, p, crop_tool, t)
		act(farm, p, Config.Tool.WATER, t)


## Moves the season clock on quickly, keeping `watered` tiles out of stress.
func advance(farm: Node, seconds: float, watered: Array, waterers := [0], threshold := 0.5) -> void:
	var t := 0.0
	var step := 0.5
	var n := 0
	while t < seconds and is_instance_valid(farm) and farm.running:
		if farm.elapsed + step >= farm.duration - 1.0:
			break
		farm.simulate(step)
		t += step
		n += 1
		for tile in watered:
			if tile.is_planted() and tile.moisture < threshold and farm.water.remaining >= Config.WATER_COST_PER_ACTION:
				act(farm, waterers[n % waterers.size()], Config.Tool.WATER, tile, false)
		if n % 10 == 0:
			await get_tree().process_frame


func harvest_all(farm: Node, p: int) -> void:
	for t in farm.field.tiles:
		if t.can_harvest():
			act(farm, p, Config.Tool.HARVEST, t)


func place(farm: Node, p: int, tile: Node, offset := Vector2(0, 10)) -> void:
	farm.players[p].global_position = tile.global_position + offset


# --------------------------------------------------------------- director ---

func _spawn(args: Array, wait_for := true, limit := 600.0) -> int:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var full: Array = ["--path", proj]
	full.append_array(args)
	var pid := OS.create_process(exe, PackedStringArray(full))
	note("spawned %s pid=%d" % [str(args), pid])
	if wait_for and pid > 0:
		var t := 0.0
		while OS.is_process_running(pid) and t < limit:
			await wait(1.0)
			t += 1.0
		if OS.is_process_running(pid):
			OS.kill(pid)
			note("killed %d after %.0f s" % [pid, t])
	return pid


func _job(cap: String, res: String, pos: String, extra := []) -> Array:
	var a: Array = [SCENE, "--resolution", res, "--position", pos, "--", "--cap=" + cap]
	a.append_array(extra)
	return a


func _director() -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://test_out/test_results.json")):
		await _spawn(["--headless", "--", "--run-tests"], true, 900.0)
	await _spawn(_job("desktop", "1600x900", "40,40"))
	await _spawn(_job("dsolo", "1600x900", "40,40"))
	# LAN: host and client side by side.
	var host := await _spawn(_job("lan_host", "1280x720", "0,30"), false)
	await wait(4.0)
	await _spawn(_job("lan_client", "1280x720", "600,330"))
	while OS.is_process_running(host):
		await wait(1.0)
	# Phone joining a PC host.
	var mhost := await _spawn(_job("mhost", "1280x720", "0,30"), false)
	await wait(4.0)
	await _spawn(_job("mclient", "1560x720", "200,250", ["--mobile"]))
	while OS.is_process_running(mhost):
		await wait(1.0)
	await _spawn(_job("msolo", "1560x720", "100,100", ["--mobile"]))
	note("ALL DONE")
	get_tree().quit(0)


# ---------------------------------------------------------- desktop offline --

func _desktop() -> void:
	get_tree().change_scene_to_file("res://scenes/boot.tscn")
	await wait(0.35)
	await shot("d01_splash")
	var s := await scene_named("MainMenu")
	await shot("d02_main_menu")
	SessionController.goto_instructions()
	s = await scene_named("Instructions")
	await shot("d03_instructions")
	SessionController.goto_main_menu()
	await scene_named("MainMenu")
	SessionController.start_new_session()
	s = await scene_named("PlayerSetup")
	await shot("d04_player_setup")
	press(s, "Page/PageScroll/Row/PageContent/Buttons/ConfirmButton")

	# Pre-test: one answer chosen (no feedback), then the hand-over.
	s = await scene_named("AssessmentScreen")
	await shot("d05_pre_test")
	s._on_option_pressed(1)
	await shot("d06_pre_test_selected")
	await answer_player(s, 0)
	await wait(0.3)
	await shot("d07_handover")
	press(s, "NextButton")
	await wait(0.3)
	await answer_player(s, 0)

	# ---- Season 1: baseline maize
	s = await scene_named("ScenarioBriefing")
	await shot("d08_briefing_1")
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	var farm := await scene_named("Farm")
	await wait(0.5)
	await shot("d09_farm_1_start")
	var bed := tiles(farm, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3)])
	act(farm, 0, Config.Tool.HOE, bed[0])
	place(farm, 0, bed[0])
	await shot("d10_farm_till")
	act(farm, 0, Config.Tool.SEED, bed[0])
	act(farm, 0, Config.Tool.WATER, bed[0])
	sow(farm, 0, bed.slice(1))
	await advance(farm, 30.0, bed, [0, 1])
	act(farm, 1, Config.Tool.INSPECT, bed[6])
	act(farm, 0, Config.Tool.WATER, bed[2])
	place(farm, 0, bed[2], Vector2(-8, 18))
	place(farm, 1, bed[6], Vector2(8, 18))
	await wait(0.2)
	await shot("d11_farm_1_growing")
	farm.pause_overlay.set_paused(true)
	await wait(0.4)
	await shot("d12_pause")
	farm.pause_overlay.set_paused(false)
	await wait(0.2)
	await advance(farm, 112.0, bed, [0, 1])
	await wait(0.2)
	await shot("d13_farm_1_mature")
	harvest_all(farm, 0)
	place(farm, 1, bed[8])
	await wait(0.2)
	await shot("d14_farm_1_harvested")
	farm.finish_season("time")
	s = await scene_named("ScenarioResults")
	await shot("d15_results_1")
	press(s, "Page/PageScroll/Row/PageContent/ContinueButton")

	s = await scene_named("AssessmentScreen")
	await shot("d16_quiz_question")
	s._on_option_pressed(int(s._current_question().get("correct_index", 0)))
	await shot("d17_quiz_correct")
	press(s, "NextButton")
	await wait(0.3)
	var right := int(s._current_question().get("correct_index", 0))
	s._on_option_pressed(0 if right != 0 else 1)
	await shot("d18_quiz_wrong")
	press(s, "NextButton")
	await wait(0.2)
	await answer_both(s, -1)

	# ---- Season 2: pests
	s = await scene_named("ScenarioBriefing")
	await shot("d19_briefing_2")
	SessionController.request_exit()
	await wait(0.4)
	await shot("d20_exit_dialog")
	SessionController._hide_exit_dialog()
	await wait(0.2)
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	farm = await scene_named("Farm")
	var beans := tiles(farm, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(2, 3), Vector2i(3, 3)])
	sow(farm, 0, beans)
	await advance(farm, 36.0, beans, [0, 1])
	place(farm, 0, beans[1])
	place(farm, 1, beans[6])
	await wait(0.3)
	await shot("d21_farm_2_outbreak")
	farm.hud.close_event()
	await advance(farm, 10.0, beans, [0])
	for t in beans:
		act(farm, 1, Config.Tool.INSPECT, t)
	var first_pest: Node = null
	for t in beans:
		if t.infested and first_pest == null:
			first_pest = t
	if first_pest != null:
		act(farm, 1, Config.Tool.INSPECT, first_pest)
	act(farm, 0, Config.Tool.WATER, beans[0])
	place(farm, 0, beans[0], Vector2(-6, 18))
	await wait(0.3)
	await shot("d22_farm_2_scouted")
	if first_pest != null:
		act(farm, 1, Config.Tool.TREAT, first_pest)
	await wait(0.2)
	await shot("d23_farm_2_treated")
	for t in beans:
		if t.infested:
			act(farm, 1, Config.Tool.TREAT, t)
	var k := 0
	while k < 16:
		k += 1
		await advance(farm, 4.5, beans, [0])
		for t in beans:
			if t.is_planted():
				act(farm, 1, Config.Tool.INSPECT, t, false)
				if t.infested:
					act(farm, 1, Config.Tool.TREAT, t, false)
	harvest_all(farm, 0)
	harvest_all(farm, 1)
	await advance(farm, 20.0, [], [0])
	farm.finish_season("time")
	s = await scene_named("ScenarioResults")
	await shot("d24_results_2")
	press(s, "Page/PageScroll/Row/PageContent/ContinueButton")
	s = await scene_named("AssessmentScreen")
	await answer_both(s, -1)

	# ---- Season 3: drought - six sown, four protected
	s = await scene_named("ScenarioBriefing")
	await shot("d25_briefing_3")
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	farm = await scene_named("Farm")
	var dry := tiles(farm, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(6, 2), Vector2i(7, 2)])
	var kept := dry.slice(0, 4)
	sow(farm, 0, dry)
	await advance(farm, 31.0, kept, [0, 1], 0.46)
	place(farm, 0, dry[0])
	place(farm, 1, dry[3])
	await wait(0.3)
	await shot("d26_farm_3_drought")
	farm.hud.close_event()
	await advance(farm, 60.0, kept, [0, 1], 0.46)
	act(farm, 1, Config.Tool.INSPECT, dry[4])
	act(farm, 0, Config.Tool.WATER, dry[1])
	place(farm, 1, dry[4])
	await wait(0.2)
	await shot("d27_farm_3_low_water")
	await advance(farm, 52.0, kept, [0, 1], 0.46)
	harvest_all(farm, 0)
	var guard := 0
	while farm.water.remaining >= Config.WATER_COST_PER_ACTION and guard < 100:
		guard += 1
		act(farm, 0, Config.Tool.WATER, dry[4 + guard % 2], false)
	act(farm, 1, Config.Tool.INSPECT, dry[5])
	act(farm, 0, Config.Tool.WATER, dry[4])
	await wait(0.2)
	await shot("d28_farm_3_empty")
	farm.finish_season("time")
	s = await scene_named("ScenarioResults")
	await shot("d29_results_3")
	press(s, "Page/PageScroll/Row/PageContent/ContinueButton")
	s = await scene_named("AssessmentScreen")
	await answer_both(s, -1)

	# ---- Post-test, usability, final results
	s = await scene_named("AssessmentScreen")
	await shot("d30_post_test")
	await answer_both(s, -1)
	s = await scene_named("UsabilityScreen")
	await answer_usability(s, "d31_usability")
	s = await scene_named("FinalResults")
	await shot("d32_final_results")
	await wait(0.5)
	get_tree().quit(0)


## Solo on a computer: the farm with one farmer and all six tools.
func _desktop_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_named("MainMenu")
	SessionController.start_new_session(true)
	var s := await scene_named("AssessmentScreen")
	await answer_player(s, 0)
	s = await scene_named("ScenarioBriefing")
	await shot("s01_briefing_solo")
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	var farm := await scene_named("Farm")
	var bed := tiles(farm, [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)])
	sow(farm, 0, bed)
	await advance(farm, 40.0, bed, [0])
	act(farm, 0, Config.Tool.INSPECT, bed[4])
	await wait(0.2)
	await shot("s02_farm_solo")
	get_tree().quit(0)


# -------------------------------------------------------------------- LAN ---

func _lan_host(for_phone: bool) -> void:
	var p := "m" if for_phone else "l"
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_named("MainMenu")
	SessionController.goto_multiplayer()
	var s := await scene_named("MultiplayerMenu")
	if not for_phone:
		await shot("l01_host_tab")
	(s.get_node(s.PAGES + "/HostPage/NameRow/HostName") as LineEdit).text = "Sulaiman's farm"
	press(s, s.PAGES + "/HostPage/HostButton")
	await wait(1.0)
	if not for_phone:
		await shot("l02_host_lobby_waiting")
	var t := 0.0
	while not Net.is_ready() and t < 90.0:
		await wait(0.25)
		t += 0.25
	note("partner connected=%s" % Net.is_ready())
	await wait(3.0)
	if not for_phone:
		await shot("l05_host_lobby_ready")
	await wait(4.0)
	press(s, s.PAGES + "/LobbyPage/LobbyButtons/StartButton")
	s = await scene_named("PlayerSetup")
	if not for_phone:
		await shot("l06_host_setup")
	await wait(4.0)
	press(s, "Page/PageScroll/Row/PageContent/Buttons/ConfirmButton")
	s = await scene_named("AssessmentScreen")
	await answer_player(s, 0)
	await wait(0.5)
	if not for_phone:
		await shot("l08_host_waiting_partner")
	s = await scene_named("ScenarioBriefing", 90.0)
	await wait(4.0)
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	var farm := await scene_named("Farm")
	var bed := tiles(farm, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)])
	sow(farm, 0, bed)
	await advance(farm, 35.0, bed, [0])
	place(farm, 0, bed[4])
	act(farm, 0, Config.Tool.WATER, bed[4], false)
	var tw := 0.0
	while not farm.field.tile_at(7, 2).scouted and not farm.field.tile_at(6, 2).scouted and tw < 25.0:
		await wait(0.1)
		tw += 0.1
	await wait(0.4)
	if not for_phone:
		await shot("l10_host_farm")
	# Client takes its farm screenshots, then drops its link on purpose.
	t = 0.0
	while not Net.waiting_for_partner and t < 40.0:
		await wait(0.2)
		t += 0.2
	if not for_phone:
		await shot("l12_host_connection_lost")
		await wait(1.0)
		await shot("l12b_host_connection_lost")
	t = 0.0
	while Net.waiting_for_partner and t < 40.0:
		await wait(0.25)
		t += 0.25
	await wait(3.0)
	farm = get_tree().current_scene
	if for_phone and farm != null and farm.name == "Farm":
		# Let the phone see a pause, then finish the season so it gets the quiz.
		farm.pause_overlay.set_paused(true)
		await wait(5.0)
		farm.pause_overlay.set_paused(false)
		await wait(1.0)
		await advance(farm, 120.0, bed, [0])
		harvest_all(farm, 0)
		await wait(1.0)
		farm.finish_season("time")
		s = await scene_named("ScenarioResults")
		await wait(5.0)
		press(s, "Page/PageScroll/Row/PageContent/ContinueButton")
		s = await scene_named("AssessmentScreen")
		await answer_player(s, -1)
		await wait(25.0)
	SessionController.abandon_session()
	s = await scene_named("MultiplayerMenu")
	if not for_phone:
		await shot("l14_host_back_in_lobby")
	await wait(4.0)
	Net.leave()
	await wait(1.0)
	get_tree().quit(0)


func _lan_client() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_named("MainMenu")
	SessionController.goto_multiplayer()
	var s := await scene_named("MultiplayerMenu")
	s._select_tab(2)
	var addrs := Net.local_addresses()
	(s.get_node(s.PAGES + "/AddressPage/Address") as LineEdit).text = addrs[0] if not addrs.is_empty() else "192.168.0.10"
	await wait(0.3)
	await shot("l03b_join_by_address")
	s._select_tab(1)
	var t := 0.0
	while s._hosts.is_empty() and t < 15.0:
		await wait(0.25)
		t += 0.25
	await wait(1.0)
	await shot("l03_find_games")
	if not s._hosts.is_empty():
		s._join_host(s._hosts[0])
	else:
		s._join("127.0.0.1", Net.GAME_PORT)
	t = 0.0
	while not Net.is_ready() and t < 15.0:
		await wait(0.25)
		t += 0.25
	await wait(1.0)
	await shot("l04_client_lobby")
	s = await scene_named("PlayerSetup", 60.0)
	await shot("l07_client_setup")
	s = await scene_named("AssessmentScreen")
	await wait(3.0)
	await shot("l08b_client_question")
	await answer_player(s, 0)
	s = await scene_named("ScenarioBriefing", 60.0)
	await shot("l09_client_briefing")
	var farm := await scene_named("Farm", 60.0)
	var me: Node = farm.players[1]
	var target: Node = farm.field.tile_at(7, 2)
	me.use_test_input = true
	var guard := 0
	while is_instance_valid(farm) and me.global_position.distance_to(target.global_position) > 18.0 and guard < 600:
		guard += 1
		me.test_input = (target.global_position - me.global_position).normalized()
		await get_tree().physics_frame
	me.test_input = Vector2.ZERO
	me.select_tool(Config.Tool.INSPECT)
	me.try_use()
	await wait(2.5)
	await shot("l11_client_farm")
	await wait(1.0)
	Net.simulate_connection_loss()
	await shot("l13_client_reconnecting")
	await wait(0.4)
	await shot("l13b_client_reconnecting")
	# It redials by itself; then the host ends the session.
	s = await scene_named("MultiplayerMenu", 90.0)
	await wait(1.0)
	await shot("l15_client_back_in_lobby")
	await wait(1.0)
	Net.leave()
	get_tree().quit(0)


# ----------------------------------------------------------------- mobile ---

func _mobile_client() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_named("MainMenu")
	await shot("m01_main_menu")
	SessionController.goto_multiplayer()
	var s := await scene_named("MultiplayerMenu")
	var t := 0.0
	while s._hosts.is_empty() and t < 15.0:
		await wait(0.25)
		t += 0.25
	await wait(1.0)
	await shot("m02_find_games")
	s._select_tab(0)
	await wait(0.4)
	await shot("m02b_host_tab")
	s._select_tab(1)
	t = 0.0
	while s._hosts.is_empty() and t < 15.0:
		await wait(0.25)
		t += 0.25
	if not s._hosts.is_empty():
		s._join_host(s._hosts[0])
	else:
		s._join("127.0.0.1", Net.GAME_PORT)
	t = 0.0
	while not Net.is_ready() and t < 15.0:
		await wait(0.25)
		t += 0.25
	await wait(1.0)
	await shot("m03_lobby")
	s = await scene_named("PlayerSetup", 60.0)
	await shot("m04_player_setup")
	s = await scene_named("AssessmentScreen")
	s._on_option_pressed(1)
	await shot("m05_pre_test")
	await answer_player(s, 0)
	s = await scene_named("ScenarioBriefing", 60.0)
	await shot("m06_briefing")
	var farm := await scene_named("Farm", 60.0)
	var me: Node = farm.players[1]
	var target: Node = farm.field.tile_at(6, 2)
	me.use_test_input = true
	var guard := 0
	while is_instance_valid(farm) and me.global_position.distance_to(target.global_position) > 18.0 and guard < 600:
		guard += 1
		me.test_input = (target.global_position - me.global_position).normalized()
		await get_tree().physics_frame
	me.test_input = Vector2.ZERO
	me.select_tool(Config.Tool.INSPECT)
	me.try_use()
	await wait(4.0)
	await shot("m07_farm")
	Net.simulate_connection_loss()
	await shot("m08_reconnecting")
	await wait(0.4)
	await shot("m08b_reconnecting")
	t = 0.0
	while Net.reconnecting and t < 40.0:
		await wait(0.25)
		t += 0.25
	# The host pauses shortly after.
	t = 0.0
	while not get_tree().paused and t < 20.0:
		await wait(0.1)
		t += 0.1
	await wait(0.6)
	await shot("m09_pause")
	s = await scene_named("ScenarioResults", 120.0)
	await shot("m10_results")
	s = await scene_named("AssessmentScreen", 60.0)
	s._on_option_pressed(int(s._current_question().get("correct_index", 0)))
	await shot("m11_quiz_feedback")
	await answer_player(s, -1)
	s = await scene_named("MultiplayerMenu", 90.0)
	await wait(0.5)
	Net.leave()
	get_tree().quit(0)


func _mobile_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_named("MainMenu")
	SessionController.start_new_session(true)
	var s := await scene_named("AssessmentScreen")
	await answer_player(s, 0)
	s = await scene_named("ScenarioBriefing")
	await shot("m12_briefing_solo")
	press(s, "Page/PageScroll/Row/PageContent/StartButton")
	var farm := await scene_named("Farm")
	var bed := tiles(farm, [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)])
	sow(farm, 0, bed)
	await advance(farm, 40.0, bed, [0])
	place(farm, 0, bed[4])
	act(farm, 0, Config.Tool.INSPECT, bed[4])
	await wait(0.4)
	await shot("m13_farm_solo")
	SessionController.request_exit()
	await wait(0.5)
	await shot("m14_exit_dialog")
	SessionController._hide_exit_dialog()
	farm.finish_season("time")
	s = await scene_named("ScenarioResults")
	await shot("m15_results_solo")
	get_tree().quit(0)
