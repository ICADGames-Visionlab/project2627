# InsightData.gd — Um insight: o que o mundo, ou uma cabeça, tem a dizer sobre algo.
#
# Um .tres por insight, em res://resources/insights/. O designer preenche tudo pelo Inspector; não
# existe caminho que exija abrir um script para acrescentar conteúdo.
#
# @tool porque _validate_property() e o setter de channel rodam dentro do editor: sem isso o
# Inspector nunca esconderia head_id nas fontes de ambiente.
#
# O guia completo está em docs/insights.md.
@tool
class_name InsightData
extends Resource

# Ambiente fala pelo mundo e abre uma caixa de texto no próprio objeto; personagem fala por uma
# cabeça e abre a tela de diálogo. É a única diferença que o resto do sistema precisa conhecer.
enum Channel { ENVIRONMENT, CHARACTER }

# Desempate quando dois insights da mesma fonte estão disponíveis ao mesmo tempo. Enum (e não int
# solto) porque "Alta" se lê no Inspector e 10 não; os valores são espaçados para caber uma faixa
# intermediária no futuro sem renumerar os .tres existentes.
enum Priority { LOW = -10, NORMAL = 0, HIGH = 10 }

@export_group("Conteúdo")
@export var id: StringName = &""
@export var channel: Channel = Channel.ENVIRONMENT:
	set = _set_channel
# Chave do translations.csv, nunca o texto: texto escrito aqui garante localização refeita depois.
@export var text_key: String = ""

# Só para CHARACTER: qual cabeça fala. A cabeça do jogador está sempre desbloqueada; a de um NPC
# só depois de derrotá-lo (ver HeadRegistry).
@export var head_id: StringName = &""

@export_group("Portas")
@export var required_flags: Array[StringName] = []
@export var blocked_by_flags: Array[StringName] = []

@export_group("Comportamento")
@export var priority: Priority = Priority.NORMAL
# Com one_shot, o insight deixa de ser novidade depois de lido: continua relegível (o orbe fica
# vazado no lugar), mas perde a vez para qualquer insight ainda não lido da mesma fonte.
@export var one_shot: bool = true
@export var grants_flag: StringName = &""


# Esconde head_id quando o insight é de ambiente: campo que não se aplica não deve aparecer no
# Inspector. Enum é int por baixo, então a comparação de prioridade na escolha continua funcionando
# sem conversão.
func _validate_property(property: Dictionary) -> void:
	if property.name == "head_id" and channel != Channel.CHARACTER:
		property.usage = PROPERTY_USAGE_NO_EDITOR


# Troca o canal e pede ao Inspector que remonte a lista de propriedades — sem isso o head_id só
# apareceria (ou sumiria) na próxima vez que o recurso fosse selecionado.
func _set_channel(value: Channel) -> void:
	channel = value
	notify_property_list_changed()


# Diz se o insight fala por uma cabeça. Existe para os call sites não repetirem a comparação com o
# enum, que é o tipo de detalhe que se esquece de atualizar quando um canal novo aparecer.
func is_character() -> bool:
	return channel == Channel.CHARACTER


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "InsightData(%s, %s)" % [id, "CHARACTER/%s" % head_id if is_character() else "ENVIRONMENT"]
