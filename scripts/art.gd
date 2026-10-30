extends RefCounted

# Original procedural sprites: cached body textures, independently animated
# equipment. The cache is bounded by catalog profiles and five body frames.
static var bodies:Dictionary={}

static func _body(kind:String,team:int,main:Color,frame:int)->Texture2D:
	var key=kind+str(team)+main.to_html(false)+str(frame)
	if bodies.has(key):return bodies[key]
	var dark="#"+main.darkened(0.52).to_html(false)
	var cloth="#"+main.darkened(0.22).to_html(false)
	var plate="#"+main.lightened(0.12).to_html(false)
	var edge="#"+main.lightened(0.36).to_html(false)
	var leg=2 if frame==1 else (-2 if frame==2 else 0)
	var torso='<path d="M8 18 L23 18 L26 36 L5 36 Z" fill="'+cloth+'" stroke="'+dark+'"/>'
	if kind=="hero":torso='<path d="M7 14 L24 14 L29 40 L3 39 Z" fill="'+dark+'"/>'+torso
	var helmet='<path d="M9 8 Q16 3 23 8 L23 16 L9 16Z" fill="'+plate+'" stroke="'+dark+'"/><path d="M10 11L22 11L21 14L11 14Z" fill="#23282a"/>'
	if kind=="archer":helmet='<path d="M7 15 Q8 1 16 2 Q24 4 25 16L21 18L11 18Z" fill="'+cloth+'" stroke="'+dark+'"/><path d="M12 8L20 8L21 15L12 15Z" fill="#bcb2a0"/><path d="M11 13L22 13" stroke="'+dark+'" stroke-width="2"/>'
	elif kind=="worker":helmet='<path d="M9 9L22 9L22 17L10 17Z" fill="#bcb2a0"/><path d="M7 8L24 8L22 4L10 4Z" fill="'+cloth+'" stroke="'+dark+'"/>'
	elif kind=="hero":helmet='<path d="M8 7L24 7L23 17L9 17Z" fill="'+edge+'" stroke="'+dark+'"/><path d="M10 12L22 12" stroke="#25282b" stroke-width="2"/><path d="M5 6L27 6L21 2L10 2Z" fill="'+dark+'"/>'
	var details='<path d="M10 20L22 20L21 29L11 29Z" fill="'+plate+'"/><path d="M16 20L16 29M11 24L21 24" stroke="'+edge+'"/><path d="M7 31L24 31" stroke="'+dark+'" stroke-width="3"/><path d="M14 30L18 30L18 33L14 33Z" fill="#b9b4a0"/>'
	if kind=="worker":details='<path d="M11 19L21 19L23 34L9 34Z" fill="'+dark+'"/><path d="M12 21L20 21L20 27L12 27Z" fill="'+cloth+'"/>'
	var legs='<path d="M9 33L14 33L14 '+str(43+leg)+'L8 '+str(43+leg)+'Z" fill="'+dark+'"/><path d="M18 33L23 33L24 '+str(43-leg)+'L18 '+str(43-leg)+'Z" fill="'+dark+'"/><path d="M7 '+str(44+leg)+'L14 '+str(44+leg)+'M18 '+str(44-leg)+'L25 '+str(44-leg)+'" stroke="#323538" stroke-width="3"/>'
	var content='<ellipse cx="16" cy="44" rx="14" ry="4" fill="#090b0c" opacity=".4"/>'+legs+torso+details+helmet
	if frame==4:content='<ellipse cx="16" cy="43" rx="15" ry="4" fill="#090b0c" opacity=".4"/><path d="M2 39L24 38L28 43L5 45Z" fill="'+cloth+'" stroke="'+dark+'"/><path d="M23 35L30 37L29 43L22 42Z" fill="'+plate+'"/>'
	var svg='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="48" viewBox="0 0 32 48">'+content+'</svg>'
	var bitmap=Image.new()
	if bitmap.load_svg_from_string(svg)!=OK:return null
	var texture=ImageTexture.create_from_image(bitmap);bodies[key]=texture;return texture

