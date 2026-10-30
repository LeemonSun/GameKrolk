extends SceneTree
const Battle=preload("res://scripts/battle.gd")
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var b=Battle.new();b.start({"hero":"lina","army":{"militia":1,"archer":1,"guard":0},"enemies":1})
	check(b.catalog.troop("guard").name=="Щитоносец","equipment role is not named after canonical clan rank")
	var ally=b.units[1];var corpse=b.units[2];var enemy=b.units[3]
	ally.hp=10.0;corpse.hp=0;ally.pos=b.units[0].pos+Vector2(20,0);corpse.pos=ally.pos;enemy.pos=Vector2(900,500)
	b.skill()
	check(ally.hp==10 and ally.regeneration>0,"Lina applies gradual regeneration rather than instant heal")
	check(corpse.hp==0 and enemy.poison==0,"healing seal neither revives nor poisons enemies")
	for unit in b.units:unit.command="hold";unit.target=-1
	b.step(0.1)
	check(ally.hp>10 and ally.hp<11,"seal gradually restores living body")
	var initial=float(ally.hp);ally.poison=1;b.step(0.1)
	check(ally.hp<initial,"ongoing harmful status blocks regeneration instead of being universally cured")
	var s=State.new("res://work/lore-healing.json");s.data.selected_hero="lina";var world=World.new(s)
	world.battle.units[1].hp=10;world.battle.units[1].pos=world.battle.units[0].pos+Vector2(20,0)
	world.battle.skill();check(s.save_progress(),"active healing seal saves")
	var loaded=State.new(s.save_path);check(loaded.load_progress(),"active healing seal loads")
	var restored=World.new(loaded)
	for i in 90:world.step(1.0/30.0);restored.step(1.0/30.0)
	check(is_equal_approx(world.battle.units[1].hp,restored.battle.units[1].hp) and is_equal_approx(world.battle.units[1].regeneration,restored.battle.units[1].regeneration),"healing continuation survives reload")
	var old=s.data.duplicate(true);old.version=6;old.erase("personnel")
	for unit in old.world.combat.units:unit.erase("regeneration");unit.erase("combat_tier")
	for worker in old.world.workers:
		for field in ["post","at_post","skills","practice"]:worker.erase(field)
	var migrated=s._migrate(old)
	check(s._valid(migrated),"old combat coefficients migrate without becoming organizational ranks")
	print("LORE_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
