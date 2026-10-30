extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const P=preload("res://scripts/personnel.gd")
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
	var s=State.new("res://work/personnel.json");var w=World.new(s);s.data.world.raid_in=9999
	check(s._valid(s.data),"new people format validates")
	var tree=int(w.source_at(Vector2i(11,11)).id);w.gather(tree,1)
	check(s.data.world.workers[1].job=="manual" and s.data.world.workers[0].job=="idle","manual task targets selected worker instead of arbitrary free person")
	s.data.world.workers[1].carry=2;s.data.world.workers[1].carry_kind="wood"
	var unchanged=s.data.duplicate(true);w.gather(tree,1)
	check(s.data==unchanged,"selected carrying worker cannot silently discard cargo for new task")
	s.data.world.workers[1].carry=0;w.set_preference(1,"auto")
	check(s.data.world.workers[0].skills.command==3 and s.data.world.workers[2].skills.medicine==3,"people have distinct specialties")
	var initial=s.capacity();s.assign("commander",0)
	check(s.data.world.workers[0].post=="commander" and not P.ready(s.data,"commander"),"appointment reserves person before arrival")
	check(s.capacity()==initial,"command bonus requires arrival")
	advance(w,8)
	check(P.ready(s.data,"commander") and s.capacity()==initial+4,"commander reaches HQ and provides skill-based capacity")
	var before=s.data.duplicate(true);s.assign("quartermaster",0)
	check(s.data==before,"HQ requirement does not mutate appointment")
	s.data.buildings[0].level=2;s.data.buildings[0].target_level=2;w.sync_army()
	before=s.data.duplicate(true);s.assign("quartermaster",0)
	check(s.data==before,"one person cannot hold two posts")
	var carrier=s.data.world.workers[1];carrier.job="manual";carrier.source=-1;carrier.carry=2;carrier.carry_kind="wood";carrier.x=11.5;carrier.y=11.5
	s.assign("quartermaster",1);w._assign_jobs()
	check(carrier.carry==2 and carrier.returning and not P.ready(s.data,"quartermaster"),"appointment preserves cargo and defers service")
	advance(w,12)
	check(carrier.carry==0 and P.ready(s.data,"quartermaster"),"new officer delivers cargo before service")
	before=s.data.duplicate(true);w.set_preference(0,"wood")
	check(s.data==before,"production preference cannot steal an officer")
	s.assign("commander");w._assign_jobs()
	check(s.data.world.workers[0].post.is_empty() and not s.data.officers.commander,"dismissal frees exact person")
	check(s.capacity()==22+8+6,"dismissal removes capacity bonus")
	# Real combat records, with ten actual casualties and a live remaining army.
	w.start_raid();var killed={"militia":0,"archer":0}
	for u in w.battle.units:
		if u.team==0 and u.kind in killed and killed[u.kind]<(6 if u.kind=="militia" else 4):w.battle._damage(int(u.id),10000,-1);killed[u.kind]+=1
	w._end_raid(true);s.data.world.raid_in=9999
	check(s.data.personnel.wounded.militia==3 and s.data.personnel.wounded.archer==2,"combat casualties split into wounded and permanent losses")
	check(s.data.personnel.lost==5 and s.army_count()==10,"wounded do not count as active army")
	before=s.data.duplicate(true);w._end_raid(true)
	check(s.data==before,"duplicate encounter completion cannot duplicate wounded")
	check(not P.treatment_reason(s).is_empty(),"treatment requires building and medic")
	for x in range(22,24):
		for y in range(15,17):s.data.world.tiles[y*32+x]=0
	for source in s.data.world.sources:
		if source.x in [22,23] and source.y in [15,16]:source.amount=0
	s.data.food=100;s.data.coins=300
	s.build("infirmary",Vector2i(22,15));w.rebuild_navigation();w._assign_jobs();advance(w,40)
	check(s.level("infirmary")==1,"real builder completes infirmary")
	s.assign("medic",2);w._assign_jobs();advance(w,12)
	check(P.ready(s.data,"medic"),"medic walks to infirmary")
	check(s.data.world.workers[2].job=="idle" and s.data.world.workers[2].post=="medic","medic cannot perform a production job")
	var progress=float(s.data.personnel.treatment);s.data.personnel.auto_treat=false;P.tick(s,3)
	check(s.data.personnel.treatment==progress,"manual pause preserves treatment progress")
	s.data.personnel.auto_treat=true;s.data.world.raid_active=true;P.tick(s,3)
	check(s.data.personnel.treatment==progress,"raid pauses treatment")
	s.data.world.raid_active=false;var food=int(s.data.food);s.data.food=0;P.tick(s,3)
	check(s.data.personnel.treatment==progress,"no free treatment without food")
	s.data.food=food
	check(s.save_progress(),"save occupied posts and partial treatment")
	var loaded=State.new(s.save_path)
	check(loaded.load_progress() and A.same(s.data,loaded.data),"all post references, practice and treatment roundtrip")
	var restored=World.new(loaded);var count=s.army_count();var coins=int(s.data.coins)
	advance(w,22);advance(restored,22)
	check(s.data.personnel.treated>0 and s.army_count()>count,"treatment returns real fighter to army")
	check(s.data.coins<coins and s.data.personnel.treated==loaded.data.personnel.treated,"treatment costs money and resumes identically")
	check(s.data.personnel.wounded==loaded.data.personnel.wounded and s.data.army==loaded.data.army,"reload does not duplicate or lose recovered fighters")
	advance(w,140)
	check(s.data.personnel.treated==5 and s.army_count()==15,"all five wounded recover while permanent losses remain")
	var stock=int(s.data.coins);advance(w,5)
	check(s.data.coins==stock,"empty hospital does not charge")
	# A posted person must not continue working after his station disappears.
	var index=-1
	for i in s.data.buildings.size():
		if s.data.buildings[i].id=="infirmary":index=i;break
	s.data.buildings.remove_at(index);w.rebuild_navigation();advance(w,0.1)
	check(not P.ready(s.data,"medic"),"destroyed infirmary disables medic")
	var legacy=s.data.duplicate(true);legacy.version=6;legacy.erase("personnel")
	for person in legacy.world.workers:
		for key in ["post","at_post","skills","practice"]:person.erase(key)
	legacy.officers.commander=true
	var migrated=s._migrate(legacy)
	check(s._valid(migrated) and migrated.personnel.posts.commander>=0,"legacy appointment migrates to real existing person")
	var bad=s.data.duplicate(true);bad.personnel.posts.commander=9999
	check(not s._valid(bad),"dangling officer reference rejected")
	bad=s.data.duplicate(true);bad.personnel.wounded.guard=-1
	check(not s._valid(bad),"negative wounded rejected")
	bad=s.data.duplicate(true);bad.world.workers[0].skills.command=100
	check(not s._valid(bad),"out of range skill rejected")
	bad=s.data.duplicate(true);bad.personnel.treatment=INF
	check(not s._valid(bad),"infinite medical clock rejected")
	var apprentice=s.data.world.workers[0];var skill=int(apprentice.skills.build);P.practice(apprentice,"build",100)
	check(apprentice.skills.build>skill,"work experience improves actual skill")
	print("PERSONNEL_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"treated":s.data.personnel.treated,"permanent_losses":s.data.personnel.lost}))
	quit(1 if failures else 0)
