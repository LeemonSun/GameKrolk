extends SceneTree
const Battle=preload("res://scripts/battle.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var b=Battle.new();b.start({"army":{"militia":499,"archer":0,"guard":0},"enemies":500,"seed":78})
	# Overlaps, cell edges, empty cells, both teams and dead records.
	var rng=RandomNumberGenerator.new();rng.seed=71
	for u in b.units:
		u.pos=Vector2(rng.randf_range(0,200),rng.randf_range(0,200))
		if int(u.id)%17==0:u.hp=0
	b.units[2].pos=Vector2(18,18);b.units[3].pos=Vector2(18,18);b._rebuild_grid()
	for u in b.units:
		var reference=Vector2.ZERO
		for other in b.units:
			if other.id==u.id or other.team!=u.team or other.hp<=0:continue
			var diff:Vector2=u.pos-other.pos;var distance=diff.length_squared()
			if distance>0.01 and distance<=196:reference+=diff.normalized()*(1.0-sqrt(distance)/14.0)
		check(b._separation(u).distance_to(reference)<0.00001,"fine spatial grid matches brute-force local force")
	print("SPATIAL_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"actors":b.units.size()}))
	quit(1 if failures else 0)
