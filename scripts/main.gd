extends Control

const State=preload("res://scripts/state.gd")
const Settlement=preload("res://scripts/settlement.gd")
const Profiles=preload("res://scripts/profiles.gd")
const StartMenu=preload("res://scripts/start_menu.gd")
var profiles
var start_menu
var session_started=false
var combat_was_paused=false
var live_labels={}
var demolition_dialog:ConfirmationDialog
var demolition_uid=-1
var dialog_was_paused=false
var selected_building_uid=-1
const BaseView=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
const BattleView=preload("res://scripts/battle_view.gd")
const Palette=preload("res://scripts/palette.gd")
const Logistics=preload("res://scripts/logistics.gd")
const Commerce=preload("res://scripts/commerce.gd")
const BG=Palette.BG
const PANEL=Palette.PANEL
const ACCENT=Palette.ACCENT
const INK=Palette.INK
const MUTED=Palette.MUTED
var state
var world
var base
var combat
var sidebar:VBoxContainer
var resources:Label
var title:Label
var subtitle:Label
var toast:Label
var battle_stats:Label
var skill_button:Button
var content:HBoxContainer
var root:VBoxContainer
var toolbar:Container
var tab="build"
var selected_building=-1
var placement=""
var in_battle=false
var toast_time=0.0
var result_dialog:AcceptDialog
var retreat_dialog:ConfirmationDialog
var ui_clock=0.0
var benchmark_mode=false
var selected_source=-1
var autosave_clock=0.0

func _ready():
	Engine.max_fps=60
	var test_profile="user://progress.json"
	var test_mode="--test-mode" in OS.get_cmdline_user_args()
	if test_mode:
		test_profile="res://work/test-session-%d.json"%OS.get_process_id()
		profiles=Profiles.new("res://work/profiles-%d"%OS.get_process_id(),test_profile)
	else:
		profiles=Profiles.new();test_profile=profiles.last_path()
	state=State.new(test_profile);state.load_progress()
	world=World.new(state);world.notice.connect(_notice);world.raid_finished.connect(func(_won):_refresh());world.settlement_changed.connect(func():call_deferred("_refresh"))
	_setup_theme();_setup_ui();_refresh()
	start_menu=StartMenu.new();add_child(start_menu)
	start_menu.continue_requested.connect(_continue_profile);start_menu.new_requested.connect(_new_party)
	start_menu.resume_requested.connect(_resume_game);start_menu.exit_requested.connect(_close)
	if test_mode:session_started=true;start_menu.hide()
	else:_open_main_menu()
	if not state.warning.is_empty():_notice(state.warning,15)
	print("GAMEKROLK_READY "+JSON.stringify({"version":"0.0.6","save":ProjectSettings.globalize_path(state.save_path),"renderer":RenderingServer.get_current_rendering_method()}))

func _style(color:Color,border:Color=Color.TRANSPARENT,radius:int=10)->StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color
	s.set_corner_radius_all(radius);s.set_border_width_all(1);s.border_color=border
	s.content_margin_left=14;s.content_margin_right=14;s.content_margin_top=10;s.content_margin_bottom=10
	return s

func _setup_theme():
	theme=Palette.make()

func _label(text:String,size_px:int=16,color:Color=INK)->Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size_px);label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _button(text:String,callback:Callable=Callable(),accent:bool=false)->Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=42;b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if callback.is_valid():b.pressed.connect(callback)
	if accent:Palette.button_accent(b)
	return b

func _setup_ui():
	var bg=ColorRect.new();bg.color=BG;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,26)
	for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin);root=VBoxContainer.new();root.add_theme_constant_override("separation",13);margin.add_child(root)
	var header=HBoxContainer.new();root.add_child(header)
	var brand=VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;brand.add_theme_constant_override("separation",1);header.add_child(brand)
	title=_label("КРОЛИК  /  ЦИТАДЕЛЬ",29,ACCENT);brand.add_child(title)
	subtitle=_label("ЖИВОЙ УЧАСТОК    ·    прототип 0.0.6    ·    хозяйство и оборона",12,MUTED);brand.add_child(subtitle)
	header.add_child(_button("Сохранить",func():_notice("Прогресс сохранён." if state.save_progress() else state.warning)))
	header.add_child(_button("Меню",_open_main_menu))
	header.add_child(_button("Во весь экран  F11",_fullscreen))
	var resource_panel=PanelContainer.new();root.add_child(resource_panel);resources=_label("",17,INK);resource_panel.add_child(resources)
	toolbar=HFlowContainer.new();root.add_child(toolbar)
	content=HBoxContainer.new();content.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",16);root.add_child(content)
	var stage=PanelContainer.new();stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(stage)
	var layers=Control.new();layers.custom_minimum_size=Vector2(640,460);layers.size_flags_vertical=Control.SIZE_EXPAND_FILL;layers.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.add_child(layers)
	base=BaseView.new();base.state=state;base.world=world;base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(base);base.cell_clicked.connect(_base_click);base.order_requested.connect(world.order)
	combat=BattleView.new();combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(combat);combat.hide();combat.ended.connect(_battle_ended);combat.notice.connect(_notice)
	var side=PanelContainer.new();side.custom_minimum_size.x=340;content.add_child(side)
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side.add_child(scroll)
	sidebar=VBoxContainer.new();sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.custom_minimum_size.x=300;sidebar.add_theme_constant_override("separation",10);scroll.add_child(sidebar)
	toast=_label("Начните с рубежей поселения: наладьте древесину, еду и жильё. Людям можно назначать работу.",14,MUTED)
	toast.custom_minimum_size.y=42;root.add_child(toast)
	result_dialog=AcceptDialog.new();result_dialog.title="Итог сражения";result_dialog.ok_button_text="Вернуться в крепость";result_dialog.confirmed.connect(_return_base);result_dialog.canceled.connect(_return_base);add_child(result_dialog)
	retreat_dialog=ConfirmationDialog.new();retreat_dialog.title="Отступить?";retreat_dialog.dialog_text="Осада будет засчитана как поражение. Выжившие вернутся; потраченный провиант не возвращается."
	retreat_dialog.ok_button_text="Отступить";retreat_dialog.cancel_button_text="Остаться";retreat_dialog.confirmed.connect(_retreat);add_child(retreat_dialog)
	demolition_dialog=ConfirmationDialog.new();demolition_dialog.title="Снести постройку?"
	demolition_dialog.ok_button_text="Снести";demolition_dialog.cancel_button_text="Отмена";demolition_dialog.confirmed.connect(_demolish);add_child(demolition_dialog)
	demolition_dialog.canceled.connect(func():world.paused=dialog_was_paused;_refresh())
	get_window().close_requested.connect(_close)

