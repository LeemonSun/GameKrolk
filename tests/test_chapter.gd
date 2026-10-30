extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter.gd")
const A=preload("res://tests/assertions.gd")
var checks=0
var failures=0
func check(ok:bool,msg:String):
	checks+=1
	if not ok:failures+=1;push_error(msg)
func advance(w,seconds:float):
	for i in ceili(seconds*30):
		w.step(1.0/30.0)
		if w.battle.can_auto_skill():w.battle.skill()
func place(s,w,id:String)->bool:
	var choices=[];var def=s.catalog.building(id)
	for y in range(5,19):
		for x in range(9,27):
			var point=Vector2i(x,y)
			if not s.can_build(id,point).is_empty():continue
			var free=true
			for dx in int(def.width):
				for dy in int(def.height):
					if w.occupied(point+Vector2i(dx,dy)):free=false
			if not free:continue
			var score=Vector2(point).distance_to(Vector2(16,11))
			if id=="lumber":
				var near=100.0
				for source in s.data.world.sources:
					if source.kind=="wood" and source.amount>0:near=minf(near,Vector2(point).distance_to(Vector2(source.x,source.y)))
				if near>7:continue
				score+=near*2
			choices.append({"point":point,"score":score})
	choices.sort_custom(func(a,b):return a.score<b.score)
	if choices.is_empty():return false
	var count=s.data.buildings.size();s.build(id,choices[0].point);w.rebuild_navigation();w._assign_jobs()
	return s.data.buildings.size()==count+1
func _initialize():call_deferred("run")
func run():
	var reports=[]
	for seed_value in [1,11,20261029]:
		for setup in [["shields","standard"],["bows","standard"],["shields","calm"],["bows","calm"],["shields","harsh"],["bows","harsh"]]:
			var plan=setup[0];var mode=setup[1]
			var s=State.new("res://work/chapter-%d-%s-%s.json"%[seed_value,plan,mode]);s.new_game(seed_value,mode,"First frontier",true);var w=World.new(s)
			check(s._valid(s.data) and s.data.chapter.phase=="supply","guided start is valid")
			if seed_value==1 and plan=="shields":advance(w,160);check(not s.data.world.raid_active and s.data.world.raid_number==0,"no raid deadline while learning")
			s.research("forestry");s.research("agriculture")
			check(place(s,w,"lumber") and place(s,w,"farm"),"ordinary budget places required economy")
			for i in 240:
				advance(w,1)
				if s.data.chapter.phase!="supply":break
			check(s.data.chapter.phase=="prepare" and Chapter.supplied(s),"real construction, harvest and delivery complete supply")
			s.data.chapter.plan=plan
			if plan=="shields":
				check(place(s,w,"forge"),"ordinary budget funds forge")
				for i in 180:
					advance(w,1)
					if s.level("forge")>0:break
				s.recruit("guard");s.recruit("guard");s.recruit("militia");s.recruit("militia")
			else:
				check(place(s,w,"wall") and place(s,w,"wall"),"ordinary budget funds fortifications")
				for i in 4:s.recruit("archer")
			for i in 180:
				advance(w,1)
				if Chapter.ready_reason(s).is_empty():break
			check(Chapter.ready_reason(s).is_empty(),"preparation achievable without gifted funds: "+plan)
			var food=int(s.data.food);Chapter.commit(s)
			check(s.data.chapter.phase=="countdown" and s.data.food==food-6,"commit charges provision once")
			Chapter.commit(s);check(s.data.food==food-6,"duplicate commit rejected")
			w.paused=true;advance(w,2);check(s.data.chapter.left==30,"pause freezes approach")
			w.paused=false;advance(w,12)
			check(s.save_progress(),"save during approach")
			var loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(loaded.data,s.data),"exact approach reload")
			s.before_save=Callable();s=loaded;w=World.new(s);w.command_mode="advance"
			for entry in [["guard",Vector2(22.5,11.5)],["militia",Vector2(21.5,12.5)],["archer",Vector2(18.5,12.5)],["hero",Vector2(22,13.5)]]:w.order(entry[0],w._nearest_open(entry[1]*32))
			advance(w,19)
			check(s.data.chapter.phase=="battle" and s.data.world.raid_active and s.data.chapter.leader>=0,"countdown spawns persistent leader and battle")
			check(s.save_progress(),"chapter battle saves")
			loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(loaded.data,s.data),"chapter battle reloads exactly")
			s.before_save=Callable();s=loaded;w=World.new(s)
			for i in 240:
				advance(w,1)
				if s.data.chapter.phase!="battle":break
			check(s.data.chapter.phase=="won","prepared real battle is winnable: %d %s"%[seed_value,plan])
			var coins=int(s.data.coins);Chapter.finish(s,true)
			check(s.data.coins==coins,"victory reward cannot repeat")
			check(s._valid(s.data) and s.save_progress(),"completed episode remains valid")
			reports.append({"seed":seed_value,"plan":plan,"mode":mode,"phase":s.data.chapter.phase,"seconds":s.data.world.clock,"coins":s.data.coins,"survivors":s.army_count(),"food":s.data.food})
			s.before_save=Callable()
	var s=State.new("res://work/chapter-edges.json");var original=s.data.world.tiles.duplicate();var old=s.data.duplicate(true);old.version=8;old.erase("chapter")
	var migrated=s._migrate(old);check(s._valid(migrated) and migrated.chapter.phase=="off" and migrated.world.tiles==original,"old party stays sandbox without terrain reset")
	s.new_game(5,"standard","Recovery",true);s.data.chapter.phase="battle";s.data.army={"militia":3,"archer":0,"guard":0}
	Chapter.finish(s,false);check(s.data.chapter.phase=="recover" and s.army_count()==14 and s.data.chapter.relief,"first defeat gives one visible recovery package")
	var coins=int(s.data.coins);s.data.chapter.phase="battle";Chapter.finish(s,false)
	check(s.data.coins==coins,"second defeat cannot farm relief")
	s.new_game(5,"standard","Failed save",true);s.data.chapter.phase="recover";s.read_only=true;var food=int(s.data.food)
	Chapter.commit(s);check(s.data.chapter.phase=="recover" and s.data.food==food and s.data.chapter.attempts==0,"failed checkpoint cannot charge provision or start encounter")
	s.read_only=false;s.data.chapter.phase="battle";var before=s.army_count();Chapter.finish(s,false)
	check(s.army_count()==before,"relief does not add troops above promised recovery floor")
	s.new_game(17,"standard","Real defeat",true);var w=World.new(s);s.data.chapter.phase="countdown";s.data.chapter.left=0.0;w.start_raid();w.battle.keep_hp=0;w.step(1.0/30.0)
	check(s.data.chapter.phase=="recover" and not s.data.world.raid_active and s.data.chapter.relief,"real defeat enters recover and unblocks village")
	check(s.save_progress(),"real defeat checkpoint valid")
	var loaded=State.new(s.save_path);check(loaded.load_progress() and loaded.data.chapter.phase=="recover","defeat recovery persists")
	Chapter.commit(s);advance(w,31)
	check(s.data.chapter.phase=="battle" and s.data.chapter.attempts==1,"recovered settlement can start second encounter")
	for unit in w.battle.units:
		if unit.team==1:unit.hp=0
	w.step(1.0/30.0);check(s.data.chapter.phase=="won" and s._valid(s.data),"retry can complete episode through normal result pipeline")
	print("CHAPTER_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"runs":reports}));quit(1 if failures else 0)
