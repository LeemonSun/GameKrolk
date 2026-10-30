extends SceneTree

const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Rules=preload("res://scripts/settlement.gd")
const Assertions=preload("res://tests/assertions.gd")
var checks=0
var failures=0

func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)

func advance(world,seconds:float):
	for i in ceili(seconds*30):
		world.step(1.0/30.0)
		if world.battle.can_auto_skill():world.battle.skill()

func clear_area(s,cell:Vector2i,size:Vector2i):
	var area=Rect2i(cell,size)
	for x in range(cell.x,cell.x+size.x):
		for y in range(cell.y,cell.y+size.y):s.data.world.tiles[y*32+x]=0
	for source in s.data.world.sources:
		if area.has_point(Vector2i(source.x,source.y)):source.amount=0

func _initialize():call_deferred("run")

func run():
	var s=State.new("res://work/settlement-test.json");var world=World.new(s)
	check(s._valid(s.data),"fresh version 3 validates")
	check(s.worker_capacity()==3,"initial three beds")
	check(not world._walkable(Vector2(16.5,11.5)*32) and world._walkable(world.home()),"building footprint blocks movement and entrance stays walkable")
	var before=s.data.duplicate(true);s.hire_worker()
	check(s.data==before,"no hiring without housing")
	s.research("forestry");s.research("mining");s.research("agriculture")
	check(s.data.research.agriculture,"farming technology has a real unlock")
	var places={"lumber":Vector2i(12,11),"mine":Vector2i(19,9),"farm":Vector2i(21,10),"house":Vector2i(16,15)}
	for id in places:
		clear_area(s,places[id],Vector2i(2,2))
		check(s.can_build(id,places[id]).is_empty(),"valid footprint for "+id)
		check(s.build(id,places[id]).begins_with("Заложено"),"foundation for "+id)
		check(s.level(id)==0,"unfinished building inactive: "+id)
	world.rebuild_navigation();world._assign_jobs()
	check(s._valid(s.data),"construction sites and assignments validate")
	before=s.data.duplicate(true);s.build("wall",Vector2i(13,12))
	check(s.data==before,"entire multi-tile footprint reserves land")
	check(not s.can_build("house",Vector2i(31,21)).is_empty(),"whole footprint must stay in bounds")
	check(not s.can_build("wall",Vector2i(world.home()/32)).is_empty(),"storage entrance cannot be covered")
	advance(world,70)
	for id in places:check(s.level(id)==1,"workers finish "+id)
	check(s.data.stats.wood_delivered>=10 and s.data.stats.stone_delivered>=5,"industry physically delivers finite resources")
	check(s.data.stats.food_delivered>=5,"farm physically delivers food")
	check(s.data.achieved.size()==3,"first three development rewards unlock from work")
	var coins=int(s.data.coins);world._check_goals();world._check_goals()
	check(s.data.coins==coins,"development rewards cannot be claimed twice")
	check(s.worker_capacity()==5,"completed house expands population")
	check(s.hire_worker().begins_with("Прибыл") and s.hire_worker().begins_with("Прибыл"),"hire two actual additional people")
	before=s.data.duplicate(true);s.hire_worker()
	check(s.data==before and s.data.world.workers.size()==5,"population cap enforced without spending")
	world._check_goals();check("people" in s.data.achieved,"growth milestone is based on population")
	for worker in s.data.world.workers:world.set_preference(int(worker.id),"rest")
	advance(world,12)
	check(s.data.world.workers.all(func(worker):return worker.job=="idle" and worker.carry==0),"workers deliver cargo before resting")
	s.data.army={"militia":0,"archer":0,"guard":0};world.sync_army()
	s.data.food=2;s.data.world.food_clock=59.99;world.step(1.0/30.0)
	check(s.data.food==0,"meal consumes real food and cannot overdraw")
	world.paused=true;var food_clock=s.data.world.food_clock;advance(world,3)
	check(s.data.world.food_clock==food_clock,"pause freezes food consumption")
	world.paused=false
	s.data.wood=500;s.data.stone=500;s.data.coins=500
	clear_area(s,Vector2i(19,14),Vector2i.ONE);s.build("wall",Vector2i(19,14));world.rebuild_navigation()
	var wall=s.data.buildings[-1];var wall_uid=int(wall.uid)
	world.set_preference(0,"build")
	var builder=s.data.world.workers[0];var point=world._site_target(builder,wall)
	builder.x=point.x;builder.y=point.y;world.paths.clear();world.destinations.clear()
	advance(world,2)
	check(wall.work_done>1.0 and wall.work_done<1.4 and not wall.built,"food shortage slows actual work to sixty percent")
	s.data.food=20;advance(world,8)
	check(wall.built,"feeding restores construction rate")
	var house_index=s.building_at(places.house)
	check(s.upgrade(house_index).begins_with("Начато"),"upgrade is queued, not instantly granted")
	check(s.data.buildings[house_index].level==1 and s.worker_capacity()==5,"existing building remains active during upgrade")
	advance(world,40)
	check(s.data.buildings[house_index].level==2 and s.worker_capacity()==7,"worker finishes upgrade and capacity changes once")
	before=s.data.duplicate(true);s.demolish(house_index)
	check(s.data==before,"occupied housing cannot be demolished into homelessness")
	# This checks delivery, not overflow: leave room after the earlier rich
	# construction fixture. Full-storage behavior has its own logistics tests.
	s.data.wood=100
	var courier=s.data.world.workers[1];courier.job="manual";courier.source=-1;courier.carry=2;courier.carry_kind="wood";courier.x=world.home().x/32;courier.y=world.home().y/32
	var stock=int(s.data.wood);world.set_preference(1,"rest");world.step(1.0/30.0)
	check(s.data.wood==stock+2 and courier.job=="idle" and courier.carry==0,"reassignment preserves and delivers partial cargo exactly once")
	world.step(1.0/30.0);check(s.data.wood==stock+2,"partial cargo cannot be delivered twice")
	clear_area(s,Vector2i(20,15),Vector2i.ONE);s.build("wall",Vector2i(20,15));world.rebuild_navigation();world._assign_jobs()
	var site=s.data.buildings[-1];advance(world,1)
	check(not site.built and s.save_progress(),"save partially completed construction")
	var loaded=State.new(s.save_path)
	check(loaded.load_progress() and Assertions.same(loaded.data,s.data),"save roundtrip includes workers, meals, goals and stable identities: "+Assertions.first_difference(s.data,loaded.data))
	var restored=World.new(loaded);var saved_site=loaded.building_uid(int(site.uid))
	check(is_equal_approx(saved_site.work_done,site.work_done),"construction progress survives reload")
	advance(restored,15)
	check(saved_site.built,"loaded construction resumes to completion")
	var bad=s.data.duplicate(true);bad.buildings[-1].uid=bad.buildings[0].uid
	check(not s._valid(bad),"duplicate building identities rejected")
	bad=s.data.duplicate(true);bad.world.workers[-1].id=0
	check(not s._valid(bad),"duplicate worker identities rejected")
	bad=s.data.duplicate(true);bad.buildings[-1].width=99
	check(not s._valid(bad),"invalid saved footprint rejected")
	bad=s.data.duplicate(true);bad.world.food_clock=-1
	check(not s._valid(bad),"invalid saved meal timer rejected")
	var legacy=State.new().data;legacy.version=2
	for key in ["stats","achieved","construction_first","next_building_uid"]:legacy.erase(key)
	legacy.research.erase("agriculture");legacy.world.erase("food_clock")
	for b in legacy.buildings:
		for key in ["uid","built","target_level","work_done","hp","width","height","paid_wood","paid_stone"]:b.erase(key)
	for worker in legacy.world.workers:
		for key in ["name","preference","workplace","returning"]:worker.erase(key)
	var migrated=s._migrate(JSON.parse_string(JSON.stringify(legacy)))
	check(s._valid(migrated) and migrated.buildings[0].built and migrated.buildings[0].width==1,"real version 2 migration preserves old footprint and finished buildings")
	legacy.world.workers[0].id="broken"
	check(s._migrate(legacy)==null,"malformed legacy worker fails safely")
	var barricade=s.building_uid(wall_uid)
	check(not world._line_clear(Vector2(18.5,14.5)*32,Vector2(20.5,14.5)*32),"walls block attacks and arrows")
	barricade.hp=1;world.battle._add_unit("militia",1,Vector2(18.75,14.5)*32,s.catalog.troop("militia"));world.battle.units[-1].timer=-1
	stock=s.data.wood;world._attack_structures()
	check(s.building_uid(wall_uid).is_empty() and world._walkable(Vector2(19.5,14.5)*32),"attacker breaches structure and opens navigation")
	check(s.data.wood==stock,"enemy destruction does not grant demolition refund")
	var old_count=world.battle.units.size();world.battle.units[-1].hp=0;var hero_uid=world.battle.units[0].uid
	world._compact_army()
	check(world.battle.units.size()<old_count and world.battle.units[0].uid==hero_uid,"dead fighters compact without changing stable hero identity")
	check(s._valid(s.data),"settlement remains valid after all operations")
	print("SETTLEMENT_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"population":s.data.world.workers.size(),"goals":s.data.achieved,"minutes":s.data.world.clock/60}))
	quit(1 if failures else 0)