func _clear(box:Node):
	for child in box.get_children():box.remove_child(child);child.queue_free()

func _refresh():
	_resolve_selected()
	_update_resources();live_labels.clear();_clear(toolbar);_clear(sidebar)
	if in_battle:_battle_ui();return
	if not state.data.world.raid_active:world.sync_army()
	for entry in [["build","Строить"],["people","Люди"],["logistics","Снабжение"],["trade","Поставки"],["goals","Рубежи"],["orders","Приказы"],["heroes","Герои"],["army","Армия"],["officers","Должности"],["tech","Технологии"]]:
		var b=_button(entry[1],_set_tab.bind(entry[0]),tab==entry[0]);toolbar.add_child(b)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	toolbar.add_child(_button("Продолжить" if world.paused else "Пауза  P",_pause_world))
	toolbar.add_child(_button("Разведка",func():_notice(preload("res://scripts/world_rules.gd").forecast(state.data),15)))
	if "--test-mode" in OS.get_cmdline_user_args() or "--developer" in OS.get_cmdline_user_args():
		toolbar.add_child(_button("Полигон",func():_start_battle("hero")))
		toolbar.add_child(_button("Проверить набег",_trigger_raid,true))
	match tab:
		"build":_build_ui()
		"people":_people_ui()
		"logistics":_logistics_ui()
		"trade":_trade_ui()
		"goals":_goals_ui()
		"orders":_orders_ui()
		"heroes":_heroes_ui()
		"army":_army_ui()
		"officers":_officers_ui()
		"tech":_tech_ui()
	base.selected=selected_building;base.selected_source=selected_source;base.placement=placement;base.show_orders=tab=="orders";base.queue_redraw()

func _set_tab(value:String):
	tab=value;placement="";base.placement="";_refresh()

func _update_resources():
	var raid="НАБЕГ!" if state.data.world.raid_active else "НАБЕГ ЧЕРЕЗ %02d:%02d"%[int(state.data.world.raid_in)/60,int(state.data.world.raid_in)%60]
	resources.text="МОНЕТЫ %d    ДРЕВЕСИНА %d    КАМЕНЬ %d    ПРОВИАНТ %d    АРМИЯ %d/%d    %s"%[state.data.coins,state.data.wood,state.data.stone,state.data.food,state.army_count(),state.capacity(),raid]

func _heading(text:String):sidebar.add_child(_label(text,21,ACCENT))
func _hint(text:String):sidebar.add_child(_label(text,14,MUTED))
func _line():sidebar.add_child(HSeparator.new())

