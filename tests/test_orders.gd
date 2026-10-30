extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func advance(world,seconds:float):
	for i in ceili(seconds*30):world.step(1.0/30)
func _initialize():call_deferred("run")
func run():
	var s=State.new("res://work/orders.json")
	for i in s.data.world.tiles.size():s.data.world.tiles[i]=0
	for source in s.data.world.sources:source.amount=0
	for y in 22:s.data.world.tiles[y*32+16]=1
	s.data.world.tiles[10*32+16]=0;s.data.world.raid_in=10000
	var world=World.new(s);world.command_mode="move"
	world.battle.units[0].pos=Vector2(12.5,14.5)*32;world.battle.units[0].prev=world.battle.units[0].pos
	world.order("all",Vector2(23.5,16.5)*32)
	var goals=[]
	for unit in world.battle.units:goals.append(unit.goal)
	check(goals.size()==21 and goals[1]!=goals[2],"formation keeps distinct physical endpoints inside a tile")
	advance(world,1)
	check(s.build("wall",Vector2i(16,10)).begins_with("Заложено"),"close sole passage with real construction site")
	world.rebuild_navigation()
	check(world.battle.units.all(func(u):return u.route_blocked),"all marching units recognize closed passage")
	advance(world,4)
	check(world.battle.units.all(func(u):return u.pos.x<16*32),"blocked march never crosses water or closed passage")
	check(s.save_progress(),"blocked order is saved")
	var loaded=State.new(s.save_path);loaded.load_progress();world=World.new(loaded);s=loaded
	check(world.battle.units.all(func(u):return u.route_blocked and u.goal!=Vector2.INF),"waiting destinations survive reload")
	s.demolish(s.building_at(Vector2i(16,10)))
	var atomic_state=State.new(s.save_path);atomic_state.load_progress();var atomic_world=World.new(atomic_state)
	check(atomic_world.battle.units.all(func(u):return not u.route_blocked),"first atomic save after demolition already contains reopened routes")
	world.rebuild_navigation()
	check(world.battle.units.all(func(u):return not u.route_blocked),"opening passage restores pending paths")
	var safe=true
	for tick in 1500:
		world.step(1.0/30.0)
		for unit in world.battle.units:safe=safe and world._walkable(unit.pos)
	check(safe,"entire formation stays on walkable terrain while passing narrow gap")
	var arrived=0
	for unit in world.battle.units:
		if unit.goal==Vector2.INF and unit.pos.x>20*32:arrived+=1
	check(arrived==21,"all twenty-one fighters finish a narrow-pass march without abandoned orders: "+str(arrived))
	world.order("hero",Vector2(20.5,15.5)*32);advance(world,1);world.stop("hero",true)
	var hero=world.battle.units[0];var position=hero.pos
	world.battle._add_unit("guard",1,position+Vector2(90,0),s.catalog.troop("guard"))
	world.battle.units[-1].speed=0.0;world.battle.units[-1].reach=10.0
	advance(world,2)
	check(hero.pos.distance_to(position)<0.01 and hero.command=="hold","hold position does not chase nearby enemy")
	world.command_mode="move";world.order("hero",position+Vector2(-100,0));advance(world,0.5)
	check(hero.pos.x<position.x-20,"move order permits retreat instead of chasing")
	world.stop("hero");check(hero.goal==Vector2.INF and hero.command=="guard","stop cancels movement and restores free defense")
	var duel_state=State.new("res://work/orders-duel.json");duel_state.data.army={"militia":0,"archer":0,"guard":0};var duel=World.new(duel_state)
	var duelist=duel.battle.units[0];var origin=duelist.pos
	duel.battle._add_unit("guard",1,origin+Vector2(20,0),duel_state.catalog.troop("guard"));var opponent=duel.battle.units[-1];opponent.speed=0.0;opponent.reach=10.0
	var enemy_hp=opponent.hp;duel.command_mode="move";duel.order("hero",origin-Vector2(120,0));advance(duel,0.3)
	check(opponent.hp==enemy_hp and duelist.pos.x<origin.x-15,"move ignores a reachable melee enemy during retreat")
	duelist.pos=origin;duelist.prev=origin;opponent.pos=origin+Vector2(20,0)
	duel.command_mode="advance";duel.order("hero",origin-Vector2(120,0));advance(duel,0.7)
	check(opponent.hp<enemy_hp,"advance responds to enemy in weapon range")
	for i in 60:
		duel.step(1.0/30.0)
		if duelist.attack_left>0:break
	check(duelist.attack_left>0,"interrupt fixture catches an actual attack windup")
	enemy_hp=opponent.hp;duel.stop("hero",true);advance(duel,0.1)
	check(opponent.hp==enemy_hp,"canceled windup cannot land a delayed ghost hit")
	var shield_state=State.new("res://work/orders-shield.json");shield_state.data.selected_hero="warden";var shield=World.new(shield_state)
	shield.battle.units[0].pos=Vector2(18.5,12.5)*32
	shield.battle._add_unit("guard",1,Vector2(18.8,12.5)*32,shield_state.catalog.troop("guard"))
	shield.battle.units[-1].hp=200;shield.battle.units[-1].max_hp=200
	shield.battle.skill()
	check(shield._walkable(shield.battle.units[-1].pos),"hero knockback cannot push an enemy into or through a wall")
	print("ORDER_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"formation_size":21,"arrived":arrived}))
	quit(1 if failures else 0)
