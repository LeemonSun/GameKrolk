extends SceneTree

func _initialize():call_deferred("run")

func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.state.before_save=Callable();app.state.reset();app.state.save_path="res://work/world-ui.json"
	app.world=load("res://scripts/world.gd").new(app.state);app.base.world=app.world
	app.world.notice.connect(app._notice);app.world.raid_finished.connect(func(_won):app._refresh())
	app.state.research("forestry");app.state.research("mining");app.state.research("agriculture")
	app.state.build("lumber",Vector2i(12,11));app.state.build("mine",Vector2i(19,9));app.state.build("farm",Vector2i(21,10))
	app.world.rebuild_navigation();app._refresh()
	for i in 150:app.world.step(1.0/30.0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-construction.png")
	for i in 1950:app.world.step(1.0/30.0)
	app._refresh()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-world.png")
	app._set_tab("orders");app._world_group("all");app._world_mode("advance")
	app.world.order("all",Vector2(25.5,11.5)*32)
	for i in 120:app.world.step(1.0/30.0)
	app._update_live()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-orders.png")
	if not app.base.show_orders:push_error("order overlay did not activate")
	app._set_tab("people")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-people.png")
	app._set_tab("goals")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-goals.png")
	app._set_tab("tech")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-tech.png")
	app._set_tab("heroes");app.world.start_raid()
	for i in 420:
		app.world.step(1.0/30.0)
		if app.world.battle.can_auto_skill():app.world.battle.skill()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-raid.png")
	root.size=Vector2i(1152,720)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-small.png")
	app._set_tab("logistics")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-logistics-small.png")
	app.state.data.world.raid_in=9999;app.state.data.coins=500;app.state.data.wood=200;app.state.data.stone=150;app.state.data.food=40
	for x in range(2,9):
		for y in range(2,9):app.state.data.world.tiles[y*32+x]=0
	for source in app.state.data.world.sources:
		if source.x<9 and source.y<9:source.amount=0
	app.state.build("warehouse",Vector2i(3,4));app.state.build("gate",Vector2i(6,5));app.world.rebuild_navigation();app.world.set_preference(0,"build")
	for i in 2100:app.world.step(1.0/30.0)
	var gate=app.state.data.buildings[-1]
	if not gate.built or app.state.level("warehouse")==0:push_error("new logistics buildings did not complete")
	gate.hp=80.0;app.world.repair(int(gate.uid));app._inspect_building(int(gate.uid))
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-repair-small.png")
	app._set_tab("trade")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-trade-small.png")
	app._set_tab("goals")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-progression-small.png")
	print("WORLD_UI_READY "+JSON.stringify({"wood":app.state.data.wood,"stone":app.state.data.stone,"raid_active":app.state.data.world.raid_active,"actors":app.world.battle.units.size()}))
	quit()
