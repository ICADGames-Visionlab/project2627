extends Node

#Armazena o caminho dos 3 arquivos de save
const save_file_1: String = "user://save1.json"
const save_file_2: String = "user://save2.json"
const save_file_3: String = "user://save3.json"

const default_disctionary: Dictionary = {}

#Função para salvar o jogo no atual slot de save
func save_game (data: Dictionary, current_save: String) -> void:
	var save_file: FileAccess = FileAccess.open(current_save, FileAccess.WRITE)
	if save_file == null:
		push_error("Erro ao abrir arquivo de save")
		return
	var string_data: String = JSON.stringify(data)
	save_file.store_line(string_data)
	save_file.close()
	return

#Função para carregar um slot de save
func load_game(current_save: String) -> Dictionary:
	if FileAccess.file_exists(current_save):
		var save_file: FileAccess = FileAccess.open(current_save, FileAccess.READ)
		if save_file == null:
			push_error("Erro ao abrir arquivo de save")
			return default_disctionary
			
		var json = JSON.new()
		var string_data: String = save_file.get_line()
		if json.parse(string_data) == OK:
			var data: Dictionary = json.data
			save_file.close()
			return data
		push_error("Dados corrompidos")
	return default_disctionary

#Função para resetar um slot de save
func reset_save(current_save: String) -> void:
	if FileAccess.file_exists(current_save):
		DirAccess.remove_absolute(current_save)
		print("Arquivo de save deletado: ", current_save)


#Função para checar se o usuário já tem algum slot de save
func has_save(file_slot: String) -> bool:
	return FileAccess.file_exists(file_slot)
