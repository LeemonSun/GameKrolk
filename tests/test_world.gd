extends SceneTree

const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const WorldData=preload("res://scripts/world_data.gd")
var checks=0
var failures=0

func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)

func _initialize():call_deferred("run")

func run():
	DirAccess.make_dir_recursive_absolute("res://work")
	var s=State.new("res://work/world-test.json")
	check(WorldData.valid(s.data.world),"generated world validates")
	check(WorldData.generate(20261029).tiles==s.data.world.tiles and WorldData.generate(20261029).sources==s.data.world.sources,"seed is reproducible")
	check(WorldData.generate(123).tiles!=s.data.world.tiles,"different seed changes terrain")
	var w=World.new(s)
	check(w.battle.mode=="world" and not w.battle.finished,"continuous simulation mode")
	var source=w.source_at(Vector2i(11,11));var amount=int(source.amount);var initial=int(s.data.wood)
	check(not source.is_empty(),"accessible initial forest")
	check(w.gather(int(source.id)).contains("будет добывать"),"manual harvest assigned")
	for i in 40:w.step(1.0/30.0)
	check(s.data.wood==initial,"resources are not granted before delivery")
	for i in 1100:w.step(1.0/30.0)
	check(s.data.wood>initial and source.amount<amount,"worker harvests and delivers finite resource")
	check(s.research("forestry").begins_with("Изучено"),"research unlocks production")
	check(s.build("lumber",Vector2i(12,11)).begins_with("Заложено"),"production placed in same world")
	w.rebuild_navigation()
	var wood_before=int(s.data.wood)
	for i in 1500:w.step(1.0/30.0)
	check(s.data.wood>wood_before,"sawmill performs continuing physical production")
	w.paused=true;var clock=float(s.data.world.clock)
	for i in 30:w.step(0.1)
	check(s.data.world.clock==clock,"pause freezes world and production")
	w.paused=false
	check(not w._walkable(Vector2(-20,0)),"outside region is impassable")
	var state_before=s.data.duplicate(true)
	var water=Vector2i(-1,-1)
	for y in WorldData.HEIGHT:
		for x in WorldData.WIDTH:
			if s.data.world.tiles[y*WorldData.WIDTH+x]==1:water=Vector2i(x,y);break
		if water.x>=0:break
	if water.x>=0:
		s.build("wall",water);check(s.data==state_before,"cannot build on water")
	w.start_raid();check(s.data.world.raid_active and w.battle.alive(1)>0,"raid enters persistent region")
	var original_units=w.battle.units.size()
	for i in 90:w.step(1.0/30.0)
	check(w.battle.units[-1].pos.x<970,"raiders physically approach settlement")
	w.flush()
	if not s._valid(s.data):
		print("WORLD_INVALID "+JSON.stringify({"world_valid":WorldData.valid(s.data.world),"state_warning":s.warning,"combat":s.data.world.combat,"workers":s.data.world.workers}))
	check(s.save_progress(),"save continuous world with combat snapshot")
	var loaded=State.new(s.save_path);check(loaded.load_progress(),"load saved continuous world")
	var restored=World.new(loaded)
	check(loaded.data.world.raid_active and restored.battle.units.size()==original_units,"active raid and fighters survive reload")
	check(restored.battle.units[-1].pos.distance_to(w.battle.units[-1].pos)<0.01,"fighter position survives reload")
	check(loaded.data.world.workers==s.data.world.workers,"worker progress survives reload")
	for i in 5000:
		w.step(1.0/30.0)
		if w.battle.can_auto_skill():w.battle.skill()
		if not s.data.world.raid_active:break
	check(not s.data.world.raid_active and s.data.world.raids_defeated==1,"raid is repelled without changing scene")
	check(not w.battle.finished,"world continues after raid")
	var bad=s.data.duplicate(true);bad.world.combat.units[0].x="bad"
	check(not s._valid(bad),"reject malformed saved combat")
	var old=s.data.duplicate(true);old.version=1;old.erase("world");old.erase("research");old.erase("stone");old["materials"]=old.wood;old.erase("wood")
	for b in old.buildings:b.x-=12;b.y-=9
	old.buildings=old.buildings.filter(func(b):return b.id!="lumber")
	var migrated=s._migrate(old);check(s._valid(migrated) and migrated.wood==s.data.wood,"version 1 migration preserves resources and buildings")
	print("WORLD_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"world_seconds":s.data.world.clock,"wood":s.data.wood,"raid_kills":w.battle.kills}))
	quit(1 if failures else 0)