func _build_ui():
	_heading("Постройки поселения")
	if selected_source>=0:
		var source=world._source(selected_source)
		if not source.is_empty():
			sidebar.add_child(_label(("Дерево" if source.kind=="wood" else "Месторождение")+" · осталось "+str(int(source.amount)),18,ACCENT))
			sidebar.add_child(_button("Добывать до исчерпания",_gather_selected,true));_line()
	if selected_building>=0 and selected_building<state.data.buildings.size():
		var building=state.data.buildings[selected_building];var def=state.catalog.building(building.id)
		_heading("%s · %s"%[def.name,"уровень "+str(building.level) if building.built else "стройка"])
		_hint(def.hint)
		var progress=_label("",14,ACCENT);live_labels["building_progress"]=progress;sidebar.add_child(progress)
		if building.id=="gate" and building.built:
			sidebar.add_child(_button("Закрыть ворота" if building.gate_open else "Открыть ворота",func():_notice(world.toggle_gate(int(building.uid)));_refresh(),true))
			_hint("Открытый проход доступен обеим сторонам. Занятый проход закрыть нельзя.")
		var quote=world.repair_quote(int(building.uid))
		if not building.repair.is_empty():
			sidebar.add_child(_button("Отменить ремонт",func():_notice(world.cancel_repair(int(building.uid)));_refresh()))
		elif not quote.is_empty():
			sidebar.add_child(_button("Ремонт · %d дерева / %d камня"%[quote.wood,quote.stone],func():_notice(world.repair(int(building.uid)));_refresh(),true))
		if building.built and building.target_level==building.level and building.level<def.max_level:
			var upgrade_button=_button("Улучшить · %d / %d / %d"%[def.coins*building.level,def.wood*building.level,def.stone*building.level],_upgrade,true)
			upgrade_button.disabled=not building.repair.is_empty();sidebar.add_child(upgrade_button)
		if building.id!="hq":sidebar.add_child(_button("Убрать постройку…",_ask_demolish))
		_line()
	elif placement.is_empty():_hint("Выберите здание на карте для улучшения. Новую стройку выполняет рабочий; размеры видны под курсором.")
	if not placement.is_empty():_hint("Размещаете: "+state.catalog.building(placement).name+". ЛКМ — заложить, Esc — отменить.")
	var grid=GridContainer.new();grid.columns=2;sidebar.add_child(grid)
	for id in ["wall","gate","warehouse","house","lumber","mine","farm","barracks","forge","lab","hq"]:
		var def=state.catalog.building(id)
		var button=_button("%s\n%d / %d / %d"%[def.name,def.coins,def.wood,def.stone],_place.bind(id),placement==id)
		button.custom_minimum_size.y=62;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.disabled=def.has("tech") and not state.data.research.get(def.tech,false)
		button.tooltip_text=def.hint+"\nРазмер: %d×%d. Стройка: %d секунд работы."%[def.width,def.height,def.work];grid.add_child(button)
	_line();_hint("Цена: монеты / древесина / камень. Лес, шахты и фермы требуют технологий и рабочих. Рабочее место обслуживает один человек.")
	_hint("Повреждённую постройку выберите на карте: ремонт выполняет строитель после оплаты материалов.")
	_update_live()

func _place(id:String):
	placement=id;selected_building=-1;selected_building_uid=-1;selected_source=-1;_notice("Выберите свободную клетку для: "+state.catalog.building(id).name);_refresh()

func _base_click(cell:Vector2i):
	if in_battle:return
	var index=state.building_at(cell)
	if index>=0:
		selected_building=index;selected_building_uid=int(state.data.buildings[index].uid);selected_source=-1;placement="";_refresh();return
	if placement.is_empty():
		selected_building=-1;selected_building_uid=-1
		var source=world.source_at(cell);selected_source=int(source.id) if not source.is_empty() else -1
		_refresh();return
	var def=state.catalog.building(placement)
	for x in range(cell.x,cell.x+int(def.width)):
		for y in range(cell.y,cell.y+int(def.height)):
			if world.occupied(Vector2i(x,y)):_notice("Площадка занята людьми. Отведите бойцов или дождитесь рабочего.");return
	var result=state.build(placement,cell);_notice(result)
	if result.begins_with("Заложено"):
		selected_building=state.data.buildings.size()-1;selected_building_uid=int(state.data.buildings[-1].uid);placement="";world.rebuild_navigation();world._assign_jobs();state.save_progress()
	_refresh()

func _upgrade():_resolve_selected();_notice(state.upgrade(selected_building));_refresh()

func _gather_selected():_notice(world.gather(selected_source));_refresh()

func _tech_ui():
	_heading("Технологии поселения")
	_hint("Технологии открывают постоянное производство. Рабочие физически идут к источнику и возвращают груз.")
	for id in state.catalog.data.technologies:
		var def=state.catalog.data.technologies[id]
		sidebar.add_child(_label(def.name,19,ACCENT));_hint(def.hint)
		var b=_button("Изучено" if state.data.research[id] else "Изучить · %d / %d / %d"%[def.coins,def.wood,def.stone],_research.bind(id),true)
		b.disabled=state.data.research[id];sidebar.add_child(b);_line()
	_hint("Числа цены: монеты / древесина / камень. Первые три открытия; большая технологическая цепочка ещё предстоит.")

func _research(id:String):_notice(state.research(id));_refresh()
func _pause_world():world.paused=not world.paused;_refresh()
func _trigger_raid():_notice(world.start_raid());_refresh()

func _heroes_ui():
	_heading("Герой вашего похода")
	_hint("В этой первой сборке в бой выходит один выбранный герой. Остальные сохраняют свой опыт.")
	for id in ["astreya","lina","warden"]:
		var def=state.catalog.hero(id);var available=state.hero_available(id)
		var b=_button(("● " if state.data.selected_hero==id else "")+def.name+" · ур. "+str(state.hero_level(id)),_select_hero.bind(id),state.data.selected_hero==id)
		b.disabled=not available;sidebar.add_child(b)
		_hint(def.role)
		if not available:_hint("Нужна лаборатория." if id=="lina" else "Нужен Штаб II.")
		elif state.data.selected_hero==id:
			_hint(def.skill+": "+def.hint)
			_hint("До следующего уровня: %d опыта."%[60-int(state.data.xp[id])%60])
		_line()
	_hint("Способности — тестовые игровые адаптации. Командир гарнизона — временный персонаж вне канона.")

