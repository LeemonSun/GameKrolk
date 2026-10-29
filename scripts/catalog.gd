extends RefCounted

const PATH="res://data/game.json"
var data: Dictionary

func _init():
	data=JSON.parse_string(FileAccess.get_file_as_string(PATH))

func building(id:String)->Dictionary:
	return data.buildings.get(id,{})

func troop(id:String)->Dictionary:
	return data.troops.get(id,{})

func hero(id:String)->Dictionary:
	return data.heroes.get(id,{})
