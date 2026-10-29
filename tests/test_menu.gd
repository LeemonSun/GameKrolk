extends SceneTree

const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Rules=preload("res://scripts/world_rules.gd")
var checks=0
var failures=0

func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)

func capture(path:String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _initialize():call_deferred("run")

func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.session_started=false;app._open_main_menu()
	check(app.start_menu.visible and app.start_menu.continue_button.disabled,"empty library opens at new game without a false Continue")
	var clock=app.state.data.world.clock
	for i in 3:await process_frame
	check(app.state.data.world.clock==clock,"world does not advance behind start screen")
	app.start_menu.seed_input.text="wrong";app.start_menu._new_game()
	check(not app.start_menu.message.text.is_empty() and not app.session_started,"invalid seed shows error without creating a game")
	await capture("res://work/ui-menu-new.png")
	check(app.start_menu.get_global_rect().encloses(app.start_menu.exit_button.get_global_rect()),"new game form fits without hiding exit below screen")
	app.start_menu.seed_input.text="314159";app.start_menu.name_input.text="Тихая бухта";app.start_menu.threat.select(0);app.start_menu.threat.item_selected.emit(0);app.start_menu._new_game()
	check(app.session_started and not app.start_menu.visible,"New game button enters playable world")
	check(app.state.data.world.seed==314159 and Rules.mode(app.state.data)=="calm" and app.state.data.world.raid_in>359,"seed and peaceful threat mode affect actual world")
	check(app.state.data.profile.name=="Тихая бухта" and app.state._valid(app.state.data),"party name is saved in validated state")
	var first_path=app.state.save_path
	check(first_path.begins_with(app.profiles.directory) and FileAccess.file_exists(first_path),"new party has its own file")
	check(app.profiles.last_path()==first_path,"last selected party is remembered")
	app.base.order_requested.emit("hero",Vector2(18.5,14.5)*32)
	check(app.world.battle.units[0].goal!=Vector2.INF and app.base.order_requested.get_connections().size()==1,"orders are connected to the newly created world exactly once")
	app._open_main_menu();clock=app.state.data.world.clock
	var first_text=FileAccess.get_file_as_string(first_path)
	for i in 3:await process_frame
	check(app.state.data.world.clock==clock and app.start_menu.back_button.visible,"in-game menu pauses simulation and offers return")
	app.start_menu.seed_input.text="271828";app.start_menu.name_input.text="Острый берег";app.start_menu.threat.select(2);app.start_menu.threat.item_selected.emit(2);app.start_menu._new_game()
	check(app.start_menu.description.text==Rules.MODES.harsh.hint,"mode dropdown updates explanation")
	var second_path=app.state.save_path
	check(second_path!=first_path and FileAccess.get_file_as_string(first_path)==first_text,"another game preserves previous settlement byte for byte")
	check(Rules.mode(app.state.data)=="harsh" and app.state.data.world.raid_in>89 and app.state.data.world.raid_in<=90,"dangerous mode starts with its shorter raid timer")
	check(app.profiles.entries().size()==2 and app.profiles.last_path()==second_path,"both games appear in save library")
	app._open_main_menu();await capture("res://work/ui-menu-saves.png")
	app._continue_profile(first_path)
	check(app.state.save_path==first_path and app.state.data.profile.name=="Тихая бухта" and Rules.mode(app.state.data)=="calm","Continue restores selected party rather than replacing it")
	check(app.profiles.last_path()==first_path and not app.start_menu.visible,"selection persists after continue")
	var terrain=app.state.data.world.tiles.duplicate()
	app._open_main_menu();app._continue_profile(second_path)
	check(app.state.data.world.tiles!=terrain,"different seeds produce different terrain")
	app._open_main_menu();var count=app.profiles.paths().size()
	app._new_party(0,"standard","bad")
	check(app.start_menu.visible and not app.start_menu.message.text.is_empty() and app.profiles.paths().size()==count,"model rejects bad game options without writing an extra save")
	app._resume_game();check(not app.start_menu.visible,"return resumes existing session without reload")
	var backup_path=app.profiles.directory.path_join("backup-only.json")
	var backup=FileAccess.open(backup_path+".bak",FileAccess.WRITE);backup.store_string(first_text);backup.close()
	var recovered=State.new(backup_path)
	check(recovered.load_progress() and not recovered.warning.is_empty() and recovered.data.profile.name=="Тихая бухта","backup-only party recovers even if primary is missing")
	var broken_path=app.profiles.directory.path_join("broken.json")
	var file=FileAccess.open(broken_path,FileAccess.WRITE);file.store_string("broken");file.close()
	var entries=app.profiles.entries();var bad_found=false;var recovered_found=false
	for item in entries:
		if item.path==broken_path:bad_found=not item.valid
		if item.path==backup_path:recovered_found=item.valid
	check(bad_found and recovered_found,"library separates unreadable games from recoverable backups")
	file=FileAccess.open(app.profiles.index_path,FileAccess.WRITE);file.store_string(JSON.stringify({"path":"user://outside-library.json"}));file.close()
	check(app.profiles.last_path() in app.profiles.paths(),"untrusted index cannot choose a path outside known saves")
	var sizes=[];var strengths=[];var intervals=[]
	for mode in ["calm","standard","harsh"]:
		var state=State.new("res://work/menu-mode-"+mode+".json");state.new_game(123,mode,"Mode fixture")
		var world=World.new(state);world.start_raid()
		sizes.append(world.battle.alive(1));strengths.append(world.battle.units[-1].damage)
		for unit in world.battle.units:
			if unit.team==1:unit.hp=0
		world.step(1.0/30.0);intervals.append(state.data.world.raid_in)
	check(sizes==[6,12,18],"threat choice changes actual attacking force")
	check(strengths[0]<strengths[1] and strengths[1]<strengths[2],"threat choice changes real enemy damage")
	check(intervals==[360.0,180.0,120.0],"mode controls subsequent raids too")
	root.size=Vector2i(1152,720);app._open_main_menu();await capture("res://work/ui-menu-small.png")
	check(app.start_menu.get_global_rect().encloses(app.start_menu.exit_button.get_global_rect()),"in-game menu fits at minimum window size")
	print("MENU_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"separate_games":count,"raid_sizes":sizes,"mode_intervals":intervals}))
	quit(1 if failures else 0)
