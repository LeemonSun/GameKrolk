extends SceneTree

func _initialize():call_deferred("run")

func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	var results=[]
	for amount in ["200","500","1000"]:
		if app.in_battle:app._return_base()
		app._start_battle(amount)
		# Bring the formations into contact before measuring actual rendered frames.
		for i in 240:app.combat.battle.step(1.0/30.0)
		var warm=Time.get_ticks_msec()+1500
		while Time.get_ticks_msec()<warm:await process_frame
		app.combat.frame_samples.clear()
		var samples=[];var deadline=Time.get_ticks_msec()+5000;var previous=Time.get_ticks_usec()
		while Time.get_ticks_msec()<deadline:
			await process_frame
			var now=Time.get_ticks_usec();samples.append(float(now-previous)/1000.0);previous=now
		samples.sort()
		var total=0.0
		for sample in samples:total+=sample
		var result={"initial_combatants":int(amount),"frames":samples.size(),"mean_frame_ms":total/maxi(1,samples.size()),"p95_frame_ms":samples[int(samples.size()*0.95)],
			"simulation_p95_ms":app.combat.p95(),"alive_at_end":app.combat.battle.alive(0)+app.combat.battle.alive(1),"engine_fps":Engine.get_frames_per_second(),
			"renderer":RenderingServer.get_current_rendering_method(),"viewport":"1440x900"}
		results.append(result);print("BATTLE_BENCHMARK "+JSON.stringify(result))
	var f=FileAccess.open("res://work/benchmark.json",FileAccess.WRITE);f.store_string(JSON.stringify(results,"\t"));f.close()
	quit()
