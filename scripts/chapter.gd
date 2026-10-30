extends RefCounted
const PHASES=["off","supply","prepare","ready","countdown","battle","recover","won","free"]
static func initialize(d:Dictionary):
	if not d.has("chapter"):d.chapter={"phase":"off","plan":"shields","left":0.0,"attempts":0,"leader":-1,"relief":false,"wood_start":0,"food_start":0}
static func begin(d:Dictionary):
	initialize(d);d.chapter.phase="supply";d.chapter.wood_start=int(d.stats.wood_delivered);d.chapter.food_start=int(d.stats.food_delivered)
static func enabled(d:Dictionary)->bool:return d.chapter.phase!="off"
static func active(d:Dictionary)->bool:return d.chapter.phase not in ["off","won","free"]
static func enemy_count(d:Dictionary)->int:return {"calm":14,"standard":22,"harsh":28}[d.get("rules",{}).get("threat","standard")]
static func placement_reason(s,id:String,point:Vector2i)->String:
	if not active(s.data) or id!="lumber":return ""
	for source in s.data.world.sources:
		if source.kind=="wood" and source.amount>0 and Vector2(point).distance_to(Vector2(source.x,source.y))<=8:return ""
	return "Для лесопилки нужны деревья не дальше восьми клеток. Выберите место ближе к лесу."
static func supplied(s)->bool:return s.level("lumber")>0 and s.level("farm")>0 and s.data.stats.wood_delivered-s.data.chapter.wood_start>=10 and s.data.stats.food_delivered-s.data.chapter.food_start>=5
static func ready_reason(s)->String:
	if not supplied(s):return "Нужны лесопилка и ферма, доставка 10 дерева и 5 еды."
	if not s.data.regional.expedition.is_empty():return "Верните походный отряд: бойцы нужны дома."
	if s.army_count()<24:return "Доведите гарнизон до 24 бойцов."
	if s.data.chapter.plan=="shields" and (s.level("forge")==0 or s.data.army.guard<2):return "Постройте кузницу и наймите двух щитоносцев."
	if s.data.chapter.plan=="bows":
		var walls=0
		for b in s.data.buildings:
			if b.id=="wall" and b.built:walls+=1
		if walls<3 or s.data.army.archer<12:return "Нужны 12 лучников и три готовые секции стены."
	if s.data.food<10:return "Подготовьте 10 провианта: 6 уйдёт на сбор защитников."
	return ""
static func tick(s,dt:float)->String:
	var c=s.data.chapter
	if c.phase=="supply" and supplied(s):
		c.phase="prepare";s.data.coins+=40;s.data.food+=8
		return "Снабжение налажено: монеты +40, провиант +8. Выберите план обороны."
	if c.phase in ["prepare","ready"]:
		var next="ready" if ready_reason(s).is_empty() else "prepare"
		if next!=c.phase:c.phase=next;return "Готовность к обороне изменилась. Откройте «Первый рубеж»."
	if c.phase=="countdown":c.left=maxf(0,c.left-dt)
	return ""
static func commit(s)->String:
	var c=s.data.chapter
	if c.phase=="recover":
		if s.army_count()<12 or s.data.food<6:return "Для повторной обороны нужны 12 бойцов и 6 провианта."
	elif c.phase in ["prepare","ready"]:
		var reason=ready_reason(s)
		if not reason.is_empty():return reason
	else:return "Сейчас нельзя начать новое столкновение."
	if s.data.world.raid_active or not s.data.regional.expedition.is_empty():return "Завершите текущий бой и верните отряд."
	var previous=c.duplicate(true);var food=int(s.data.food)
	s.data.food-=6;c.phase="countdown";c.left=30.0;c.attempts+=1;c.leader=-1
	if not s.save_progress():s.data.chapter=previous;s.data.food=food;return "Не удалось сохранить начало обороны. Провиант не списан."
	return "Разъезд подойдёт с востока через 30 секунд. Расставьте защитников; P — пауза."
static func due(d:Dictionary)->bool:return d.chapter.phase=="countdown" and d.chapter.left<=0
static func finish(s,won:bool)->String:
	var c=s.data.chapter
	if c.phase!="battle":return ""
	c.left=0.0
	if won:
		c.phase="won";s.data.coins+=200;s.data.wood+=30;s.data.stone+=15;s.data.food+=10;s.data.xp[s.data.selected_hero]+=60
		return "ПЕРВЫЙ РУБЕЖ УДЕРЖАН. Награда главы: 200 монет, 30 дерева, 15 камня, 10 провианта и 60 опыта."
	c.phase="recover"
	if not c.relief:
		c.relief=true;s.data.coins+=120;s.data.food+=12
		var free=mini(maxi(0,s.capacity()-s.army_total()),maxi(0,14-s.army_count()));var archers=mini(4,free);s.data.army.archer+=archers;free-=archers
		s.data.army.militia+=mini(maxi(0,14-s.army_count()),free)
		return "Оборона сорвана. Однократная помощь: 120 монет, 12 провианта и пополнение до 14 бойцов. Можно восстановиться и повторить."
	return "Оборона сорвана. Хозяйство сохранено. Пополните отряд и подготовьте повторную оборону."
static func title(d:Dictionary)->String:return {"off":"Поселение","supply":"1 / 3 · Обеспечить поселение","prepare":"2 / 3 · Подготовить оборону","ready":"2 / 3 · Гарнизон готов","countdown":"3 / 3 · Разъезд на подходе","battle":"3 / 3 · Защитить Штаб","recover":"Восстановиться после поражения","won":"Первый рубеж удержан","free":"Поселение продолжается"}[d.chapter.phase]
static func hint(s)->String:
	match s.data.chapter.phase:
		"supply":return "Лесопилка и ферма · доставлено дерева %d/10, еды %d/5"%[mini(10,int(s.data.stats.wood_delivered)-int(s.data.chapter.wood_start)),mini(5,int(s.data.stats.food_delivered)-int(s.data.chapter.food_start))]
		"prepare","ready":return ready_reason(s) if not ready_reason(s).is_empty() else "Можно встретить разъезд. Начало — по вашему решению."
		"countdown":return "До нападения %d с · враг придёт справа · пехота впереди лучников"%ceili(s.data.chapter.left)
		"battle":return "Разбейте разъезд и главаря. ПКМ — приказ · 1 — все · 3 — мечники · 4 — лучники · Пробел — техника"
		"recover":return "Отремонтируйте повреждения и соберите минимум 12 бойцов. Помощь приходит один раз."
		"won":return "Награда получена. Можно продолжить строительство и разведку большого мира."
	return "Развивайте поселение и исследуйте мир."
static func valid(d:Dictionary)->bool:
	var c=d.get("chapter")
	if not c is Dictionary or c.get("phase") not in PHASES or c.get("plan") not in ["shields","bows"] or not c.get("relief") is bool:return false
	for key in ["attempts","leader","wood_start","food_start"]:
		var value=c.get(key)
		if not (value is int or value is float) or not is_finite(value) or value!=int(value) or value<(-1 if key=="leader" else 0) or value>10000000:return false
	if not (c.get("left") is int or c.get("left") is float) or not is_finite(c.left) or c.left<0 or c.left>30.01:return false
	return c.phase!="battle" or d.world.raid_active
