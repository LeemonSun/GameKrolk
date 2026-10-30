extends SceneTree
const World=preload("res://scripts/world.gd")
const P=preload("res://scripts/personnel.gd")
var failures=0
var checks=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func capture(path:String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _initialize():call_deferred("run")
func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame
	app.state.before_save=Callable();app.state.reset();app.state.save_path="res://work/care-ui.json"
	app.state.data.coins=500;app.state.data.food=100;app.state.data.world.raid_in=9999
	app.state.data.buildings[0].level=2;app.state.data.buildings[0].target_level=2
	for x in range(21,25):
		for y in range(14,18):app.state.data.world.tiles[y*32+x]=0
	for source in app.state.data.world.sources:
		if source.x>=21 and source.x<25 and source.y>=14 and source.y<18:source.amount=0
	app.world=World.new(app.state);app.base.world=app.world;app.world.notice.connect(app._notice)
	app.world.settlement_changed.connect(func():app.call_deferred("_refresh"))
	app.state.build("infirmary",Vector2i(22,15));app.world.rebuild_navigation();app.world._assign_jobs()
	for i in 1200:app.world.step(1.0/30.0)
	check(app.state.level("infirmary")==1,"UI fixture has real completed infirmary")
	app._set_tab("officers")
	for entry in [["commander",0],["quartermaster",1],["medic",2]]:
		var choice=app.sidebar.get_node("choice_"+entry[0]);var selected=-1
		for i in range(1,choice.item_count):
			if choice.get_item_id(i)==entry[1]:selected=i;break
		check(selected>=0,"eligible person shown for "+entry[0])
		if selected>=0:choice.select(selected);choice.item_selected.emit(selected)
		await process_frame
		check(app.state.data.personnel.posts[entry[0]]==entry[1],"selector assigns correct post and person: "+entry[0])
	for i in 450:app.world.step(1.0/30.0)
	check(P.ready(app.state.data,"medic"),"UI medic reaches station")
	root.size=Vector2i(1152,720);app._set_tab("officers")
	await capture("res://work/ui-officers-v7.png")
	app.state.data.personnel.wounded={"militia":3,"archer":2,"guard":1};app._set_tab("medical")
	for i in 180:app.world.step(1.0/30.0)
	app._update_live();await capture("res://work/ui-medical-v7.png")
	check(app.live_labels.medical.text.contains("Раненые: 6"),"medical UI displays actual reserve")
	app._set_tab("people");await capture("res://work/ui-people-v7.png")
	var person=app.state.data.world.workers[0]
	app._base_click(Vector2i(floori(person.x),floori(person.y)))
	check(app.selected_worker==0 and app.base.selected_worker==0 and app.tab=="people","clicking resident on map selects actual person")
	app._focus_worker(2)
	var rect=app.base.grid_rect();var point=rect.position+Vector2(app.state.data.world.workers[2].x,app.state.data.world.workers[2].y)*(rect.size.x/32)
	check(point.distance_to(app.base.size*0.5)<0.01,"find resident centers camera on actual position")
	check(app.state.save_progress(),"UI assignments save successfully")
	print("CARE_UI_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