func _select_hero(id:String):
	if not state.hero_available(id):return
	if state.data.world.raid_active:_notice("Во время набега смена героя недоступна.");return
	state.data.selected_hero=id;state.save_progress();_refresh()

func _army_ui():
	_heading("Соберите свой полк")
	_hint("Бойцы защищают этот участок от набегов. Потери сохраняются; полигон служит отдельной тренировкой.")
	for id in ["militia","archer","guard"]:
		var def=state.catalog.troop(id)
		sidebar.add_child(_label("%s  ·  %d в строю"%[def.name,state.data.army[id]],18))
		_hint("Здоровье %d · урон %d · %s"%[def.hp,def.damage,"дальний бой" if id=="archer" else "ближний бой"])
		var b=_button("Нанять +1  ·  %d монет"%def.coins,_recruit.bind(id));b.disabled=id=="guard" and state.level("forge")==0;sidebar.add_child(b)
		if b.disabled:_hint("Стражам требуется кузница.")
		_line()
	_hint("Штаб и Казармы расширяют лимит армии. Кузница усиливает обычные атаки союзников.")

func _recruit(id:String):
	if state.data.world.raid_active:_notice("В ранней версии пополнение доступно между набегами.");return
	_notice(state.recruit(id));_refresh()

func _officers_ui():
	_heading("Поручите людям работу")
	_hint("Первые две должности проверяют делегирование. Это пока функциональные назначения без отдельных биографий слуг.")
	for id in ["commander","quartermaster"]:
		var assigned=bool(state.data.officers[id]);var command=id=="commander"
		sidebar.add_child(_label("Командующий" if command else "Снабженец",19,ACCENT))
		_hint("После осады пополняет мечников до 12, пока есть монеты и места." if command else "После осады покупает провиант до запаса 12. Цена: 4 монеты за единицу.")
		var b=_button("Освободить должность" if assigned else "Назначить",_assign.bind(id));b.disabled=not command and state.level("hq")<2;sidebar.add_child(b)
		if b.disabled:_hint("Вторая должность откроется на уровне Штаба II.")
		var toggle=CheckButton.new();toggle.text="Разрешить автоматизацию";toggle.button_pressed=state.data.auto_recruit if command else state.data.auto_supply;toggle.disabled=not assigned
		toggle.toggled.connect(_toggle_auto.bind("auto_recruit" if command else "auto_supply"));sidebar.add_child(toggle);_line()
	sidebar.add_child(_button("Купить 3 провианта · 12 монет",_buy_food))
	sidebar.add_child(_button("Выполнить поручения сейчас",_run_automation))
	_hint("Уже есть нужный запас — расхода не будет. Еда расходуется населением и армией каждую игровую минуту.")

func _assign(id:String):_notice(state.assign(id));_refresh()
func _toggle_auto(enabled:bool,key:String):state.data[key]=enabled;state.save_progress()

func _buy_food():
	if state.data.coins<12:_notice("Недостаточно монет.");return
	state.data.coins-=12;state.data.food+=3;state.save_progress();_notice("Куплено 3 провианта.");_refresh()

func _run_automation():
	var result=state.automate();state.save_progress();_notice("Поручения: нанято %d, провиант +%d, расход %d монет."%[result.recruited,result.food,result.spent]);_refresh()

func _start_battle(kind:String):
	if in_battle:return
	if kind=="siege":
		var error=state.begin_siege()
		if not error.is_empty():_notice(error);return
	benchmark_mode=kind!="siege"
	var army=state.data.army.duplicate()
	var count=26+int(state.data.war_rank)*7
	if kind=="hero":army={"militia":0,"archer":0,"guard":0};count=20
	elif kind in ["200","500","1000"]:
		var half=int(kind)/2;army={"militia":int(half*0.6)-1,"archer":int(half*0.3),"guard":half-int(half*0.6)-int(half*0.3)};count=half
	var wall_hp=0
	for b in state.data.buildings:
		if b.id=="wall":wall_hp+=int(b.level)*80
	in_battle=true;base.hide();combat.show()
	combat.start({"mode":kind,"hero":state.data.selected_hero,"hero_level":state.hero_level(state.data.selected_hero),"rank":state.data.war_rank,
		"forge":state.level("forge"),"army":army,"enemies":count,"keep_hp":300+state.level("hq")*80+wall_hp,"seed":20261029+int(state.data.wins)+int(state.data.losses)})
	_refresh();_notice("ПКМ — приказ выбранной группе. Пробел — техника. P — пауза. Полигон не меняет прогресс." if benchmark_mode else "Защитите крепость! ПКМ — приказ, Пробел — техника, P — пауза.",12)

