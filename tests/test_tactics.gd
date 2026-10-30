extends SceneTree
const Battle=preload("res://scripts/battle.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var b=Battle.new();b.start({"army":{"militia":0,"archer":1,"guard":1},"enemies":0})
	var guard={};var archer={}
	for u in b.units:
		if u.kind=="guard":guard=u
		elif u.kind=="archer":archer=u
	guard.hp=100.0;guard.max_hp=100.0;guard.pos=Vector2(400,300);guard.facing=Vector2.RIGHT
	b._damage(int(guard.id),20,int(archer.id),true,Vector2(500,300));var front=100-guard.hp
	guard.hp=100;b._damage(int(guard.id),20,int(archer.id),true,Vector2(300,300));var rear=100-guard.hp
	check(is_equal_approx(front,7) and is_equal_approx(rear,14),"directional shield halves frontal arrows while rear receives armor only")
	guard.hp=100;b._damage(int(guard.id),20,int(archer.id));check(is_equal_approx(guard.hp,86),"ordinary armor remains in melee")
	guard.hp=100;guard.facing=Vector2.UP;b._damage(int(guard.id),20,int(archer.id),true,Vector2(400,200))
	check(is_equal_approx(guard.hp,93),"shield orientation works on other axes")
	archer.pos=Vector2(200,300);guard.pos=Vector2(230,300);guard.hp=100;archer.attack_target=guard.id
	b._resolve_attack(archer);check(is_equal_approx(b.projectiles[-1].damage,archer.damage*0.55),"archer caught in melee loses shooting efficiency")
	b.projectiles.clear();guard.pos=Vector2(300,300);b._resolve_attack(archer)
	check(is_equal_approx(b.projectiles[-1].damage,archer.damage),"archer maintains full damage at range")
	for destination in [Vector2(750,300),Vector2(200,300),Vector2(500,500),Vector2(650,450)]:
		b.start({"army":{"militia":6,"archer":8,"guard":6},"enemies":0,"mode":"world","size":Vector2(1024,704)})
		var center=Vector2.ZERO
		for unit in b.units:center+=unit.pos
		center/=b.units.size();var forward=(destination-center).normalized()
		b.order("all",destination,"advance")
		var shield_depth=0.0;var bow_depth=0.0;var goals={};var valid=true
		for unit in b.units:
			if unit.kind=="guard":shield_depth+=unit.goal.dot(forward)/6
			if unit.kind=="archer":bow_depth+=unit.goal.dot(forward)/8
			valid=valid and not goals.has(unit.goal) and unit.goal.x>=35 and unit.goal.y>=35 and unit.goal.x<1024 and unit.goal.y<704
			goals[unit.goal]=true
		check(shield_depth>bow_depth,"guard front and archer rear rotate with order direction")
		check(valid,"rotated formation preserves distinct in-bounds endpoints")
	print("TACTICS_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
