extends SceneTree

const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Assertions=preload("res://tests/assertions.gd")
var checks=0
var failures=0

func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)

func _initialize():call_deferred("run")

func run():
	var s=State.new("res://work/soak.json");var world=World.new(s)
	s.research("forestry");s.research("mining");s.research("agriculture")
	for item in [["lumber",Vector2i(12,11)],["mine",Vector2i(19,9)],["farm",Vector2i(21,10)],["house",Vector2i(18,13)]]:
		check(s.build(item[0],item[1]).begins_with("Заложено"),"natural starting terrain allows "+item[0])
	world.rebuild_navigation();world._assign_jobs()
	var started=Time.get_ticks_usec();var highest_uid=world.battle.next_uid;var reloads=0
	for tick in 108000:
		world.step(1.0/30.0)
		if world.battle.can_auto_skill():world.battle.skill()
		if tick==2400:
			check(s.level("house")>0,"housing finishes before first raid")
			check(s.hire_worker().begins_with("Прибыл") and s.hire_worker().begins_with("Прибыл"),"starting economy funds growth without test grants")
			world._assign_jobs()
		if (tick+1)%1800==0:
			check(s.save_progress(),"hour soak saves a valid state every minute")
			check(world.battle.next_uid>=highest_uid,"fighter identities never reuse a previous counter")
			highest_uid=world.battle.next_uid
		if (tick+1)%9000==0:
			var loaded=State.new(s.save_path)
			check(loaded.load_progress() and Assertions.same(loaded.data,s.data),"all state fields survive periodic reload")
			s.before_save=Callable();world=World.new(loaded);s=loaded;reloads+=1
			check(world.battle.next_uid>=highest_uid,"identity counter survives reload even after dead fighters were removed")
	check(s.data.world.clock>3599.9 and s.data.world.raid_number>=10,"one hour includes repeated real raids")
	check(s.data.world.workers.size()==5,"population survives repeated raids and reloads")
	check(s._valid(s.data) and world.battle.units.size()<160,"long session stays valid and dead fighters do not accumulate indefinitely")
	print("SOAK_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"game_seconds":s.data.world.clock,"raids":s.data.world.raid_number,"wins":s.data.world.raids_defeated,"reloads":reloads,"actors_retained":world.battle.units.size(),"wall_seconds":(Time.get_ticks_usec()-started)/1000000.0}))
	quit(1 if failures else 0)