func _battle_ui():
	toolbar.add_child(_button("Отступить" if not benchmark_mode else "Закрыть полигон",_request_retreat))
	toolbar.add_child(_button("Продолжить" if combat.paused else "Пауза  P",_pause))
	toolbar.add_child(_button("Скорость ×1" if combat.speed==1 else "Скорость ×2",_speed))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	toolbar.add_child(_label("ПОЛИГОН · без расхода ресурсов" if benchmark_mode else "ОСАДА · защитите крепость",15,ACCENT))
	_heading(state.catalog.hero(state.data.selected_hero).name)
	battle_stats=_label("",16,INK);sidebar.add_child(battle_stats)
	skill_button=_button("",combat.cast,true);sidebar.add_child(skill_button)
	_hint(state.catalog.hero(state.data.selected_hero).hint)
	var automatic=CheckButton.new();automatic.text="Применять технику автоматически";automatic.button_pressed=combat.automatic_skill;automatic.toggled.connect(func(value):combat.automatic_skill=value);sidebar.add_child(automatic)
	_line();sidebar.add_child(_label("КОМУ ОТДАТЬ ПРИКАЗ",13,MUTED))
	for item in [["all","Всем бойцам  ·  1"],["hero","Только герою  ·  2"],["militia","Мечникам  ·  3"],["archer","Лучникам  ·  4"],["guard","Стражам  ·  5"]]:
		sidebar.add_child(_button(item[1],_select_group.bind(item[0]),combat.group==item[0]))
	_hint("Нажмите правой кнопкой на поле, чтобы задать направление. В контакте бойцы атакуют самостоятельно.")
	if benchmark_mode:
		_line();_hint("НАГРУЗОЧНЫЕ СЦЕНЫ")
		for count in ["200","500","1000"]:sidebar.add_child(_button(count+" участников",_restart_sandbox.bind(count)))
	_update_battle_ui()

func _update_battle_ui():
	if not in_battle or not is_instance_valid(battle_stats):return
	var b=combat.battle;var hero=b.units[b.hero_id]
	battle_stats.text="Герой: %d / %d\nСоюзники: %d   ·   Враги: %d\nКрепость: %d / %d\nВремя: %02d:%02d   ·   FPS %d"%[hero.hp,hero.max_hp,b.alive(0),b.alive(1),b.keep_hp,b.keep_max,int(b.time)/60,int(b.time)%60,Engine.get_frames_per_second()]
	skill_button.text=("Техника  ·  Пробел" if b.hero_cooldown<=0 else "Восстановление  ·  %.1f с"%b.hero_cooldown)
	skill_button.disabled=b.hero_cooldown>0 or hero.hp<=0 or b.finished

func _select_group(value:String):combat.group=value;_refresh()
func _pause():combat.paused=not combat.paused;_refresh()
func _speed():combat.speed=2.0 if combat.speed==1.0 else 1.0;_refresh()

func _restart_sandbox(count:String):
	in_battle=false;combat.running=false;_start_battle(count)

func _request_retreat():
	if benchmark_mode:_return_base();return
	combat.paused=true;_refresh();retreat_dialog.popup_centered(Vector2i(480,220))

func _retreat():
	if not in_battle:return
	combat.battle.finished=true;combat.battle.won=false;combat.reported=true;_battle_ended(false)

func _battle_ended(won:bool):
	var b=combat.battle;var text="ПОБЕДА" if won else "ПОРАЖЕНИЕ"
	text+="\n\nПротивников побеждено: %d / %d\nВремя боя: %d с"%[b.kills,b.total_enemies,int(b.time)]
	if not benchmark_mode:
		var reward=state.finish_siege(won,b.survivors())
		if not reward.is_empty():
			text+="\n\nМонеты +%d   ·   Материалы +%d\nПровиант +%d   ·   Опыт героя +%d"%[reward.coins,reward.wood,reward.food,reward.xp]
			var auto=reward.automation
			if auto.spent>0:text+="\nПоручения: бойцы +%d, провиант +%d\nРасход поручений: %d монет"%[auto.recruited,auto.food,auto.spent]
			if reward.has("reserves"):text+="\nГарнизон выделил трёх резервных мечников."
	else:text+="\n\nЭто полигон. Армия и ресурсы не изменены."
	text+="\n\nГерои возвращаются даже после поражения.\nОбычные бойцы в осаде несут потери."
	result_dialog.dialog_text=text;result_dialog.popup_centered(Vector2i(570,440));_update_resources()

func _return_base():
	result_dialog.hide();in_battle=false;combat.running=false;combat.hide();base.show();_refresh();state.save_progress();_notice("Вы вернулись в поселение. Мир и добыча продолжаются.")

func _notice(text:String,duration:float=6.0):
	if toast==null:return
	toast.text=text;toast_time=duration;toast.add_theme_color_override("font_color",ACCENT)

func _process(dt):
	if start_menu!=null and start_menu.visible:return
	if world!=null and not in_battle:
		world.step(dt);autosave_clock+=dt
		if autosave_clock>20:autosave_clock=0;state.save_progress()
	if toast_time>0:
		toast_time-=dt
		if toast_time<=0:toast.add_theme_color_override("font_color",MUTED)
	ui_clock+=dt
	if ui_clock>0.2:ui_clock=0;_update_battle_ui();_update_resources();_update_live()

