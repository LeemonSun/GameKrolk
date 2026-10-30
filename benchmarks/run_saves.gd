extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
func _initialize():call_deferred("run")
func run():
	var s=State.new("res://work/save-benchmark.json");s.data.world.raids_defeated=20;var world=World.new(s);world.start_raid()
	for i in 300:world.step(1.0/30.0)
	var times=[];var failed=false
	for i in 12:
		var started=Time.get_ticks_usec()
		if not s.save_progress():failed=true;push_error(s.warning)
		times.append((Time.get_ticks_usec()-started)/1000.0)
	times.sort();var total=0.0
	for value in times:total+=value
	var file=FileAccess.open(s.save_path,FileAccess.READ)
	var result={"actors":world.battle.units.size(),"samples":times.size(),"mean_save_ms":total/times.size(),"p95_save_ms":times[int(times.size()*0.95)],"bytes":file.get_length(),"failed":failed}
	file.close();file=FileAccess.open("res://work/save-benchmark-result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	print("SAVE_BENCHMARK "+JSON.stringify(result));quit(1 if failed else 0)
