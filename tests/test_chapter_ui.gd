extends SceneTree
const Chapter=preload("res://scripts/chapter.gd")
const State=preload("res://scripts/state.gd")
var checks=0
var failures=0
func check(ok:bool,msg:String):
	checks+=1
	if not ok:failures+=1;push_error(msg)
func find(node:Node,text:String):
	if node is Button and node.text.begins_with(text):return node
	for child in node.get_children():
		var result=find(child,text)
		if result!=null:return result
	return null
func capture(path:String):
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(path)
func advance(app,seconds:float):
	for i in ceili(seconds*30):
		app.world.step(1.0/30.0)
		if app.world.battle.can_auto_skill():app.world.battle.skill()
func place(app,id:String):
	if id in ["lumber","farm"]:find(app.sidebar,"Поставить: "+app.state.catalog.building(id).name).pressed.emit()
	else:find(app.sidebar,"Поставить секцию стены").pressed.emit()
	var def=app.state.catalog.building(id)
	for y in range(6,18):
		for x in range(10,25):
			var point=Vector2i(x,y)
			if not app.state.can_build(id,point).is_empty() or not Chapter.placement_reason(app.state,id,point).is_empty():continue
			var occupied=false
			for dx in int(def.width):
				for dy in int(def.height):
					if app.world.occupied(point+Vector2i(dx,dy)):occupied=true
			if occupied:continue
			var count=app.state.data.buildings.size();app._base_click(point)
			check(app.state.data.buildings.size()==count+1,"placement shortcut builds actual "+id);app._set_tab("mission");return
	check(false,"no legal UI placement for "+id)
func _initialize():
	call_deferred("run")
	create_timer(60).timeout.connect(func():push_error("chapter UI timed out");quit(1))
func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame
	app.session_started=false;app._open_main_menu();root.size=Vector2i(1152,720)
	app.start_menu.seed_input.text="20261029";app.start_menu.name_input.text="Первый рубеж";app.start_menu.threat.select(1);app.start_menu._mode_hint()
	check(app.start_menu.guided.button_pressed and app.start_menu.new_button.text.contains("Первый рубеж"),"first episode is clear default new game")
	await capture("res://work/ui-chapter-menu.png")
	check(app.start_menu.get_global_rect().encloses(app.start_menu.exit_button.get_global_rect()),"menu still fits smallest supported window")
	app.start_menu.new_button.pressed.emit();await process_frame
	check(app.tab=="mission" and app.state.data.chapter.phase=="supply" and app.objective_panel.visible,"actual menu starts episode with persistent objective")
	await capture("res://work/ui-chapter-intro.png")
	find(app.sidebar,"Лесное дело").pressed.emit();find(app.sidebar,"Агротехника").pressed.emit()
	place(app,"lumber");place(app,"farm")
	for i in 240:
		advance(app,1)
		if app.state.data.chapter.phase!="supply":break
	app._set_tab("mission");check(app.state.data.chapter.phase=="prepare","real production moves UI to preparation")
	find(app.sidebar,"Лучники и укрепления").pressed.emit();place(app,"wall");place(app,"wall")
	for i in 4:find(app.sidebar,"Нанять лучника").pressed.emit()
	for i in 180:
		advance(app,1)
		if Chapter.ready_reason(app.state).is_empty():break
	app._refresh();var begin=find(app.sidebar,"Встретить разъезд")
	check(begin!=null and not begin.disabled,"prepared episode exposes enabled battle action")
	await capture("res://work/ui-chapter-prepared.png")
	find(app.sidebar,"Встретить разъезд").pressed.emit();find(app.sidebar,"Расставить защитный строй").pressed.emit()
	check(app.state.data.chapter.phase=="countdown" and app.base.command_group=="all","formation action issues real group orders during approach")
	check(app.state.save_progress(),"formation UI creates valid persisted orders")
	var resumed=State.new(app.state.save_path);resumed.load_progress();app._activate_party(resumed)
	check(app.tab=="mission" and app.state.data.chapter.phase=="countdown","loading ongoing episode returns to its objective and controls")
	advance(app,31);app._refresh();await capture("res://work/ui-chapter-battle.png")
	check(app.state.data.chapter.phase=="battle" and app.live_labels.chapter.text.contains("Противников осталось"),"battle HUD shows live encounter state")
	for i in 240:
		advance(app,1)
		if app.state.data.chapter.phase!="battle":break
	app._refresh();await capture("res://work/ui-chapter-victory.png")
	check(app.state.data.chapter.phase=="won" and app.tab=="mission" and find(app.sidebar,"Продолжить поселение")!=null,"victory returns to episode result and continuing goal")
	check(app.world.paused,"victory pauses time to read rewards safely")
	check(app.root.get_global_rect().end.y<=app.size.y+1,"objective and victory layout fit minimum window")
	var coins=int(app.state.data.coins);app.world.paused=false;app.world.start_raid()
	for unit in app.world.battle.units:
		if unit.team==1:unit.hp=0
	app.world.step(1.0/30.0)
	check(not app.world.paused and app.state.data.coins==coins+55,"ordinary next raid does not reopen or reward chapter result")
	find(app.sidebar,"Продолжить поселение").pressed.emit();await process_frame
	check(app.state.data.chapter.phase=="free" and not app.world.paused and not app.objective_panel.visible and find(app.toolbar,"Мир")!=null,"continuation unlocks full settlement interface")
	check(app.state.save_progress(),"completed UI episode saves")
	print("CHAPTER_UI_TESTS "+JSON.stringify({"checks":checks,"failures":failures}));quit(1 if failures else 0)