func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_F11:_fullscreen();get_viewport().set_input_as_handled();return
	if start_menu!=null and start_menu.visible:
		if event.keycode==KEY_ESCAPE:_resume_game();get_viewport().set_input_as_handled()
		return
	if in_battle and not result_dialog.visible:
		match event.keycode:
			KEY_SPACE:combat.cast()
			KEY_P:_pause()
			KEY_1:_select_group("all")
			KEY_2:_select_group("hero")
			KEY_3:_select_group("militia")
			KEY_4:_select_group("archer")
			KEY_5:_select_group("guard")
			KEY_ESCAPE:_request_retreat()
		get_viewport().set_input_as_handled()
	elif not in_battle:
		match event.keycode:
			KEY_ESCAPE:
				if placement.is_empty():_open_main_menu()
				else:placement="";_refresh()
			KEY_P:_pause_world()
			KEY_S:world.stop(base.command_group)
			KEY_H:world.stop(base.command_group,true)
			KEY_SPACE:_notice("Снимите паузу для применения техники." if world.paused else world.battle.skill())
			KEY_1:_world_group("all");_notice("Приказ получат все бойцы.")
			KEY_2:_world_group("hero");_notice("Приказ получит только герой.")
			KEY_3:_world_group("militia");_notice("Приказ получат мечники.")
			KEY_4:_world_group("archer");_notice("Приказ получат лучники.")
			KEY_5:_world_group("guard");_notice("Приказ получат стражи.")

func _orders_ui():
	_heading("Управление бойцами")
	_hint("Выберите группу и режим, затем укажите место правой кнопкой на карте. Приказы доступны на паузе.")
	var grid=GridContainer.new();grid.columns=2;sidebar.add_child(grid)
	for entry in [["all","Все"],["hero","Герой"],["militia","Мечники"],["archer","Лучники"],["guard","Стражи"]]:
		var button=_button(entry[1],_world_group.bind(entry[0]),base.command_group==entry[0]);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(button)
	_line()
	sidebar.add_child(_button("Идти без остановки на бой",_world_mode.bind("move"),world.command_mode=="move"))
	sidebar.add_child(_button("Двигаться с ответным боем",_world_mode.bind("advance"),world.command_mode=="advance"))
	_hint("Обычный приказ не отвлекается на врага по пути. При движении с боем отряд останавливается, чтобы атаковать противника в пределах оружия.")
	_line()
	sidebar.add_child(_button("Удерживать позицию  H",func():world.stop(base.command_group,true)))
	sidebar.add_child(_button("Отменить маршрут  S",func():world.stop(base.command_group)))
	_hint("Удержание запрещает преследование, но оставляет атаки в пределах оружия. Отмена маршрута возвращает свободную оборону. При закрытом проходе бойцы ждут; после открытия продолжают путь.")
	var status=_label("",14,ACCENT);live_labels["orders"]=status;sidebar.add_child(status);_update_live()

func _world_group(group:String):
	base.command_group=group
	if tab=="orders":_refresh()
func _world_mode(mode:String):world.command_mode=mode;_refresh()

func _fullscreen():
	var window=get_window();window.mode=Window.MODE_WINDOWED if window.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _close():
	if session_started and not in_battle:state.save_progress()
	get_tree().quit()

func _people_ui():
	_heading("Люди поселения")
	_hint("Рабочие %d / мест %d. Еда: %d в игровую минуту. В походном полигоне поселение стоит на паузе."%[state.data.world.workers.size(),state.worker_capacity(),world.food_need()])
	var food=_label("",14,ACCENT);live_labels["food"]=food;sidebar.add_child(food)
	var hire=_button("Нанять рабочего · 40 монет / 4 еды",_hire_worker,true)
	hire.disabled=state.data.world.workers.size()>=state.worker_capacity();sidebar.add_child(hire)
	if hire.disabled:_hint("Чтобы пригласить следующего человека, достройте жилой дом.")
	var priority=CheckButton.new();priority.text="Стройка важнее производства";priority.button_pressed=state.data.construction_first
	priority.tooltip_text="Автоматический рабочий вернёт груз и возьмётся за стройку. Ручные поручения и выбранные профессии сохраняются."
	priority.toggled.connect(func(value):world.set_priority(value));sidebar.add_child(priority)
	_line()
	for worker in state.data.world.workers:
		sidebar.add_child(_label(worker.name,18,ACCENT))
		var status=_label("",14,MUTED);live_labels["worker_"+str(int(worker.id))]=status;sidebar.add_child(status)
		var choice=OptionButton.new();choice.custom_minimum_size.y=36
		for text in ["Авто: работа по приоритету","Строитель","Дровосек: нужна лесопилка","Шахтёр: нужна шахта","Фермер: нужна ферма","Отдых"]:
			choice.add_item(text)
		choice.select(Settlement.PREFERENCES.find(worker.preference));choice.item_selected.connect(_worker_choice.bind(int(worker.id)));sidebar.add_child(choice);_line()
	_hint("При смене работы груз сначала возвращается в Штаб. Выбранный источник добывается до конца; отдых отменяет поручение.")
	_update_live()

func _worker_choice(index:int,id:int):
	_notice(world.set_preference(id,Settlement.PREFERENCES[index]));_update_live()

