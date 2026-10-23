## DiaryPageView - base de toda página do diário: um Control que ocupa o par de folhas aberto e
## desenha um DiaryPage.
##
## COMO USAR: cada tipo de página (DiaryPage.Kind) é uma cena com um script que estende este. O
## DiaryBook instancia a cena do tipo, põe dentro do livro, preenche "book" e chama show_page() — de
## novo a cada mudança de conteúdo, então show_page() tem que conseguir redesenhar tudo do zero.
##
## Links, pop-ups e o menu de marcas não são da página: ela pede ao book (navigate, show_evidence,
## show_word_evidence, request_mark_menu), que é quem fica por cima das páginas.
class_name DiaryPageView
extends Control

## Espaço para variáveis

var book: DiaryBook

## Espaço para funções personalizadas

func show_page(_page: DiaryPage) -> void:
	pass


# false = a página desenha o próprio fundo (a capa fechada); o livro esconde as folhas abertas.
func uses_spread() -> bool:
	return true


# Apaga os filhos de um contêiner que a página remonta a cada show_page(). remove_child antes do
# queue_free pra a contagem e o layout já valerem neste mesmo quadro.
static func clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
