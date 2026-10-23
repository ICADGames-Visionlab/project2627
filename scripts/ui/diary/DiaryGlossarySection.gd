## DiaryGlossarySection - uma categoria do glossário no diário: o nome dela, um traço e as palavras.
class_name DiaryGlossarySection
extends VBoxContainer

## Espaço para variáveis onready

@onready var _title: Label = %Title
@onready var _words: Container = %Words

## Espaço para funções personalizadas

func configure(title: String) -> void:
	_title.text = title


# Onde a página põe os chips das palavras desta categoria.
func get_words_container() -> Container:
	return _words
