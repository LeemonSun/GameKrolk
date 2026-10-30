extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const C=preload("res://scripts/commerce.gd")
var failures=0
var checks=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var s=State.new("res://work/crisis.json");var w=World.new(s)
	w.start_raid();w._end_raid(false)
	check(s.data.losses==1 and not s.data.world.raid_active,"loss counted and battle ends")
	check(w.battle.keep_hp>0 and s.data.world.workers.size()==3,"defeat preserves recoverable settlement")
	var before=s.data.duplicate(true);w._end_raid(true)
	check(s.data==before,"ended encounter cannot grant another reward")
	s.data.coins=0;s.data.food=0;s.data.wood=0;s.data.stone=0;s.data.world.raid_in=9999
	w.gather(int(w.source_at(Vector2i(11,11)).id))
	for i in 2700:w.step(1.0/30.0)
	check(s.data.wood>=20,"manual work recovers goods from zero funds and food")
	C.send(s,"wood_export")
	for i in 1051:w.step(1.0/30.0)
	check(s.data.coins>=26,"zero-money settlement can earn recovery funds")
	check(s.save_progress(),"crisis saves valid progress")
	var loaded=State.new(s.save_path)
	check(loaded.load_progress() and loaded.data.losses==1,"recovery and loss survive restart")
	print("CRISIS_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