static func person(c:CanvasItem,p:Vector2,kind:String,team:int,phase:float,facing:Vector2,attack:float,flash:float,hero_color:Color=Color.WHITE,dead:bool=false,zoom:float=1.0):
	var hero=kind=="hero";var scale=1.2 if hero else 0.78
	var main=hero_color if hero else (Color("a5b5b6") if team==0 else Color("a7766b"))
	if kind=="guard":main=Color("b4b4a6") if team==0 else Color("b48d77")
	elif kind=="archer":main=Color("899a8f") if team==0 else Color("9e897d")
	elif kind=="worker":main=Color("9c9788")
	var frame=4 if dead else (1 if sin(phase)>0.3 else (2 if sin(phase)< -0.3 else 0))
	var texture=_body(kind,team,main,frame)
	var bob=-absf(sin(phase))*0.7 if not dead else 0.0
	c.draw_set_transform(p+Vector2(0,bob*zoom),0,Vector2.ONE*scale*zoom)
	if texture!=null:c.draw_texture(texture,Vector2(-16,-42),Color(1.6,1.6,1.6) if flash>0 else Color.WHITE)
	if dead:c.draw_set_transform(Vector2.ZERO);return
	var dir=facing.normalized();var hand=Vector2(5,-17)+dir*5
	c.draw_line(Vector2(5,-19),hand,main.lightened(0.25),4)
	if kind=="archer":
		var angle=dir.angle()
		c.draw_arc(hand,11,angle-1.3,angle+1.3,10,Color("b9b09a"),2)
		c.draw_line(hand+dir.rotated(-1.3)*11,hand-dir*attack*5,Color("c8cbca"),1)
		c.draw_line(hand-dir*attack*5,hand+dir.rotated(1.3)*11,Color("c8cbca"),1)
		if attack>0:c.draw_line(hand-dir*6,hand+dir*16,Color("dddcd1"),1.5)
	elif kind=="worker":
		var tool=Vector2(6,-12)+dir*4
		c.draw_line(tool,tool+dir.rotated(-0.4)*19,Color("857b67"),2.5)
		c.draw_line(tool+dir.rotated(-0.4)*17-dir.orthogonal()*5,tool+dir.rotated(-0.4)*17+dir.orthogonal()*5,Color("b5b9b4"),3)
	else:
		var swing=dir.rotated(-0.6+attack*1.8 if attack>0 else -0.25)
		var tip=hand+swing*(28 if hero else 22)
		c.draw_line(hand,tip,Color("d9dcda"),3 if hero else 2)
		c.draw_line(hand-swing*3,hand,Color("8a806b"),3)
		c.draw_line(hand-dir.orthogonal()*4,hand+dir.orthogonal()*4,Color("ada58e"),2)
		if attack>0.05:c.draw_arc(hand,28 if hero else 22,dir.angle()-0.8,dir.angle()+attack*1.1,12,Color(0.9,0.93,0.92,0.48),2)
	if kind=="guard":
		c.draw_colored_polygon(PackedVector2Array([Vector2(-15,-25),Vector2(-4,-25),Vector2(-3,-9),Vector2(-10,-4),Vector2(-16,-10)]),main.darkened(0.35))
		c.draw_polyline(PackedVector2Array([Vector2(-15,-25),Vector2(-4,-25),Vector2(-3,-9),Vector2(-10,-4),Vector2(-16,-10),Vector2(-15,-25)]),main.lightened(0.35),1.5)
		c.draw_line(Vector2(-10,-22),Vector2(-10,-9),Color("d5d3c4"),1)
	c.draw_set_transform(Vector2.ZERO)