func _hire_worker():
	_notice(state.hire_worker());world._relocate_blocked();world._assign_jobs();state.save_progress();_refresh()

func _goals_ui():
	_heading("Рубежи поселения")
	_hint("Ваш отряд обустраивает поселение. Сначала наладьте лес, еду и жильё; затем получите доход от поставок и подготовьте гарнизон. Рубежи можно выполнять в разном порядке.")
	sidebar.add_child(_button("Перейти к строительству",_set_tab.bind("build"),true))
	sidebar.add_child(_button("Поставки и доход",_set_tab.bind("trade")))
	_hint("Это задачи обучающего среза, а не сюжетная кампания. Каждый рубеж даёт награду один раз.")
	for goal in Settlement.GOALS:
		var done=goal.id in state.data.achieved
		sidebar.add_child(_label(("✓ " if done else "○ ")+goal.title,19,ACCENT if not done else MUTED))
		_hint(goal.hint)
		_hint("Получено: %d монет."%goal.reward if done else "Награда: %d монет."%goal.reward);_line()
	_hint("Монеты также приходят за отражённые набеги. Потери армии остаются, а поселение продолжает работать между нападениями.")
	_hint(preload("res://scripts/world_rules.gd").forecast(state.data))

func _ask_demolish():
	if selected_building<0 or selected_building>=state.data.buildings.size():return
	var b=state.data.buildings[selected_building];demolition_uid=int(b.uid)
	dialog_was_paused=world.paused;world.paused=true
	demolition_dialog.dialog_text="Убрать «%s»? Вернётся %d древесины и %d камня. Монеты не возвращаются."%[state.catalog.building(b.id).name,int(b.paid_wood)/2,int(b.paid_stone)/2]
	demolition_dialog.popup_centered(Vector2i(460,220))

func _demolish():
	world.paused=dialog_was_paused
	for i in state.data.buildings.size():
		if int(state.data.buildings[i].uid)==demolition_uid:
			_notice(state.demolish(i));selected_building=-1;selected_building_uid=-1;world.rebuild_navigation();world._assign_jobs();state.save_progress();_refresh();return
	_notice("Постройка уже отсутствует.")

func _resolve_selected():
	if selected_building_uid<0:return
	selected_building=-1
	for i in state.data.buildings.size():
		if int(state.data.buildings[i].uid)==selected_building_uid:selected_building=i;return
	selected_building_uid=-1

func _update_live():
	if in_battle:return
	if live_labels.has("orders"):
		var total=0;var moving=0;var waiting=0
		for unit in world.battle.units:
			if unit.team!=0 or unit.hp<=0 or (base.command_group!="all" and unit.kind!=base.command_group):continue
			total+=1
			if unit.route_blocked:waiting+=1
			elif unit.goal!=Vector2.INF:moving+=1
		live_labels.orders.text="Выбрано: %d · с маршрутом: %d · ждут прохода: %d"%[total,moving,waiting]
	for worker in state.data.world.workers:
		var key="worker_"+str(int(worker.id))
		if live_labels.has(key):live_labels[key].text=world.worker_status(int(worker.id))
	if live_labels.has("food"):
		live_labels.food.text="Еды нет — скорость работы 60%." if state.data.food==0 else "Запас еды: %d. Следующая трапеза через %d с."%[state.data.food,ceili(60-state.data.world.food_clock)]
	if live_labels.has("building_progress") and selected_building>=0 and selected_building<state.data.buildings.size():
		var building=state.data.buildings[selected_building]
		if not building.repair.is_empty():live_labels.building_progress.text="Ремонт: %d%% · осталось восстановить %d"%[roundi(100*(1.0-building.repair.remaining/building.repair.total)),ceili(building.repair.remaining)]
		else:live_labels.building_progress.text="Работа: %d%% · к уровню %d"%[mini(100,roundi(building.work_done/world.required_work(building)*100)),building.target_level] if world.needs_work(building) else "Построено · прочность %d / %d"%[building.hp,state.catalog.building(building.id).hp*building.level]
		if building.id=="hq":live_labels.building_progress.text+="\nШтаб: %d / %d"%[world.battle.keep_hp,world.battle.keep_max]
	if live_labels.has("storage"):
		var lines=[]
		for entry in [["wood","Древесина"],["stone","Камень"],["food","Провиант"]]:
			var current=int(state.data[entry[0]]);var capacity=Logistics.capacity(state.data,entry[0])
			lines.append("%s: %d / %d%s"%[entry[1],current,capacity," · нет места" if current>=capacity else ""])
		live_labels.storage.text="\n".join(lines)
	if live_labels.has("trade"):
		var cargo=state.data.commerce.cargo
		live_labels.trade.text="Новые заказы через %d с\nЭкспортов: %d · доход: %d монет\n%s"%[ceili(180-state.data.commerce.window),state.data.commerce.orders,state.data.commerce.income,"Нет поставки в пути" if cargo.is_empty() else (Commerce.OFFERS[cargo.id].name+" · "+("ждёт конца нападения" if cargo.remaining<=0 else str(ceili(cargo.remaining))+" с"))]
	if live_labels.has("logistics"):
		var carriers=0;var cargo=0;var stalled=0
		for w in state.data.world.workers:
			if w.carry>0:carriers+=1;cargo+=int(w.carry)
			if "хранилищ" in world.worker_status(int(w.id)).to_lower():stalled+=1
		live_labels.logistics.text="Груз у людей: %d · носильщиков: %d\nОжидают места или пути: %d\nРасход еды: %d в минуту"%[cargo,carriers,stalled,world.food_need()]

