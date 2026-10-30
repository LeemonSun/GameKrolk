extends Control

signal selected_region(point:Vector2i)
const Atlas=preload("res://scripts/atlas.gd")
const Art=preload("res://scripts/art.gd")
var model
var selected=Vector2i(-1,-1)
var mode="overview"
var texture:ImageTexture
var zoom=1.0
var pan=Vector2.ZERO
var preview_path=[]
var nearby_texture:ImageTexture
var nearby_sources=[]

func _ready():mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
func activate(source):
	if model==source:return
	model=source;model.ensure();selected=model.home();zoom=1;pan=Vector2.ZERO;mode="overview"
	var atlas=model.atlas;var bitmap=Image.create(atlas.side,atlas.side,false,Image.FORMAT_RGB8)
	for y in atlas.side:
		for x in atlas.side:
			var i=y*atlas.side+x;var color=Atlas.COLORS[atlas.biomes[i]]
			var neighbor=atlas.heights[y*atlas.side+maxi(0,x-1)]
			var light=clampf(1.0+(atlas.heights[i]-neighbor)*4,0.70,1.20)
			color=Color(color.r*light,color.g*light,color.b*light)
			if atlas.rivers[i]!=0:color=Color("487e9a")
			bitmap.set_pixel(x,y,color)
	texture=ImageTexture.create_from_image(bitmap);queue_redraw()

func map_rect()->Rect2:
	var extent=minf(size.x-50,size.y-60)*zoom
	return Rect2((size-Vector2.ONE*extent)*0.5+pan,Vector2.ONE*extent)

func nearby_rect()->Rect2:
	var cell=minf((size.x-40)/96,(size.y-70)/66)
	return Rect2((size-Vector2(96,66)*cell)*0.5,Vector2(96,66)*cell)

func prepare_nearby():
	var points=[];nearby_sources.clear()
	for y in range(-1,2):
		for x in range(-1,2):
			var point=selected+Vector2i(x,y)
			if model.atlas.inside(point) and point!=model.home():points.append(point)
	model.chunks.prefetch(points)
	var bitmap=Image.create(96,66,false,Image.FORMAT_RGB8);bitmap.fill(Atlas.COLORS[0])
	for y in 3:
		for x in 3:
			var point=selected+Vector2i(x-1,y-1)
			if not model.atlas.inside(point):continue
			var chunk=model.region(point);var biome=model.atlas.biomes[model.atlas.index(point)]
			var ground=Atlas.COLORS[biome] if biome>=2 else Color("8a8a70")
			for ty in 22:
				for tx in 32:
					var color=_terrain_color(chunk,ty*32+tx,ground)
					bitmap.set_pixel(x*32+tx,y*22+ty,color)
			if model.known(point):
				for source in chunk.sources:
					if source.amount>0:nearby_sources.append({"point":Vector2(x*32+source.x+0.5,y*22+source.y+0.5),"kind":source.kind})
	nearby_texture=ImageTexture.create_from_image(bitmap);queue_redraw()

func _terrain_color(chunk:Dictionary,index:int,fallback:Color)->Color:
	if chunk.tiles[index]==1:return Color("315363")
	if not chunk.has("heights"):return fallback
	var height=float(chunk.heights[index]);var left=float(chunk.heights[index-1]) if index%32>0 else height
	var light=clampf(0.9+height*0.15+(height-left)*10,0.70,1.20)
	var color=Atlas.COLORS[chunk.biomes[index]]
	return Color(color.r*light,color.g*light,color.b*light)

func _gui_input(event):
	if model==null:return
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:pan+=event.relative;queue_redraw()
	if not event is InputEventMouseButton or not event.pressed:return
	if mode=="nearby" and event.button_index==MOUSE_BUTTON_LEFT and nearby_rect().has_point(event.position):
		var relative=(event.position-nearby_rect().position)/nearby_rect().size*Vector2(3,3)
		var point=selected+Vector2i(floori(relative.x)-1,floori(relative.y)-1)
		if model.atlas.inside(point):
			if event.double_click:mode="region"
			selected_region.emit(point)
		return
	if mode=="overview":
		var rect=map_rect()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var relative=(event.position-rect.position)/rect.size
			zoom=clampf(zoom*(1.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.8),1,8)
			var next=map_rect();pan+=event.position-(next.position+relative*next.size);queue_redraw()
		elif event.button_index==MOUSE_BUTTON_LEFT and rect.has_point(event.position):
			var point=Vector2i((event.position-rect.position)/rect.size*model.atlas.side)
			if event.double_click:mode="region"
			selected_region.emit(point)

