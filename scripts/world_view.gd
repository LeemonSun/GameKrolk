extends Control

signal cell_clicked(cell:Vector2i)
signal order_requested(group:String,pos:Vector2)
const Art=preload("res://scripts/art.gd")
const WorldData=preload("res://scripts/world_data.gd")
const Settlement=preload("res://scripts/settlement.gd")
var state
var world
var selected=-1
var selected_source=-1
var placement=""
var hover=Vector2i(-1,-1)
var clock=0.0
var zoom=1.0
var pan=Vector2.ZERO
var command_group="hero"

func _ready():
	mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func _process(dt):clock+=dt;queue_redraw()

func grid_rect()->Rect2:
	var cell=minf(size.x/(WorldData.WIDTH+1),size.y/(WorldData.HEIGHT+1))*zoom
	return Rect2((size-Vector2(WorldData.WIDTH,WorldData.HEIGHT)*cell)*0.5+pan,Vector2(WorldData.WIDTH,WorldData.HEIGHT)*cell)

func _gui_input(event):
	var rect=grid_rect();var cell=rect.size.x/WorldData.WIDTH
	if event is InputEventMouseMotion:
		if event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:pan+=event.relative
		hover=Vector2i(floori((event.position.x-rect.position.x)/cell),floori((event.position.y-rect.position.y)/cell))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before=(event.position-rect.position)/cell
			zoom=clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12),0.8,3.0)
			var after=grid_rect();var new_cell=after.size.x/WorldData.WIDTH
			pan+=event.position-(after.position+before*new_cell)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var pos=Vector2i(floori((event.position.x-rect.position.x)/cell),floori((event.position.y-rect.position.y)/cell))
			if pos.x>=0 and pos.x<WorldData.WIDTH and pos.y>=0 and pos.y<WorldData.HEIGHT:cell_clicked.emit(pos)
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			order_requested.emit(command_group,(event.position-rect.position)/(cell/WorldData.TILE))

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("1d302b"))
	if state==null:return
	var rect=grid_rect();var cell=rect.size.x/WorldData.WIDTH;var factor=cell/WorldData.TILE
	for y in WorldData.HEIGHT:
		for x in WorldData.WIDTH:
			var p=rect.position+Vector2(x,y)*cell
			var water=state.data.world.tiles[y*WorldData.WIDTH+x]==1
			var shade=float((x*17+y*23)%7)*0.006
			var col=Color(0.17+shade,0.26+shade,0.18+shade)
			if water:col=Color(0.14+shade,0.25+shade,0.28+shade)
			elif y in [10,11,12] and x>=15:col=Color("60634a")
			draw_rect(Rect2(p,Vector2.ONE*(cell+0.4)),col)
			if water:
				draw_line(p+Vector2(cell*0.2,cell*0.55),p+Vector2(cell*0.65,cell*0.55),col.lightened(0.08),1)
			elif (x+y)%3==0:draw_line(p+Vector2(cell*0.3,cell*0.7),p+Vector2(cell*0.4,cell*0.5),col.lightened(0.10),1)
			if not placement.is_empty():draw_rect(Rect2(p,Vector2.ONE*cell),Color(0.7,0.8,0.6,0.12),false,1)
	for source in state.data.world.sources:
		var p=rect.position+(Vector2(source.x,source.y)+Vector2.ONE*0.5)*cell
		if source.amount<=0:
			if source.kind=="wood":draw_rect(Rect2(p+Vector2(-3,-1)*factor,Vector2(6,4)*factor),Color("6e6145"))
			continue
		if source.kind=="wood":
			draw_rect(Rect2(p+Vector2(-2,0)*factor,Vector2(5,11)*factor),Color("665b41"))
			draw_colored_polygon(PackedVector2Array([p+Vector2(-14,4)*factor,p+Vector2(0,-25)*factor,p+Vector2(14,4)*factor]),Color("3d6245"))
			draw_colored_polygon(PackedVector2Array([p+Vector2(-11,-5)*factor,p+Vector2(0,-32)*factor,p+Vector2(11,-5)*factor]),Color("52734a"))
		else:
			draw_colored_polygon(PackedVector2Array([p+Vector2(-13,7)*factor,p+Vector2(-10,-5)*factor,p+Vector2(2,-12)*factor,p+Vector2(13,-1)*factor,p+Vector2(10,8)*factor]),Color("82938a"))
			draw_line(p+Vector2(-7,-4)*factor,p+Vector2(2,-10)*factor,Color("a4b0a0"),2*factor)
		if int(source.id)==selected_source:draw_rect(Rect2(rect.position+Vector2(source.x,source.y)*cell,Vector2.ONE*cell),Color("e0bf7e"),false,2)
	for i in state.data.buildings.size():
		var b=state.data.buildings[i]
		var area=Rect2(rect.position+Vector2(b.x,b.y)*cell,Vector2(b.width,b.height)*cell)
		var center=area.get_center()
		if b.built:Art.building(self,center,b.id,int(b.level),false,minf(area.size.x,area.size.y)/70.0)
		else:
			draw_rect(area.grow(-2),Color("514c37"));draw_rect(area.grow(-2),Color("bd9d65"),false,2)
			draw_line(area.position+Vector2(4,4),area.end-Vector2(4,4),Color("9c8255"),3*factor)
			draw_line(area.position+Vector2(area.size.x-4,4),area.position+Vector2(4,area.size.y-4),Color("9c8255"),3*factor)
		if i==selected:draw_rect(area.grow(-1),Color("e0bf7e"),false,2)
		if world!=null and world.needs_work(b):
			draw_rect(Rect2(area.position+Vector2(2,area.size.y-6),Vector2(area.size.x-4,4)),Color("28342b"))
			draw_rect(Rect2(area.position+Vector2(2,area.size.y-6),Vector2((area.size.x-4)*b.work_done/world.required_work(b),4)),Color("d0bd84"))
		elif b.hp<state.catalog.building(b.id).hp*b.level:
			var ratio=float(b.hp)/(state.catalog.building(b.id).hp*b.level)
			draw_rect(Rect2(area.position+Vector2(2,area.size.y-6),Vector2((area.size.x-4)*ratio,4)),Color("cb8d70"))
	for w in state.data.world.workers:
		var p=rect.position+Vector2(w.x,w.y)*cell
		Art.person(self,p,"militia",0,clock*8 if w.job!="idle" else 0,Vector2.RIGHT,0,0,Color.WHITE,false,factor*0.85)
		if w.carry>0:draw_rect(Rect2(p+Vector2(4,-13)*factor,Vector2(6,7)*factor),Color("bd9c63") if w.carry_kind=="wood" else (Color("a7c57b") if w.carry_kind=="food" else Color("acb9ad")))
	if world!=null:
		for trace in world.battle.traces:draw_line(rect.position+trace.a*factor,rect.position+trace.b*factor,Color(0.96,0.6,0.64,0.25),maxf(1,factor*2))
		var ordered=world.battle.units.duplicate();ordered.sort_custom(func(a,b):return a.pos.y<b.pos.y)
		var hero_color=Color(state.catalog.hero(state.data.selected_hero).color)
		for u in ordered:
			if u.hp<=0 and world.battle.time-u.died>10:continue
			var p=rect.position+u.pos*factor
			if u.kind=="hero" and u.hp>0:draw_arc(p+Vector2(0,3)*factor,21*factor,0,TAU,24,Color("dbc387"),maxf(1,factor*2))
			var attack=1.0-u.attack_left/u.windup if u.attack_left>0 and u.windup>0 else 0.0
			Art.person(self,p,u.kind,int(u.team),world.battle.time*10+u.id if u.moving else 0,u.facing,attack,float(u.flash),hero_color,u.hp<=0,factor)
			if u.hp>0 and u.hp<u.max_hp:
				draw_rect(Rect2(p+Vector2(-9,-28)*factor,Vector2(18,3)*factor),Color("25332d"))
				draw_rect(Rect2(p+Vector2(-9,-28)*factor,Vector2(18*u.hp/u.max_hp,3)*factor),Color("accf8d") if u.team==0 else Color("d9957d"))
		for p in world.battle.projectiles:
			var dir=(p.to-p.pos).normalized();draw_line(rect.position+(p.pos-dir*9)*factor,rect.position+p.pos*factor,Color("ead6a8"),maxf(1,factor*2))
		for effect in world.battle.effects:
			var age=effect.age/effect.life;var color:Color=effect.color;color.a=1-age
			if effect.type=="moon":draw_line(rect.position+effect.a*factor,rect.position+effect.b*factor,color,(1+5*(1-age))*factor)
			else:draw_arc(rect.position+effect.pos*factor,effect.radius*factor*(age if effect.type=="pulse" else 1),0,TAU,32,color,maxf(1,factor*2))
		var hp=world.battle.keep_hp/world.battle.keep_max
		var h=rect.position+world.home()*factor
		draw_rect(Rect2(h+Vector2(-18,-35)*factor,Vector2(36,4)*factor),Color("24342b"))
		draw_rect(Rect2(h+Vector2(-18,-35)*factor,Vector2(36*hp,4)*factor),Color("c8b77b"))
	if hover.x>=0 and hover.x<WorldData.WIDTH and hover.y>=0 and hover.y<WorldData.HEIGHT:
		if placement.is_empty():draw_rect(Rect2(rect.position+Vector2(hover)*cell,Vector2.ONE*cell),Color(0.9,0.8,0.5,0.16))
		else:
			var def=state.catalog.building(placement);var reason=state.can_build(placement,hover)
			for x in range(hover.x,hover.x+int(def.width)):
				for y in range(hover.y,hover.y+int(def.height)):
					if world.occupied(Vector2i(x,y)):reason="Площадка занята людьми."
			var area=Rect2(rect.position+Vector2(hover)*cell,Vector2(def.width,def.height)*cell)
			var color=Color("b4ce88") if reason.is_empty() else Color("d3806b")
			draw_rect(area,Color(color,0.25));draw_rect(area,color,false,2)
			var hint="ЛКМ — заложить · "+str(int(def.width))+"×"+str(int(def.height)) if reason.is_empty() else reason
			draw_string(ThemeDB.fallback_font,Vector2(18,28),hint,HORIZONTAL_ALIGNMENT_LEFT,size.x-30,14,color)
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-16),"Колесо — масштаб · средняя кнопка — камера · ПКМ — приказ · P — пауза · Пробел — техника",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("c1c9b2"))
