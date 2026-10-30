extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Regional=preload("res://scripts/regional_world.gd")
const A=preload("res://tests/assertions.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func advance(w,seconds:float):
	for i in ceili(seconds*30):w.step(1.0/30.0)
func _initialize():call_deferred("run")
func run():
	var s=State.new("res://work/regional-test.json");var w=World.new(s);s.data.world.raid_in=9999
	check(s._valid(s.data) and s.save_progress(),"unvisited atlas saves without generation")
	var home_before=s.data.world.duplicate(true);var buildings=s.data.buildings.duplicate(true)
	check(not w.regional.ready,"base simulation does not generate whole atlas eagerly")
	var model=w.regional;model.ensure()
	check(s.data.world==home_before and s.data.buildings==buildings,"opening world preserves all local terrain, workers, sources and buildings")
	check(model.region(model.home()).tiles==s.data.world.tiles,"home preview uses actual saved land, not a replacement seed")
	var destination=Vector2i(-1,-1)
	for d in model.atlas.DIRS:
		var point=model.home()+d
		if model.atlas.land(point) and model.route(point).size()>=2 and model.remaining(point,"wood")+model.remaining(point,"stone")>=25:destination=point;break
	check(destination.x>=0,"reachable neighboring resource region exists")
	if destination.x<0:quit(1);return
	var resource="wood" if model.remaining(destination,"wood")>=25 else "stone"
	var army=int(s.data.army.militia);var food=int(s.data.food)
	model.send(destination,resource)
	check(s.data.army.militia==army,"unexplored region cannot yield resources or spend crew")
	check(model.send(destination,"survey").begins_with("Отряд отправлен"),"scout can depart")
	check(s.data.army.militia==army-2 and s.data.food==food-3,"departure removes real crew and food")
	var saved=s.data.duplicate(true);model.send(destination,"survey")
	check(s.data==saved,"cannot duplicate active expedition")
	w.paused=true;advance(w,3)
	check(s.data.regional.expedition.elapsed==0,"pause freezes expedition")
	w.paused=false;advance(w,1)
	check(s.save_progress(),"save expedition mid-leg")
	var loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(loaded.data,s.data),"mid-expedition state roundtrips exactly")
	var restored=World.new(loaded)
	advance(w,30);advance(restored,30)
	check(s.data.regional.expedition.is_empty() and s.data.army.militia==army,"crew returns exactly once")
	check(model.known(destination) and loaded.data.regional.known==s.data.regional.known,"exploration and return survive reload")
	check(loaded.data.army==s.data.army and loaded.data.regional.completed==s.data.regional.completed,"parallel original and reloaded expedition give same result")
	var available=model.remaining(destination,resource);var stock=int(s.data[resource])
	model.send(destination,resource);advance(w,3)
	check(s.data[resource]==stock,"outside cargo is not credited on departure or arrival")
	advance(w,30)
	check(s.data[resource]==stock+25 and model.remaining(destination,resource)==available-25,"finite source decreases by exactly delivered cargo")
	check(s.save_progress(),"save harvested region")
	loaded=State.new(s.save_path);loaded.load_progress();restored=World.new(loaded)
	check(restored.regional.remaining(destination,resource)==available-25,"depletion persists without saving all generated tiles")
	for i in 20:model.region(Vector2i(5+i,12))
	check(model.chunks.cache.size()<=9 and model.remaining(destination,resource)==available-25,"cache eviction cannot replenish extracted resource")
	model.send(destination,resource);advance(w,1);model.recall();advance(w,10)
	check(s.data.regional.expedition.is_empty() and s.data.army.militia==army,"recall returns crew without duplication")
	check(s.data[resource]==stock+25,"recall before work does not create cargo")
	model.send(destination,resource);advance(w,14.4)
	s.data.world.raid_active=true;var before_army=int(s.data.army.militia)
	for i in 3000:model.tick(1.0/30.0)
	check(s.data.army.militia==before_army and s.data.regional.expedition.get("phase")=="waiting","returning crew waits outside active raid")
	check(Regional.valid(s.data),"waiting a long raid does not invalidate autosave timer")
	s.data.world.raid_active=false;model.tick(0.1);w.sync_army()
	check(s.data.army.militia==army,"waiting crew rejoins when raid ends")
	var old=s.data.duplicate(true);old.version=7;old.erase("regional");var original_land=old.world.tiles.duplicate();var migrated=s._migrate(old)
	check(s._valid(migrated) and migrated.world.tiles==original_land and Regional.empty_home(migrated.regional.home),"format seven migration preserves base and lazily adds world")
	var bad=s.data.duplicate(true);bad.regional.known.append("999:0")
	check(not s._valid(bad),"outside exploration coordinate rejected")
	bad=s.data.duplicate(true);bad.regional.changes[Regional.key(destination)]={"0":-1}
	check(not s._valid(bad),"negative external source rejected")
	bad=s.data.duplicate(true);bad.regional.expedition=null
	check(not s._valid(bad),"malformed expedition rejected safely")
	# Away soldiers still occupy their roster slots, including medical admission.
	var capacity=s.capacity();s.data.army={"militia":capacity,"archer":0,"guard":0};s.data.coins=1000;w.sync_army()
	model.send(destination,"survey");var coins=int(s.data.coins);s.recruit("militia")
	check(s.army_total()==capacity and s.data.army.militia==capacity-2 and s.data.coins==coins,"cannot recruit into reserved expedition slots")
	model.recall();advance(w,0.1)
	check(s.army_count()==capacity and s.army_away()==0,"full roster returns without exceeding capacity")
	print("REGIONAL_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"home":s.data.regional.home,"destination":[destination.x,destination.y],"cached":model.chunks.cache.size()}))
	quit(1 if failures else 0)
