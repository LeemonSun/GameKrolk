extends SceneTree
const State=preload("res://scripts/state.gd")
const World=preload("res://scripts/world.gd")
const C=preload("res://scripts/commerce.gd")
const P=preload("res://scripts/personnel.gd")
var failures=0
var checks=0
func check(ok:bool,msg:String):
	checks+=1
	if not ok:failures+=1;push_error(msg)
func _initialize():call_deferred("run")
func place(s,w,id:String)->bool:
	if s.data.buildings.any(func(b):return b.id==id):return true
	var price=s.catalog.building(id)
	if s.data.coins<price.coins or s.data.wood<price.wood or s.data.stone<price.stone:return false
	for y in range(7,19):
		for x in range(10,26):
			var cell=Vector2i(x,y)
			if not s.can_build(id,cell).is_empty():continue
			var free=true;var def=s.catalog.building(id)
			for dx in int(def.width):
				for dy in int(def.height):
					if w.occupied(cell+Vector2i(dx,dy)):free=false
			if not free:continue
			s.build(id,cell);w.rebuild_navigation();w._assign_jobs();return true
	return false
func manage(s,w):
	for tech in ["forestry","mining","agriculture"]:
		if not s.data.research[tech]:s.research(tech)
	for id in ["lumber","mine","farm","house","warehouse","forge"]:
		if not place(s,w,id):break
	if s.data.rules.threat=="harsh" and s.level("forge")>0:
		place(s,w,"infirmary")
		if s.level("infirmary")>0 and s.data.world.workers.size()>=5 and P.holder(s.data,"medic").is_empty():s.assign("medic",2);w._assign_jobs()
	if s.data.world.workers.size()<5:s.hire_worker()
	if s.level("hq")==1 and s.level("warehouse")>0 and s.data.coins>140:s.upgrade(0)
	for id in ["food_export","wood_export","stone_export"]:
		var offer=C.OFFERS[id]
		var keep={"wood":60,"stone":40,"food":22}[offer.take]
		if s.data[offer.take]>=int(offer.amount)+keep and C.reason(s,id).is_empty():C.send(s,id);break
	if not s.data.world.raid_active:
		var kind="guard" if s.level("forge")>0 and s.data.army.guard<5 else ("archer" if s.data.army.archer<8 else "militia")
		if s.data.coins>35 and s.army_count()<26:s.recruit(kind);w.sync_army()
	for b in s.data.buildings:
		if s.data.wood>40 and s.data.stone>20 and not w.repair_quote(int(b.uid)).is_empty():w.repair(int(b.uid))
func run():
	var reports=[]
	for seed_value in [1,5,11]:
		for mode in ["calm","standard","harsh"]:
			var s=State.new("res://work/session-%d-%s.json"%[seed_value,mode]);s.new_game(seed_value,mode,"Session");var w=World.new(s)
			for tick in 36000:
				if tick%60==0:manage(s,w)
				w.step(1.0/30.0)
				if w.battle.can_auto_skill():w.battle.skill()
				if tick>0 and tick%9000==0:
					check(s.save_progress(),"session saves")
					var loaded=State.new(s.save_path);check(loaded.load_progress(),"session loads")
					s.before_save=Callable();s=loaded;w=World.new(s)
			check(s._valid(s.data),"twenty-minute state valid")
			check(s.level("farm")>0 and s.level("house")>0 and s.data.world.workers.size()==5,"ordinary budget establishes food and population")
			check(s.data.commerce.orders>=3,"productive economy can fund itself through exports")
			check(s.level("warehouse")>0 and s.level("forge")>0 and s.level("hq")>=2,"ordinary income funds storage, military production and HQ progression")
			check(s.data.world.raid_number>=2,"session includes multiple real defenses")
			if mode=="harsh":check(s.data.personnel.treated>0,"harsh session restores actual combat casualties through assigned medic")
			reports.append({"seed":seed_value,"mode":mode,"workers":s.data.world.workers.size(),"exports":s.data.commerce.orders,"wins":s.data.world.raids_defeated,"losses":s.data.losses,"buildings":s.data.buildings.size(),"coins":s.data.coins,"treated":s.data.personnel.treated,"wounded":s.data.personnel.wounded})
			print("SESSION_RUN "+JSON.stringify(reports[-1]))
	# Transaction edge cases use their own state, not gifts in the session runs.
	var s=State.new("res://work/trade-test.json");var w=World.new(s);var coins=int(s.data.coins);var wood=int(s.data.wood)
	C.send(s,"wood_export");check(s.data.wood==wood-20 and s.data.coins==coins,"shipment reserves goods, no instant payment")
	C.send(s,"wood_export");check(s.data.wood==wood-20,"duplicate dispatch blocked")
	check(s.save_progress(),"shipment saves")
	var loaded=State.new(s.save_path);check(loaded.load_progress(),"shipment loads")
	var restored=World.new(loaded);w.paused=true;w.step(0.1)
	check(s.data.commerce.cargo.remaining==35,"pause freezes commerce")
	w.paused=false
	for i in 1051:w.step(1.0/30.0);restored.step(1.0/30.0)
	check(s.data.coins==coins+26 and loaded.data.coins==s.data.coins,"shipment pays once and survives reload")
	for i in 60:w.step(1.0/30.0)
	check(s.data.coins==coins+26,"payment cannot repeat")
	check(not C.reason(s,"wood_export").is_empty(),"limited demand prevents instant export loop")
	var bad=s.data.duplicate(true);bad.commerce.cargo={"id":"wood_export","remaining":-1}
	check(not s._valid(bad),"bad delivery time rejected")
	s.data.world.raid_active=true;var before=s.data.duplicate(true);C.send(s,"stone_export")
	check(s.data==before,"raid prevents dispatch without charging")
	s.data.commerce.cargo={"id":"stone_export","remaining":0.0};coins=int(s.data.coins);C.tick(s,0.1)
	check(s.data.coins==coins and not s.data.commerce.cargo.is_empty(),"incoming shipment waits during raid")
	s.data.world.raid_active=false;C.tick(s,0.1)
	check(s.data.coins==coins+25 and s.data.commerce.cargo.is_empty(),"incoming shipment completes after raid")
	var source=s.data.world.sources[-1];source.amount=0;s.data.world.tiles[int(source.y)*32+int(source.x)]=0;w._regrow_wood()
	check(source.amount>0,"empty forest source renews")
	source.amount=0;s.data.world.tiles[int(source.y)*32+int(source.x)]=1;w._regrow_wood()
	check(source.amount==0,"forest cannot grow in water")
	var old=s.data.duplicate(true);old.version=5;old.erase("commerce")
	check(s._valid(s._migrate(old)),"version five party gains commerce without resetting world")
	print("SESSION_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"minutes_each":20,"runs":reports}))
	quit(1 if failures else 0)
