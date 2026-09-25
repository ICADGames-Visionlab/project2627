## GlossaryWord - uma palavra que o jogador pode descobrir e usar no profiling.
##
## COMO USAR: um .tres por palavra em res://resources/profiling/palavras/. A palavra é apontada em
## dois lugares: no pool do NPC (NPCProfile.glossary_words, o que define o "23/36" do glossário) e
## na solução de uma história (ProfilingStory.solution). O mesmo arquivo pode estar no pool de
## vários NPCs — "MARCOS" pode ser palavra do glossário de três pessoas diferentes.
##
## PALAVRAS EM CONJUNTO ([MARCOS]/[CASTRO]): a legenda do GDD diz que, quando duas palavras aparecem
## juntas no mundo, clicar em qualquer uma das duas adiciona AMBAS ao glossário. É o que o campo
## "Paired Words" faz aqui, e ele vale só pra este caso: se CASTRO aparecer sozinho em outro lugar,
## quem descobre é só CASTRO (quem aparece em conjunto é o TEXTO, não a palavra — ver
## ClickableWordText.gd, que lê a marcação "[MARCOS]/[CASTRO]" do próprio texto).
##
## O par é resolvido nos DOIS sentidos: marcar CASTRO em "Paired Words" de MARCOS basta, e descobrir
## qualquer um dos dois traz o outro (ver ProfilingJournal.discover_word).
##
## O guia completo está em docs/sistema_de_profiling.md.
@tool
class_name GlossaryWord
extends Resource

## Espaço para variáveis exportadas

## Identificador estável da palavra. É o que vai pro save e pra solução da história. Não é texto
## exibido ao jogador.
@export var id: StringName = &""

## Chave de tradução da palavra, em translations/translations.csv (ex.: GLOSSARY_WORD_MARCOS).
## Nunca escreva a palavra direto aqui: ela aparece no retângulo do glossário e dentro da lacuna,
## então é texto de jogador — e nome próprio também se traduz (Joe/Zé já é assim no projeto).
@export var text_key: String = ""

## A categoria da palavra, que decide a cor do retângulo dela no glossário.
@export var category: GlossaryCategory

## As palavras que vêm junto com esta quando ela aparece em conjunto no mundo. Ver o bloco
## "PALAVRAS EM CONJUNTO" no topo deste arquivo.
@export var paired_words: Array[GlossaryWord] = []

## Espaço para funções personalizadas

# A palavra traduzida, com o id em maiúsculas como último recurso pra lacuna nenhuma aparecer vazia
# se alguém esquecer a chave no CSV.
func get_display_text() -> String:
	if text_key.is_empty():
		return String(id).to_upper()
	return tr(text_key)


# A cor do retângulo desta palavra. Palavra sem categoria não é erro fatal (o glossário continua
# funcionando), então ela cai num cinza neutro e o aviso de preenchimento acusa o resto.
func get_color() -> Color:
	if category == null:
		return Color(0.6, 0.6, 0.6)
	return category.color


# O id da categoria, ou vazio. Existe porque o filtro e o save só precisam do id, e pedir a
# categoria inteira só pra ler o id espalharia checagem de null por toda parte.
func get_category_id() -> StringName:
	if category == null:
		return &""
	return category.id


# Se esta palavra cabe numa lacuna que pede a categoria dada. Cada lacuna só aceita a categoria da
# palavra esperada nela (um nome não entra onde a frase pede uma arma); lacuna sem categoria aceita
# qualquer palavra. Compara por id, e não por instância, pra um recurso duplicado não recusar a
# palavra certa.
func fits_category(expected: GlossaryCategory) -> bool:
	return expected == null or get_category_id() == expected.id


# Problemas de preenchimento, uma frase por problema. Compartilhado entre o resumo do NPCProfile e a
# validação em lote do menu de debug.
func collect_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	if id == &"":
		issues.append("Palavra sem id.")
	if text_key.is_empty():
		issues.append("Palavra \"%s\" sem chave de texto (text_key)." % id)
	if category == null:
		issues.append("Palavra \"%s\" sem categoria." % id)
	for paired: GlossaryWord in paired_words:
		if paired == null:
			issues.append("Palavra \"%s\" tem um par vazio na lista." % id)
		elif paired.id == id:
			issues.append("Palavra \"%s\" está emparelhada com ela mesma." % id)
	return issues


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "GlossaryWord(%s, %s)" % [id, get_category_id()]
