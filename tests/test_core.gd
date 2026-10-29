extends SceneTree

const State=preload("res://scripts/state.gd")
const Battle=preload("res://scripts/battle.gd")
const World=preload("res://scripts/world.gd")
const Assertions=preload("res://tests/assertions.gd")
var checks=0
var failures=0

func check(condition:bool,message:String):
	checks+=1
	if not condition:failures+=1;push_error("FAIL: "+message)

func _initialize():call_deferred("run")

func run():
	DirAccess.make_dir_recursive_absolute("res://work")
	var path="res://work/core-test.json"
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var s=State.new(path)
	check(s._valid(s.data),"initial state validates")
	check(s.save_progress(),"first save")
	var initial=int(s.data.coins)
	var world=World.new(s)
	check(s.build("forge",Vector2i(1,1)).begins_with("Заложено"),"place forge foundation")
	check(s.level("forge")==0 and not s.hero_available("lina"),"foundation has no finished building effects")
	world.rebuild_navigation()
	for i in 1500:world.step(1.0/30.0)
	check(s.level("forge")==1 and s.data.coins==initial-80,"cost charged once")
	var before=s.data.duplicate(true)
	s.build("lab",Vector2i(1,1));check(s.data==before,"occupied tile cannot spend resources")
	s.build("forge",Vector2i(8,1));check(s.data==before,"unique forge cannot be duplicated")
	s.build("wall",Vector2i(-1,3));check(s.data==before,"outside grid cannot build")
	check(s.recruit("guard").begins_with("Нанят"),"forge unlocks guard")
	var reloaded=State.new(path);check(reloaded.load_progress(),"reload valid save")
	check(Assertions.same(reloaded.data,s.data),"save roundtrip with only binary float rounding tolerance")
	check(not Assertions.same({"value":1.0},{"value":1.000001}) and not Assertions.same({"uid":1},{"uid":1.0}),"roundtrip comparison rejects gameplay drift and changed integer identities")
	var bad=s.data.duplicate(true);bad.army.militia=-1;check(not s._valid(bad),"reject negative army")
	bad=s.data.duplicate(true);bad.buildings.append(bad.buildings[0].duplicate());check(not s._valid(bad),"reject overlapping saved buildings")
	s.data.coins=0;before=s.data.duplicate(true);s.recruit("militia");check(s.data==before,"recruit cannot overdraw")
	s.data.coins=100;s.data.officers.commander=true;s.data.auto_recruit=true;s.data.army.militia=4
	var automation=s.automate();check(automation.recruited==8 and s.data.coins==44,"commander purchases missing soldiers at normal price")
	check(s.automate().spent==0,"automation is idempotent at target")
	s.data.officers.quartermaster=true;s.data.auto_supply=true;s.data.food=10
	check(s.automate().food==2 and s.data.coins==36,"quartermaster uses actual money")
	check(s.begin_siege().is_empty(),"begin siege commits provision")
	check(s.data.food==9 and s.data.in_flight,"provision and pending flag")
	var reward=s.finish_siege(true,{"militia":1000,"archer":1000,"guard":1000})
	check(not reward.is_empty() and not s.data.in_flight,"finish siege")
	check(s.data.army.militia==12,"survivors cannot create troops")
	before=s.data.duplicate(true);check(s.finish_siege(true,{}).is_empty() and s.data==before,"cannot claim battle reward twice")
	check(s.save_progress(),"save after progression")
	var corrupt=FileAccess.open(path,FileAccess.WRITE);corrupt.store_string("broken save");corrupt.close()
	var recovered=State.new(path);check(recovered.load_progress() and not recovered.warning.is_empty(),"recover from valid backup")
	var broken_path="res://work/broken-test.json"
	var broken=FileAccess.open(broken_path,FileAccess.WRITE);broken.store_string("KEEP THIS CORRUPT FILE");broken.close()
	var protected=State.new(broken_path);protected.load_progress()
	check(protected.read_only and not protected.save_progress(),"unrecoverable save is protected")
	check(FileAccess.get_file_as_string(broken_path)=="KEEP THIS CORRUPT FILE","corrupt file not silently overwritten")
	var battle=Battle.new();battle.start({"army":{"militia":0,"archer":0,"guard":0},"enemies":20})
	check(battle.units.size()==21 and battle.alive(1)==20,"hero scenario creates combatants")
	check(battle.skill_casts==0 and not battle.skill().is_empty(),"empty traces do not cast")
	battle.order("hero",Vector2(400,300));check(battle.units[0].goal!=Vector2.INF,"order has real destination")
	for i in 5400:
		battle.step(1.0/30.0)
		if battle.hero_cooldown<=0 and not battle.traces.is_empty() and battle.time>12:battle.skill()
		if battle.finished:break
	check(battle.finished,"battle has a bounded outcome")
	check(battle.attacks_resolved>0 and battle.kills>0,"real attacks remove actual enemies")
	check(battle.skill_casts>0,"hero technique executed")
	var twin=Battle.new();var twin2=Battle.new()
	var config={"seed":321,"army":{"militia":6,"archer":3,"guard":1},"enemies":15}
	twin.start(config);twin2.start(config)
	for i in 300:twin.step(1.0/30.0);twin2.step(1.0/30.0)
	check(twin.units==twin2.units,"seeded simulation is reproducible")
	var test=Battle.new();test.start({"enemies":1,"army":{"militia":1,"archer":0,"guard":0}})
	test.units[0].pos=Vector2(300,300);test.units[1].pos=Vector2(300,300);test.units[2].pos=Vector2(315,300);test._rebuild_grid()
	test._trace(Vector2(280,300),Vector2(340,300));var enemy_hp=test.units[2].hp;var own_hp=test.units[1].hp;test.skill()
	check(test.units[2].hp<enemy_hp and test.units[1].hp==own_hp,"moon hits enemies near actual trace without friendly damage")
	print("CORE_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"hero_demo_won":battle.won,"hero_demo_kills":battle.kills,"hero_demo_seconds":battle.time}))
	quit(1 if failures>0 else 0)
