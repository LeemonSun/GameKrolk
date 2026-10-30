extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const A=preload("res://tests/assertions.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var reports=[]
	for seed_value in [7,31,20261029]:
		var s=State.new("res://work/travel-%d.json"%seed_value);s.new_game(seed_value,"calm","Travel stress")
		# This fixture isolates travel durability, not ordinary-budget balancing.
		s.data.food=500;s.data.world.raid_in=9999
		var w=World.new(s);w.regional.ensure();var rng=RandomNumberGenerator.new();rng.seed=seed_value
		var home_tiles=s.data.world.tiles.duplicate();var army=s.army_count();var reloads=0;var delivered=0
		for mission in 15:
			var target=w.regional.home()
			for attempt in 200:
				var candidate=w.regional.home()+Vector2i(rng.randi_range(-8,8),rng.randi_range(-8,8))
				if candidate==w.regional.home() or not w.regional.atlas.land(candidate):continue
				var path=w.regional.route(candidate)
				if path.size()<2 or path.size()>24:continue
				if w.regional.remaining(candidate,"wood")+w.regional.remaining(candidate,"stone")>=25:target=candidate;break
			check(target!=w.regional.home(),"travel target exists")
			if target==w.regional.home():continue
			var resource="wood" if w.regional.remaining(target,"wood")>=25 else "stone"
			for operation in ["survey",resource]:
				var stock=int(s.data[resource]);var remaining=w.regional.remaining(target,resource)
				w.regional.send(target,operation);var reloaded=false;var phase=["outbound","gather","return"][mission%3]
				var ticks=0
				while not s.data.regional.expedition.is_empty() and ticks<18000:
					w.step(1.0/30.0);ticks+=1
					if not reloaded and s.data.regional.expedition.get("phase")==phase:
						check(s.save_progress(),"save during "+phase)
						var loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(loaded.data,s.data),"exact continuation during "+phase)
						s.before_save=Callable();s=loaded;w=World.new(s);w.regional.ensure();reloaded=true;reloads+=1
				check(ticks<18000 and s.army_count()==army and s.army_away()==0,"each trip terminates with exact crew accounting")
				check(w.regional.chunks.cache.size()<=9,"travel does not grow resident chunk cache")
				if operation!="survey":
					check(s.data[resource]==stock+25 and w.regional.remaining(target,resource)==remaining-25,"reload cannot duplicate delivery or refill resource");delivered+=25
		check(s.data.world.tiles==home_tiles and s._valid(s.data),"long exploration preserves local terrain and valid party")
		reports.append({"seed":seed_value,"trips":s.data.regional.completed,"known":s.data.regional.known.size(),"reloads":reloads,"delivered":delivered,"game_seconds":s.data.world.clock,"retained_chunks":w.regional.chunks.cache.size(),"save_bytes":FileAccess.get_file_as_bytes(s.save_path).size()})
		s.before_save=Callable()
	print("REGIONAL_TRAVEL_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"reports":reports}));quit(1 if failures else 0)
