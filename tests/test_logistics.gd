extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const L=preload("res://scripts/logistics.gd")
const A=preload("res://tests/assertions.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func advance(w,seconds:float):
	for i in ceili(seconds*30):w.step(1.0/30.0)
func _initialize():call_deferred("run")
func run():
	var s=State.new("res://work/logistics.json")
	for i in s.data.world.tiles.size():s.data.world.tiles[i]=0
	for source in s.data.world.sources:source.amount=0
	s.data.world.raid_in=9999;s.data.coins=2000;s.data.wood=200;s.data.stone=150;s.data.food=40
	var w=World.new(s)
	check(L.capacity(s.data,"wood")==240,"base storage")
	s.build("warehouse",Vector2i(4,4));var depot=s.data.buildings[-1];var depot_uid=int(depot.uid);w.rebuild_navigation();w._assign_jobs()
	check(not depot.built and L.capacity(s.data,"wood")==240,"foundation gives no capacity")
	advance(w,40)
	check(depot.built and L.capacity(s.data,"wood")==420,"worker finishes functional warehouse")
	check(L.capacity(s.data,"stone")==300 and L.capacity(s.data,"food")==100,"all capacities added")
	for worker in s.data.world.workers:w.set_preference(int(worker.id),"rest")
	var courier=s.data.world.workers[1];courier.x=5.5;courier.y=7.5;courier.carry=5;courier.carry_kind="wood";courier.returning=true
	var point=w._delivery_target(courier)
	check(courier.depot==depot_uid and point!=w.home()/32,"nearest reachable depot selected")
	var stock=int(s.data.wood);w._work(courier,0.01)
	check(s.data.wood==stock,"cargo not credited before arrival")
	advance(w,4)
	check(s.data.wood==stock+5 and courier.carry==0,"cargo physically delivered once")
	s.data.wood=L.capacity(s.data,"wood")-2;courier.carry=5;courier.returning=true;courier.depot=0
	point=w._delivery_target(courier);courier.x=point.x;courier.y=point.y;w._work(courier,0.1)
	check(courier.carry==3 and L.room(s.data,"wood")==0,"partial unloading preserves remainder")
	stock=int(s.data.wood);w._work(courier,1)
	check(courier.carry==3 and s.data.wood==stock,"full stock waits without duplication")
	check(s.save_progress(),"save stalled delivery")
	var loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(s.data,loaded.data),"full logistics roundtrip")
	var restored=World.new(loaded);check(loaded.data.world.workers[1].carry==3,"reload keeps undelivered cargo")
	s.data.wood-=10;w._work(courier,0.1)
	check(courier.carry==0 and s.data.wood==stock-7,"spending resumes unloading")
	stock=int(s.data.wood);s.demolish(s.building_at(Vector2i(4,4)));w.rebuild_navigation()
	check(L.capacity(s.data,"wood")==240 and s.data.wood>=stock,"demolition preserves existing overflow")
	courier.carry=5;courier.returning=true;courier.depot=depot_uid;s.data.wood=20
	check(w._delivery_target(courier)==w.home()/32 and courier.depot!=depot_uid,"destroyed depot falls back to HQ")
	for y in 22:s.data.world.tiles[y*32+8]=1
	s.data.world.tiles[5*32+8]=0
	s.data.wood=100
	s.build("gate",Vector2i(8,5));var gate=s.data.buildings[-1];var uid=int(gate.uid);w.rebuild_navigation();w.set_preference(0,"build")
	advance(w,25)
	check(gate.id=="gate" and gate.built,"worker builds closed gate")
	check(not w._walkable(Vector2(8.5,5.5)*32),"closed gate blocks movement")
	check(not w._line_clear(Vector2(7.5,5.5)*32,Vector2(9.5,5.5)*32),"closed gate blocks attacks")
	courier.x=7.5;courier.y=5.5;courier.depot=0;courier.carry=5;courier.returning=true
	w._work(courier,0.1)
	check(courier.carry==5 and w._delivery_target(courier)==Vector2.INF,"isolated cargo waits without loss")
	w.toggle_gate(uid)
	check(gate.gate_open and w._walkable(Vector2(8.5,5.5)*32),"open gate changes navigation")
	check(w._delivery_target(courier)!=Vector2.INF,"opening resumes access to storage")
	courier.x=8.5;courier.y=5.5;w.toggle_gate(uid)
	check(gate.gate_open,"cannot close gate on worker")
	courier.x=7.5;var unit=w.battle.units[0];var old_pos=unit.pos;unit.pos=Vector2(8.5,5.5)*32;w.toggle_gate(uid)
	check(gate.gate_open,"cannot close gate on soldier")
	unit.pos=old_pos;w.toggle_gate(uid)
	check(not gate.gate_open,"empty gate can close")
	s.data.wood=100;s.data.stone=100;gate.hp=60.0
	var quote=w.repair_quote(uid);var old_hp=float(gate.hp);stock=int(s.data.wood);w.repair(uid)
	check(gate.hp==old_hp and not gate.repair.is_empty(),"repair queued, not instant")
	check(s.data.wood==stock-int(quote.wood),"repair materials charged once")
	stock=int(s.data.wood);w.repair(uid)
	check(s.data.wood==stock,"duplicate repair cannot charge")
	check(not s.upgrade(s.building_at(Vector2i(8,5))).begins_with("Начато"),"upgrade cannot overlap repair")
	var builder=s.data.world.workers[0];point=w._site_target(builder,gate);builder.x=point.x;builder.y=point.y;w.paths.clear();w.destinations.clear()
	advance(w,3)
	check(gate.hp>old_hp and gate.hp<180,"builder repairs progressively")
	check(s.save_progress(),"save in-progress repair")
	loaded=State.new(s.save_path);check(loaded.load_progress() and A.same(s.data,loaded.data),"repair and navigation snapshot roundtrip")
	restored=World.new(loaded);advance(w,15);advance(restored,15)
	check(gate.repair.is_empty() and is_equal_approx(gate.hp,180),"repair completes to max")
	stock=int(s.data.wood);gate.hp=180.0-1e-12;w.repair(uid)
	check(s.data.wood==stock and gate.repair.is_empty(),"floating point dust cannot charge another repair")
	check(is_equal_approx(loaded.building_uid(uid).hp,gate.hp),"loaded repair reaches same result")
	gate.hp=90.0;quote=w.repair_quote(uid);stock=int(s.data.wood);w.repair(uid);w.cancel_repair(uid)
	check(s.data.wood==stock and gate.hp==90,"unstarted repair cancellation refunds exactly")
	w.repair(uid);advance(w,1);var hp=float(gate.hp);stock=int(s.data.wood);w.cancel_repair(uid)
	check(gate.hp==hp and s.data.wood>=stock and gate.repair.is_empty(),"partial cancel retains work and refunds unused portion")
	w.toggle_gate(uid);s.data.food=40
	var hq=s.data.buildings[0];w.battle.keep_hp=100;w.repair(int(hq.uid));advance(w,40)
	check(is_equal_approx(w.battle.keep_hp,w.battle.keep_max),"HQ uses same labor repair system")
	var old=s.data.duplicate(true);old.version=4
	for b in old.buildings:b.erase("repair");b.erase("gate_open")
	for worker in old.world.workers:worker.erase("depot")
	var migrated=s._migrate(old)
	check(s._valid(migrated) and migrated.version==State.SAVE_VERSION,"format 4 migration adds logistics without resetting progress")
	var bad=s.data.duplicate(true);bad.buildings[0].gate_open=true
	check(not s._valid(bad),"non-gate open flag rejected")
	bad=s.data.duplicate(true);bad.buildings[0].repair={"wood":1,"stone":0,"remaining":10.0,"total":5.0,"rate":1.0}
	check(not s._valid(bad),"invalid repair remainder rejected")
	bad=s.data.duplicate(true);bad.world.workers[0].depot=-1
	check(not s._valid(bad),"invalid depot rejected")
	print("LOGISTICS_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
