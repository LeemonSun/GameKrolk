extends RefCounted

static func person(c:CanvasItem,p:Vector2,kind:String,team:int,phase:float,facing:Vector2,attack:float,flash:float,hero_color:Color=Color.WHITE,dead:bool=false,zoom:float=1.0):
	var hero=kind=="hero";var scale=1.35 if hero else 0.85
	var main=hero_color if hero else (Color("a7bfc0") if team==0 else Color("aa6256"))
	if kind=="guard":main=Color("b7a879") if team==0 else Color("b48a68")
	if kind=="archer":main=Color("829e88") if team==0 else Color("9d8466")
	if flash>0:main=Color("fff1c5")
	c.draw_set_transform(p,0,Vector2.ONE*scale*zoom)
	if dead:
		c.draw_rect(Rect2(-8,-2,17,5),main.darkened(0.4));c.draw_rect(Rect2(6,-4,5,5),Color("ad9a83"));c.draw_set_transform(Vector2.ZERO);return
	c.draw_rect(Rect2(-10,0,21,8),Color(0.025,0.035,0.03,0.4))
	var walk=sin(phase)*3
	c.draw_rect(Rect2(-6,0+walk,5,7),Color("27332f"));c.draw_rect(Rect2(2,0-walk,5,7),Color("27332f"))
	if hero:c.draw_colored_polygon(PackedVector2Array([Vector2(-9,-15),Vector2(8,-15),Vector2(11,5),Vector2(-12,4)]),main.darkened(0.25))
	c.draw_rect(Rect2(-7,-13,14,15),main.darkened(0.1));c.draw_rect(Rect2(-6,-12,12,4),main.lightened(0.12))
	c.draw_rect(Rect2(-4,-21,9,9),Color("cfb999"));c.draw_rect(Rect2(-5,-23,11,5),main.lightened(0.1))
	if hero:
		c.draw_rect(Rect2(-6,-26,14,4),Color("252b2c"));c.draw_rect(Rect2(-3,-29,9,4),Color("252b2c"))
	elif kind=="guard":c.draw_rect(Rect2(-4,-16,9,3),Color("60695f"))
	var dir=facing.normalized();var arm=Vector2(5,-9)+dir*5
	c.draw_line(Vector2(4,-10),arm,main.lightened(0.2),4)
	if kind=="archer":
		c.draw_arc(arm,9,dir.angle()-1.2,dir.angle()+1.2,8,Color("dbc197"),2)
	else:
		var swing=dir.rotated((-0.9+attack*2.0) if attack>0 else -0.2)
		var end=arm+swing*(24 if hero else 17)
		c.draw_line(arm,end,Color("e3dfc4"),3 if hero else 2)
		c.draw_line(arm-dir.orthogonal()*4,arm+dir.orthogonal()*4,Color("a68c5c"),2)
		if attack>0.05:
			c.draw_arc(arm,24 if hero else 17,dir.angle()-0.95,dir.angle()+attack*1.2,12,Color(1,0.9,0.67,0.55),3)
	if kind=="guard":
		c.draw_rect(Rect2(-12,-14,8,16),main.darkened(0.3));c.draw_rect(Rect2(-10,-12,4,12),main.lightened(0.2))
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