func _logistics_ui():
	_heading("Снабжение поселения")
	_hint("Добыча даёт запас только после разгрузки. Рабочий выбирает ближайший доступный Штаб или склад по длине пути.")
	var stocks=_label("",18,ACCENT);live_labels.storage=stocks;sidebar.add_child(stocks)
	var details=_label("",15);live_labels.logistics=details;sidebar.add_child(details)
	_line();_hint("Полное хранилище останавливает добычу. Уже поднятый груз остаётся у людей. Трата запасов освобождает место; работа возобновляется.")
	sidebar.add_child(_button("Разместить склад",_place.bind("warehouse"),true))
	_hint("Склад 2×2: 45 монет / 35 дерева / 15 камня. Уровень: +180 дерева, +140 камня, +60 еды. Запасы общие для поселения.")
	_line();_hint("Снос или потеря склада уменьшают предел, но уже накопленное не исчезает. Новая разгрузка ждёт освобождения места.")
	for building in state.data.buildings:
		if building.id not in ["hq","warehouse"]:continue
		var uid=int(building.uid)
		sidebar.add_child(_button("%s · %d,%d · %s"%[state.catalog.building(building.id).name,building.x,building.y,"ур. "+str(building.level) if building.built else "стройка"],_inspect_building.bind(uid)))
	_update_live()

func _inspect_building(uid:int):
	selected_building_uid=uid;tab="build";placement="";selected_source=-1;_refresh()

func _trade_ui():
	_heading("Местные поставки")
	_hint("Хозяйство даёт доход независимо от побед. Один обоз в пути; каждый заказ доступен раз в три игровых минуты. Отправка расходует запас сразу, оплата приходит после возвращения.")
	var status=_label("",16,ACCENT);live_labels.trade=status;sidebar.add_child(status)
	_line()
	var names={"wood":"дерева","stone":"камня","food":"еды","coins":"монет"}
	for id in Commerce.OFFERS:
		var offer=Commerce.OFFERS[id]
		sidebar.add_child(_label(offer.name,18))
		_hint("Отдать %d %s → получить %d %s"%[offer.amount,names[offer.take],offer.reward,names[offer.give]])
		var button=_button("Отправить поставку",_send_trade.bind(id));button.tooltip_text=Commerce.reason(state,id);sidebar.add_child(button)
		_line()
	_hint("Обозы здесь считаются по времени, отдельной фигурки на карте пока нет. Покупка и награды могут временно превысить предел склада; новая добыча ждёт места.")
	_update_live()

func _send_trade(id:String):_notice(Commerce.send(state,id));_refresh()

func _open_main_menu():
	if start_menu==null:return
	var save_error=""
	if session_started and not state.save_progress():save_error=state.warning if not state.warning.is_empty() else "Не удалось сохранить текущую партию."
	combat_was_paused=combat.paused;combat.paused=true
	start_menu.open(profiles.entries(),state.save_path,session_started)
	if not save_error.is_empty():start_menu.show_error(save_error)

func _resume_game():
	if not session_started:return
	start_menu.hide();combat.paused=combat_was_paused

func _continue_profile(path:String):
	if session_started and path==state.save_path:_resume_game();return
	if path not in profiles.paths():start_menu.show_error("Сохранение больше не найдено.");return
	var next=State.new(path)
	if not next.load_progress() or next.read_only:start_menu.show_error(next.warning);return
	_activate_party(next)

func _new_party(seed_value:int,threat:String,title_text:String):
	var next=profiles.create(seed_value,threat,title_text)
	if next==null:start_menu.show_error(profiles.error);return
	_activate_party(next)
	_set_tab("goals")

func _activate_party(next):
	state.before_save=Callable()
	for connection in base.order_requested.get_connections():base.order_requested.disconnect(connection.callable)
	state=next;world=World.new(state);base.state=state;base.world=world;base.order_requested.connect(world.order)
	world.notice.connect(_notice);world.raid_finished.connect(func(_won):_refresh());world.settlement_changed.connect(func():call_deferred("_refresh"))
	combat.running=false;combat.hide();base.show();result_dialog.hide();retreat_dialog.hide()
	in_battle=false;benchmark_mode=false;session_started=true;autosave_clock=0;tab="build"
	selected_building=-1;selected_building_uid=-1;selected_source=-1;placement="";base.zoom=1.0;base.pan=Vector2.ZERO
	base.command_group="hero"
	start_menu.hide();_refresh()
	if state.save_progress():
		if not profiles.remember(state.save_path):_notice("Партия сохранена, но последнюю выбранную партию запомнить не удалось.")
	else:_notice(state.warning)
	if not state.warning.is_empty():_notice(state.warning)
