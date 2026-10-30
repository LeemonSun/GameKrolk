extends SceneTree

const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const Snapshot=preload("res://scripts/combat_snapshot.gd")
var checks=0
var failures=0
var detail=""

func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message+" "+detail)

func matching(a,b)->bool:
	if a.battle.rng.state!=b.battle.rng.state:detail="rng";return false
	for key in ["tick","kills","skill_casts","next_uid","attacks_resolved"]:
		if a.battle.get(key)!=b.battle.get(key):detail=key;return false
	if a.battle.units.size()!=b.battle.units.size():detail="unit count";return false
	for i in a.battle.units.size():
		var first=a.battle.units[i];var second=b.battle.units[i]
		for key in ["uid","target","attack_target","command","route_blocked"]:
			if first[key]!=second[key]:detail="unit %d %s"%[i,key];return false
		if first.pos.distance_to(second.pos)>0.001 or absf(first.hp-second.hp)>1e-7 or absf(first.attack_left-second.attack_left)>1e-9:detail="unit %d position/hp/phase"%i;return false
	for key in ["coins","wood","stone","food","xp","army","achieved"]:
		if a.state.data[key]!=b.state.data[key]:detail=key;return false
	if a.state.data.world.workers!=b.state.data.world.workers:detail="workers";return false
	return true

func _initialize():call_deferred("run")

func run():
	for seed_value in range(1,65):
		var s=State.new();s.new_game(seed_value,"standard","Map fixture");var world=World.new(s)
		var playable=s._valid(s.data) and world._walkable(world.home())
		for source in s.data.world.sources.slice(-6):
			playable=playable and not world._route(world.home()/32,Vector2(source.x+0.5,source.y+0.5)).is_empty()
		for unit in world.battle.units:playable=playable and world._walkable(unit.pos)
		check(playable,"seed %d has reachable starter deposits and walkable actors"%seed_value)
		s.before_save=Callable()
	for hero in ["astreya","lina","warden"]:
		var s=State.new("res://work/resume-"+hero+".json");s.data.selected_hero=hero;var world=World.new(s)
		world.gather(int(world.source_at(Vector2i(11,11)).id));world.start_raid()
		var phase=false
		for tick in 1800:
			world.step(1.0/30.0)
			phase=world.battle.units.any(func(u):return u.attack_left>0) and not world.battle.projectiles.is_empty()
			if phase:break
		check(phase,"capture during real windup and flying arrows: "+hero)
		world.battle.buff_until=world.battle.time+3.0
		for unit in world.battle.units:
			if unit.team==1 and unit.hp>0:unit.poison=2.0;break
		if hero=="astreya":world.battle._trace(world.battle.units[0].pos,world.battle.units[0].pos+Vector2(24,0))
		check(s.save_progress(),"save full active encounter: "+hero)
		var loaded=State.new(s.save_path);check(loaded.load_progress(),"load full encounter: "+hero)
		var restored=World.new(loaded)
		check(matching(world,restored),"initial restored scene equals original: "+hero)
		var identical=true
		for tick in 900:
			world.step(1.0/30.0);restored.step(1.0/30.0)
			if tick%90==0:
				if world.battle.can_auto_skill():world.battle.skill()
				if restored.battle.can_auto_skill():restored.battle.skill()
				identical=identical and matching(world,restored)
		check(identical,"thirty seconds continue with same decisions, rng, damage and deliveries: "+hero)
		var bad=loaded.data.duplicate(true);bad.world.combat.globals.rng_state="999999999999999999999999"
		check(not loaded._valid(bad),"reject overflowing rng state")
		bad=loaded.data.duplicate(true);bad.world.combat.units[0].target=99999
		check(not loaded._valid(bad),"reject dangling attack reference")
		bad=loaded.data.duplicate(true);bad.world.combat.runtime.workers[0].path=[{"v":[100,100]}]
		check(not loaded._valid(bad),"reject worker route outside tile map")
		bad=loaded.data.duplicate(true);bad.world.combat.projectiles=[{"pos":{"v":[100,100]},"to":{"v":[120,100]},"target":99999,"source":0,"team":0,"damage":1.0,"life":1.0}]
		check(not loaded._valid(bad),"reject projectile referencing a missing fighter")
		world.paused=true;check(s.save_progress(),"save paused world")
		var paused_state=State.new(s.save_path);paused_state.load_progress();var paused_world=World.new(paused_state);var clock=paused_state.data.world.clock
		paused_world.step(0.1);check(paused_world.paused and paused_state.data.world.clock==clock,"pause survives reload")
	var old=State.new().data;old.version=3
	var legacy_state=State.new("res://work/resume-v3.json");legacy_state.data=old;var legacy_world=World.new(legacy_state);legacy_world.flush()
	var full=old.world.combat;var partial={"keep_hp":full.keep_hp,"keep_max":full.keep_max,"cooldown":full.cooldown,"raid_time":full.raid_time,"next_uid":full.next_uid,"units":[]}
	for unit in full.units:
		var row={}
		for key in ["kind","uid","team","x","y","hp","max_hp","damage","speed","reach","cooldown","rank"]:row[key]=unit[key]
		partial.units.append(row)
	old.world.combat=partial;var migrated=legacy_state._migrate(old)
	check(legacy_state._valid(migrated) and migrated.version==State.SAVE_VERSION,"version 3 partial battle migrates safely")
	legacy_state.data=migrated;legacy_state._normalize();legacy_world=World.new(legacy_state)
	check(legacy_state.save_progress() and legacy_state.data.world.combat.has("complete"),"legacy battle upgrades to full snapshot on next save")
	print("SIMULATION_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"map_seeds":64,"hero_continuations":3,"continuation_seconds_each":30}))
	quit(1 if failures else 0)
