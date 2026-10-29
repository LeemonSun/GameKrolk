extends SceneTree

func _initialize():call_deferred("run")

func run():
	var app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-base.png")
	app._set_tab("heroes")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-heroes.png")
	app._start_battle("hero")
	app.combat.automatic_skill=true
	app._refresh()
	app.combat.battle.order("hero",Vector2(430,300))
	for i in 400:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-battle.png")
	print("UI_TEST_DONE")
	quit()
