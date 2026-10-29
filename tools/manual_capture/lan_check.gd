extends Node
## Runs the LAN smoke tests (normal, Player 2 blip, host blip) and writes the
## exit codes to test_out/lan_check.txt. Documentation helper only.

func _ready() -> void:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var out := FileAccess.open(ProjectSettings.globalize_path("res://test_out/lan_check.txt"), FileAccess.WRITE)
	for case in [[""], ["--blip"], ["--host-blip"]]:
		var host_args := PackedStringArray(["--headless", "--path", proj, "--", "--lan-smoke", "--role=host"])
		var client_args := PackedStringArray(["--headless", "--path", proj, "--", "--lan-smoke", "--role=client", "--mobile"])
		if case[0] != "":
			host_args.append(case[0])
			client_args.append(case[0])
		var started := Time.get_ticks_msec()
		var h := OS.create_process(exe, host_args)
		await get_tree().create_timer(2.0).timeout
		var c := OS.create_process(exe, client_args)
		var t := 0.0
		while (OS.is_process_running(h) or OS.is_process_running(c)) and t < 300.0:
			await get_tree().create_timer(1.0).timeout
			t += 1.0
		var line := "case=%s host_exit=%d client_exit=%d seconds=%.0f" % [case[0] if case[0] != "" else "normal",
			OS.get_process_exit_code(h), OS.get_process_exit_code(c), (Time.get_ticks_msec() - started) / 1000.0]
		print(line)
		out.store_line(line)
		out.flush()
	out.store_line("DONE")
	out.close()
	get_tree().quit(0)
