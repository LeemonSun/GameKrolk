extends SceneTree
func _initialize():call_deferred("run")
func measure(app,mode:String)->Dictionary:
	var started=Time.get_ticks_usec()
	if mode=="base":app._set_tab("build")
	else:
		app._set_tab("map");app.map_view.mode=mode;app._refresh()
	var opening=(Time.get_ticks_usec()-started)/1000.0
	var warm_until=Time.get_ticks_usec()+500000
	while Time.get_ticks_usec()<warm_until:await process_frame
	var frames=[];var previous=Time.get_ticks_usec();var until=previous+1000000
	while Time.get_ticks_usec()<until or frames.size()<180:
		await process_frame
		var now=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
	frames.sort();var total=0.0
	for value in frames:total+=value
	return {"mode":mode,"opening_ms":opening,"frame_mean_ms":total/frames.size(),"frame_p95_ms":frames[int(frames.size()*0.95)-1],"frames":frames.size(),"memory_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame
	app.state.data.world.raid_in=9999;root.size=Vector2i(1440,900)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var reports=[]
	for mode in ["base","overview","region","nearby"]:reports.append(await measure(app,mode))
	var file=FileAccess.open("res://work/atlas-ui-benchmark.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"\t"));file.close()
	print("ATLAS_UI_BENCHMARK "+JSON.stringify(reports));quit()
