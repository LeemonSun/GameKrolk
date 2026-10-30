extends Control

signal continue_requested(path:String)
signal new_requested(seed_value:int,threat:String,title:String)
signal exit_requested
signal resume_requested
const Rules=preload("res://scripts/world_rules.gd")
const Palette=preload("res://scripts/palette.gd")
var library=[]
var slots:OptionButton
var continue_button:Button
var back_button:Button
var seed_input:LineEdit
var name_input:LineEdit
var threat:OptionButton
var details:Label
var description:Label
var message:Label
var exit_button:Button
var new_button:Button
var modes=["calm","standard","harsh"]

func label(text:String,size_px:int=16)->Label:
	var node=Label.new();node.text=text;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.add_theme_font_size_override("font_size",size_px);return node

func button(text:String,action:Callable)->Button:
	var node=Button.new();node.text=text;node.custom_minimum_size.y=42;node.pressed.connect(action);return node

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var background=ColorRect.new();background.color=Palette.BG;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(center)
	var panel=PanelContainer.new();panel.custom_minimum_size.x=720;center.add_child(panel)
	var margin=MarginContainer.new()
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,22)
	panel.add_child(margin)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",12);margin.add_child(column)
	var title=label("КРОЛИК / ЦИТАДЕЛЬ",32);title.add_theme_color_override("font_color",Palette.INK);column.add_child(title)
	column.add_child(label("Мир · строительство · люди · оборона   |   прототип 0.0.8",14))
	back_button=button("Вернуться в игру",func():resume_requested.emit());column.add_child(back_button)
	column.add_child(HSeparator.new());column.add_child(label("Сохранённые партии",18))
	slots=OptionButton.new();slots.custom_minimum_size.y=42;slots.item_selected.connect(_select_slot);column.add_child(slots)
	details=label("",14);column.add_child(details)
	continue_button=button("Продолжить выбранную партию",_continue);column.add_child(continue_button)
	column.add_child(HSeparator.new());column.add_child(label("Новая игра",21))
	name_input=LineEdit.new();name_input.placeholder_text="Название поселения";name_input.text="Новое поселение";name_input.max_length=40;name_input.custom_minimum_size.y=38;column.add_child(name_input)
	var row=HBoxContainer.new();column.add_child(row)
	var seed_label=label("Зерно карты");seed_label.autowrap_mode=TextServer.AUTOWRAP_OFF;seed_label.custom_minimum_size.x=110;row.add_child(seed_label)
	seed_input=LineEdit.new();seed_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;seed_input.custom_minimum_size.y=38;seed_input.placeholder_text="Число от 1 до 2147483647";row.add_child(seed_input)
	row.add_child(button("Случайное",_random_seed));_random_seed()
	threat=OptionButton.new();threat.custom_minimum_size.y=42
	for id in modes:threat.add_item(Rules.MODES[id].name)
	threat.select(1);threat.item_selected.connect(func(_index):_mode_hint());column.add_child(threat)
	description=label("",14);column.add_child(description);_mode_hint()
	new_button=button("Начать новую игру",_new_game);column.add_child(new_button)
	column.add_child(label("Новая партия создаётся в отдельном файле. Предыдущие поселения сохраняются.",13))
	message=label("",14);message.add_theme_color_override("font_color",Palette.INK);column.add_child(message)
	exit_button=button("Выход",func():exit_requested.emit());column.add_child(exit_button)

func open(entries:Array,current_path:String,can_resume:bool):
	library=entries;slots.clear();back_button.visible=can_resume;message.text=""
	var selected=0
	for i in library.size():
		var item=library[i]
		var text=item.name+" · "+str(item.population)+" жителей · %02d:%02d"%[int(item.clock)/60,int(item.clock)%60]
		if not item.valid:text+=" · не читается"
		slots.add_item(text)
		if item.path==current_path:selected=i
	if library.is_empty():slots.add_item("Пока нет сохранённых партий")
	slots.disabled=library.is_empty();slots.select(selected);_select_slot(selected);show()
	if can_resume:back_button.grab_focus()
	elif not continue_button.disabled:continue_button.grab_focus()
	else:name_input.grab_focus()

func _select_slot(index:int):
	continue_button.disabled=library.is_empty() or not library[index].valid
	Palette.button_accent(continue_button,not continue_button.disabled);Palette.button_accent(new_button,continue_button.disabled)
	if library.is_empty():details.text="Начните новое поселение ниже.";return
	var item=library[index]
	details.text="Зерно %d · %s. %s"%[item.seed,Rules.MODES[item.mode].name,item.warning]

func _continue():
	if not library.is_empty() and library[slots.selected].valid:continue_requested.emit(library[slots.selected].path)

func _new_game():
	var text=seed_input.text.strip_edges()
	if not text.is_valid_int() or int(text)<1 or int(text)>2147483647:
		message.text="Для зерна карты введите целое число от 1 до 2147483647.";return
	new_requested.emit(int(text),modes[threat.selected],name_input.text)

func _random_seed():seed_input.text=str(randi_range(1,2147483647))
func _mode_hint():description.text=Rules.MODES[modes[threat.selected]].hint
func show_error(text:String):message.text=text
