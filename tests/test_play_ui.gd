extends SceneTree
var failures=0
func _initialize():call_deferred("run")
func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame
	app._new_party(321,"standard","Первый рубеж");app._set_tab("heroes")
	for child in app.sidebar.get_children():
		if child is Button and (child.text.contains("Астрея") or child.text.contains("Лина")):failures+=1;push_error("canonical captain offered as free recruit")
	for child in app.toolbar.get_children():
		if child is Button and child.text in ["Полигон","Проверить набег"]:failures+=1;push_error("debug controls visible in normal play")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/ui-normal-play-v7.png")
	print("PLAY_UI_TESTS "+JSON.stringify({"failures":failures,"hero":app.state.data.selected_hero,"isolated_save":app.state.save_path}))
	quit(1 if failures else 0)
