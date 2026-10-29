extends SceneTree

const State=preload("res://scripts/state.gd")
const Battle=preload("res://scripts/battle.gd")
const World=preload("res://scripts/world.gd")
const Assertions=preload("res://tests/assertions.gd")

func place_free(s,id:String):
	for y in 22:
		for x in 32:
			if s.can_build(id,Vector2i(x,y)).is_empty():s.build(id,Vector2i(x,y));return

func _initialize():call_deferred("run")

func run():
	var results=[]
	var failures=0
	for hero in ["astreya","lina","warden"]:
		var s=State.new("res://work/cycle-"+hero+".json")
		s.data.coins=500;place_free(s,"forge");place_free(s,"lab");s.upgrade(0)
		var world=World.new(s)
		for i in 3000:world.step(1.0/30.0)
		s.data.selected_hero=hero;s.save_progress()
		var original=s.data.army.duplicate();var error=s.begin_siege()
		if not error.is_empty():failures+=1;push_error(error)
		var b=Battle.new();b.start({"hero":hero,"army":s.data.army,"enemies":33,"forge":s.level("forge"),"keep_hp":540})
		for i in 5401:
			b.step(1.0/30.0)
			if b.can_auto_skill():b.skill()
			if b.finished:break
		var reward=s.finish_siege(b.won,b.survivors())
		var reload_state=State.new(s.save_path);reload_state.load_progress()
		var valid=b.finished and not reward.is_empty() and Assertions.same(reload_state.data,s.data) and s.data.xp[hero]>0 and not s.data.in_flight
		for id in original:
			if s.data.army[id]>original[id]:valid=false
		if not valid:
			failures+=1;push_error("cycle failed: "+hero+" "+Assertions.first_difference(s.data,reload_state.data)+" save warning "+s.warning+" load warning "+reload_state.warning)
		results.append({"hero":hero,"won":b.won,"seconds":b.time,"skills":b.skill_casts,"survivors":b.survivors(),"valid":valid})
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame
	app.state.before_save=Callable();app.state.save_path="res://work/ui-cycle.json";app.state.reset()
	app.world=World.new(app.state);app.base.world=app.world
	app._place("lab");app._base_click(Vector2i(1,1))
	for i in 1500:app.world.step(1.0/30.0)
	app._select_hero("lina");app._start_battle("siege")
	if not app.in_battle or not app.state.data.in_flight or app.state.data.selected_hero!="lina":failures+=1
	app.combat.paused=true
	for i in 5401:
		app.combat.battle.step(1.0/30.0)
		if app.combat.battle.can_auto_skill():app.combat.battle.skill()
		if app.combat.battle.finished:break
	await process_frame
	if not app.result_dialog.visible or app.state.data.in_flight:failures+=1;push_error("UI outcome not processed")
	app._return_base()
	if app.in_battle or not app.base.visible or app.combat.visible:failures+=1
	print("CYCLE_TESTS "+JSON.stringify({"failures":failures,"heroes":results,"ui_return":not app.in_battle}))
	quit(1 if failures else 0)