func _process(_dt):
	if visible:queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("172126"))
	if model==null or texture==null:return
	if mode=="region":_draw_region();return
	if mode=="nearby":_draw_nearby();return
	var rect=map_rect();var cell=rect.size.x/model.atlas.side
	draw_texture_rect(texture,rect,false)
	for item in model.state.data.regional.known:
		var parts=item.split(":");var point=Vector2(int(parts[0]),int(parts[1]))
		draw_rect(Rect2(rect.position+point*cell,Vector2.ONE*maxf(1,cell)),Color(1,1,1,0.13),false,1)
	var path=model.state.data.regional.expedition.get("path",preview_path)
	if path.size()>1:
		var line=PackedVector2Array()
		for point in path:line.append(rect.position+(Vector2(point[0],point[1])+Vector2.ONE*0.5)*cell)
		draw_polyline(line,Color(0.95,0.89,0.65,0.8),2)
	var home=rect.position+(Vector2(model.home())+Vector2.ONE*0.5)*cell
	draw_circle(home,5,Color("f0ead4"));draw_arc(home,8,0,TAU,20,Color("151b20"),2)
	draw_string(ThemeDB.fallback_font,home+Vector2(10,-7),"Ваше поселение",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f4f2e7"))
	if model.atlas.inside(selected):draw_rect(Rect2(rect.position+Vector2(selected)*cell,Vector2.ONE*cell).grow(2),Color("f2f2e9"),false,2)
	var expedition=model.state.data.regional.expedition
	if not expedition.is_empty():
		var location=expedition.path[int(expedition.index)]
		var point=rect.position+(Vector2(location[0],location[1])+Vector2.ONE*0.5)*cell
		draw_circle(point,4,Color("e2be76"));draw_arc(point,7,0,TAU,16,Color("161a1d"),2)
	draw_string(ThemeDB.fallback_font,Vector2(18,25),"КАРТА МИРА · реки и рельеф",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dedfd5"))
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-15),"ЛКМ — область · двойной щелчок — подробнее · колесо — масштаб · средняя кнопка — камера",HORIZONTAL_ALIGNMENT_LEFT,size.x-30,12,Color("c4c8c0"))

func _draw_region():
	var chunk=model.region(selected)
	if chunk.is_empty():return
	var cell=minf((size.x-40)/32,(size.y-70)/22);var origin=(size-Vector2(32,22)*cell)*0.5
	var biome=int(model.atlas.biomes[model.atlas.index(selected)])
	var ground=Atlas.COLORS[biome] if biome>=2 else Color("8a8a70")
	for y in 22:
		for x in 32:
			var shade=1.0+float((x*13+y*7)%5)*0.012
			var color=_terrain_color(chunk,y*32+x,Color(ground.r*shade,ground.g*shade,ground.b*shade))
			draw_rect(Rect2(origin+Vector2(x,y)*cell,Vector2.ONE*(cell+0.3)),color)
	if model.known(selected):
		for source in chunk.sources:
			if source.amount<=0:continue
			var point=origin+(Vector2(source.x,source.y)+Vector2.ONE*0.5)*cell
			if source.kind=="wood":
				draw_line(point,point+Vector2(0,cell*0.25),Color("504a3d"),2)
				draw_colored_polygon(PackedVector2Array([point+Vector2(-cell*0.35,cell*0.05),point+Vector2(0,-cell*0.7),point+Vector2(cell*0.35,cell*0.05)]),Color("314f40"))
			else:draw_circle(point,cell*0.28,Color("afb5ae"))
	if selected==model.home():
		for b in model.state.data.buildings:
			var point=origin+Vector2(b.x+b.width*0.5,b.y+b.height*0.5)*cell
			if not b.built:draw_rect(Rect2(origin+Vector2(b.x,b.y)*cell,Vector2(b.width,b.height)*cell),Color("c4b894"),false,1)
			else:Art.building(self,point,b.id,int(b.level),false,cell*minf(b.width,b.height)/70,b.get("gate_open",false))
	draw_string(ThemeDB.fallback_font,Vector2(18,25),"ОБЛАСТЬ %d,%d · %s"%[selected.x,selected.y,Atlas.NAMES[biome]],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e7e8dc"))
	if not model.known(selected):draw_string(ThemeDB.fallback_font,Vector2(18,size.y-15),"Местность видна на общей карте. Запасы откроются после разведки.",HORIZONTAL_ALIGNMENT_LEFT,size.x-30,13,Color("e3e0d0"))

func _draw_nearby():
	if nearby_texture==null:return
	var rect=nearby_rect();var cell=rect.size.x/96
	draw_texture_rect(nearby_texture,rect,false)
	for source in nearby_sources:
		var point=rect.position+source.point*cell
		if source.kind=="stone":draw_circle(point,maxf(1,cell*0.25),Color("afb5ae"))
		else:draw_colored_polygon(PackedVector2Array([point+Vector2(-cell*0.3,0),point+Vector2(0,-cell*0.6),point+Vector2(cell*0.3,0)]),Color("233c31"))
	for y in 3:
		for x in 3:
			var r=Rect2(rect.position+Vector2(x*32,y*22)*cell,Vector2(32,22)*cell)
			draw_rect(r,Color(1,1,1,0.08),false,1)
			if x==1 and y==1:draw_rect(r,Color("d5d6cb"),false,2)
	var home=model.home()-selected+Vector2i.ONE
	if home.x>=0 and home.x<3 and home.y>=0 and home.y<3:
		var point=rect.position+(Vector2(home)*Vector2(32,22)+Vector2(16,11))*cell
		draw_circle(point,5,Color("f0ead4"));draw_string(ThemeDB.fallback_font,point+Vector2(10,0),"Поселение",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("f4f2e7"))
	draw_string(ThemeDB.fallback_font,Vector2(18,25),"ОКРЕСТНОСТИ · 9 областей",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dedfd5"))
	draw_string(ThemeDB.fallback_font,Vector2(18,size.y-15),"ЛКМ — соседняя область · двойной щелчок — подробнее · белая рамка — выбранная область",HORIZONTAL_ALIGNMENT_LEFT,size.x-30,12,Color("c4c8c0"))
