extends SceneTree

func _initialize():call_deferred("run")

func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.state.before_save=Callable();app.state.reset();app.state.save_path="res://work/world-ui.json"
	app.world=load("res://scripts/world.gd").new(app.state);app.base.world=app.world
	app.world.notice.connect(app._notice);app.world.raid_finished.connect(func(_won):app._refresh())
	app.state.research("forestry");app.state.research("mining")
	app.state.build("lumber",Vector2i(12,11));app.state.build("mine",Vector2i(19,8))
	app.world.rebuild_navigation();app._refresh()
	for i in 900:app.world.step(1.0/30.0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-world.png")
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
	print("WORLD_UI_READY "+JSON.stringify({"wood":app.state.data.wood,"stone":app.state.data.stone,"raid_active":app.state.data.world.raid_active,"actors":app.world.battle.units.size()}))
	quit()
