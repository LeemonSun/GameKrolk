extends RefCounted

const BG=Color("101012")
const PANEL=Color("19191c")
const INK=Color("ededeb")
const MUTED=Color("a6a6aa")
const EDGE=Color("414145")
const ACCENT=Color("e5e5e1")
const DARK_INK=Color("141416")

static func style(color:Color,border:Color=Color.TRANSPARENT,radius:int=4)->StyleBoxFlat:
	var box=StyleBoxFlat.new();box.bg_color=color;box.set_corner_radius_all(radius);box.set_border_width_all(1);box.border_color=border
	box.content_margin_left=14;box.content_margin_right=14;box.content_margin_top=10;box.content_margin_bottom=10
	return box

static func make()->Theme:
	var result=Theme.new();result.default_font_size=16
	var font=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI","Noto Sans"]);result.default_font=font
	result.set_color("font_color","Label",INK)
	for control in ["Button","OptionButton"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:result.set_color(key,control,INK)
		result.set_color("font_disabled_color",control,Color("77777c"))
		result.set_stylebox("normal",control,style(Color("242427"),EDGE))
		result.set_stylebox("hover",control,style(Color("35353a"),Color("89898f")))
		result.set_stylebox("pressed",control,style(Color("45454b"),INK))
		result.set_stylebox("focus",control,style(Color.TRANSPARENT,INK))
		result.set_stylebox("disabled",control,style(Color("1d1d20"),Color("303034")))
	for control in ["PanelContainer","AcceptDialog"]:result.set_stylebox("panel",control,style(PANEL,EDGE,6))
	result.set_stylebox("normal","LineEdit",style(Color("141416"),EDGE))
	result.set_stylebox("focus","LineEdit",style(Color.TRANSPARENT,INK))
	result.set_color("font_color","LineEdit",INK);result.set_color("caret_color","LineEdit",INK)
	result.set_stylebox("panel","PopupMenu",style(PANEL,EDGE))
	result.set_stylebox("hover","PopupMenu",style(ACCENT,ACCENT))
	result.set_color("font_color","PopupMenu",INK);result.set_color("font_hover_color","PopupMenu",DARK_INK)
	result.set_stylebox("panel","TooltipPanel",style(ACCENT,Color("88888c")))
	result.set_color("font_color","TooltipLabel",DARK_INK)
	result.set_constant("separation","VBoxContainer",9);result.set_constant("separation","HBoxContainer",10)
	return result

static func button_accent(button:Button,enabled:bool=true):
	for key in ["normal","hover","pressed"]:
		if enabled:button.add_theme_stylebox_override(key,style(ACCENT if key=="normal" else Color("ccccca"),ACCENT))
		elif button.has_theme_stylebox_override(key):button.remove_theme_stylebox_override(key)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		if enabled:button.add_theme_color_override(key,DARK_INK)
		elif button.has_theme_color_override(key):button.remove_theme_color_override(key)
