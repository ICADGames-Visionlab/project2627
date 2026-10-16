# HeadData.gd — Uma cabeça: quem fala nos insights do canal de personagem.
#
# Existem dois tipos de cabeça, e só um deles é arquivo:
#   - A do jogador: um .tres em res://resources/heads/, desbloqueada desde o começo.
#   - A de cada NPC do roster: não tem arquivo. O InsightCatalog a monta a partir do NPCDefinition
#     (id, nome, cor e letra), então a cor do orbe é sempre a cor do NPC. O jogador ganha a cabeça
#     quando derrota o NPC, e derrotar é completar o profiling dele (ver HeadRegistry.has_head).
#
# Um .tres com origin NPC em res://resources/heads/ (ex.: old_fisherman) é cabeça avulsa: não é de
# NPC nenhum do roster, tem cor própria e só o debug a desbloqueia. Um .tres com o id de um NPC do
# roster é ignorado (ver InsightCatalog.load_all_heads): a cabeça de NPC é sempre a montada da
# definição, senão o orbe teria uma cor e o nome no diálogo outra.
#
# A cor é a identidade visual do orbe: posição diz o canal (no objeto ou acima da cabeça do
# jogador), cor diz quem está falando. Cor sozinha não basta — o glifo cobre daltonismo e as
# primeiras horas de jogo, quando ninguém decorou paleta nenhuma.
class_name HeadData
extends Resource

# PLAYER é a própria cabeça do jogador, sempre disponível. NPC precisa de desbloqueio.
enum Origin { PLAYER, NPC }

@export_group("Identidade")
@export var id: StringName = &""
# Chave do translations.csv com o nome exibido: nome de cabeça aparece na tela de diálogo.
@export var display_name_key: String = ""
@export var origin: Origin = Origin.NPC

@export_group("Aparência")
@export var color: Color = Color.WHITE
# Uma letra ou símbolo desenhado dentro do orbe. Mantenha curto: dois caracteres já ficam ilegíveis
# no tamanho em que o orbe é desenhado.
@export var glyph: String = ""


# A cabeça de um NPC, montada a partir da definição dele. É o que mantém a cor do orbe, a cor do nome
# no diálogo e a cor do NPC como uma só: as três vêm do mesmo campo (NPCDefinition.color).
static func from_npc(definition: NPCDefinition) -> HeadData:
	var head: HeadData = HeadData.new()
	head.id = definition.id
	head.display_name_key = String(definition.name_key)
	head.origin = Origin.NPC
	head.color = definition.color
	head.glyph = definition.get_head_glyph()
	return head


# Diz se a cabeça já nasce disponível para o jogador. É o único caso em que o HeadRegistry
# desbloqueia sozinho, sem ninguém pedir.
func starts_unlocked() -> bool:
	return origin == Origin.PLAYER


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "HeadData(%s)" % id