static func building(c:CanvasItem,p:Vector2,id:String,level:int,selected:bool=false,zoom:float=1.0,gate_open:bool=false):
	c.draw_set_transform(p,0,Vector2.ONE*zoom)
	var gold=Color("cfb57b")
	if selected:c.draw_rect(Rect2(-33,-34,66,70),Color(0.85,0.73,0.45,0.2));c.draw_rect(Rect2(-33,-34,66,70),gold,false,2)
	c.draw_rect(Rect2(-28,12,63,20),Color(0.04,0.06,0.04,0.4))
	if id=="gate":
		c.draw_rect(Rect2(-28,-25,11,53),Color("8b918c"));c.draw_rect(Rect2(17,-25,11,53),Color("8b918c"))
		c.draw_rect(Rect2(-28,-29,56,8),Color("b5b8ac"))
		if gate_open:
			c.draw_rect(Rect2(-17,-18,5,43),Color("515951"));c.draw_rect(Rect2(12,-18,5,43),Color("515951"))
		else:
			c.draw_rect(Rect2(-17,-18,34,43),Color("586253"))
			for x in [-12,-4,4,12]:c.draw_line(Vector2(x,-17),Vector2(x,24),Color("a0a793"),2)
			c.draw_line(Vector2(-16,5),Vector2(16,5),Color("252c28"),5)
	elif id=="warehouse":
		c.draw_rect(Rect2(-30,-15,60,43),Color("929783"))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-34,-15),Vector2(-24,-31),Vector2(24,-31),Vector2(34,-15)]),Color("495d55"))
		c.draw_rect(Rect2(-13,-10,26,37),Color("2e3931"))
		for x in [-27,17]:
			c.draw_rect(Rect2(x,9,12,18),Color("a88a5b"));c.draw_line(Vector2(x,12),Vector2(x+12,24),Color("625e45"),2)
		c.draw_line(Vector2(-13,-5),Vector2(13,-5),Color("b8b99e"),2)
	elif id=="farm":
		c.draw_rect(Rect2(-30,-28,60,58),Color("675e3c"))
		for row in 5:
			c.draw_line(Vector2(-26,-22+row*10),Vector2(26,-22+row*10),Color("967947"),3)
			for column in 5:
				var tip=Vector2(-20+column*10,-24+row*10)
				c.draw_line(tip+Vector2(0,5),tip+Vector2(0,-3),Color("9bb473"),2)
	elif id=="wall":
		c.draw_rect(Rect2(-25,-11,50,32),Color("737b70"));c.draw_rect(Rect2(-25,-18,50,10),Color("a1a58d"))
		for x in [-25,-5,15]:c.draw_rect(Rect2(x,-26,11,13),Color("a1a58d"))
		for x in [-24,0,23]:c.draw_line(Vector2(x,-7),Vector2(x,19),Color("545e55"),1)
	else:
		c.draw_rect(Rect2(-25,-9,50,37),Color("8c927b"));c.draw_rect(Rect2(-22,-7,44,31),Color("b0ac89"))
		var roof=Color("4c6761")
		if id=="forge":roof=Color("8e6751")
		elif id=="lab":roof=Color("587b76")
		c.draw_colored_polygon(PackedVector2Array([Vector2(-32,-9),Vector2(0,-34),Vector2(32,-9)]),roof)
		c.draw_line(Vector2(-32,-9),Vector2(0,-34),roof.lightened(0.3),3)
		c.draw_rect(Rect2(-5,8,12,20),Color("38453d"))
		c.draw_rect(Rect2(-19,0,8,10),Color("dbc48c"));c.draw_rect(Rect2(12,0,8,10),Color("dbc48c"))
		if id=="hq":
			c.draw_line(Vector2(0,-33),Vector2(0,-60),gold,2)
			c.draw_colored_polygon(PackedVector2Array([Vector2(1,-60),Vector2(21,-55),Vector2(1,-49)]),Color("d8c39b"))
		elif id=="forge":
			c.draw_rect(Rect2(14,-34,10,22),Color("787969"));c.draw_rect(Rect2(-18,12,11,10),Color("efad65"))
		elif id=="lab":
			c.draw_circle(Vector2(1,-15),8,Color("8cd2b4"));c.draw_line(Vector2(1,-27),Vector2(1,-20),Color("cce4c8"),4)
		elif id=="infirmary":
			c.draw_rect(Rect2(-12,-24,24,17),Color("dadcd4"))
			c.draw_line(Vector2(0,-22),Vector2(0,-9),Color("30393a"),4)
			c.draw_line(Vector2(-7,-16),Vector2(7,-16),Color("30393a"),4)
		elif id=="barracks":
			c.draw_line(Vector2(-14,-24),Vector2(14,-5),gold,3);c.draw_line(Vector2(14,-24),Vector2(-14,-5),gold,3)
		elif id=="lumber":
			for i in 3:c.draw_rect(Rect2(-28+i*8,17,7,14),Color("b18a59"))
			c.draw_line(Vector2(-15,-23),Vector2(15,-3),Color("d9d4b1"),3)
		elif id=="mine":
			c.draw_rect(Rect2(-15,-8,30,32),Color("333e37"));c.draw_line(Vector2(-17,6),Vector2(17,-13),gold,4)
		elif id=="house":
			c.draw_rect(Rect2(13,-30,7,15),Color("746f5d"));c.draw_rect(Rect2(-18,13,9,9),Color("849567"))
	for i in level:c.draw_rect(Rect2(-9+i*8,31,5,4),gold)
	c.draw_set_transform(Vector2.ZERO)
