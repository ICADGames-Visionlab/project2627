# HeadData.gd — Uma cabeça: quem fala nos insights do canal de personagem.
#
# Um .tres por cabeça, em res://resources/heads/. A cabeça do jogador nasce desbloqueada; as de
# NPC só existem para o jogador depois que ele derrota o dono (ver HeadRegistry.unlock_head).
#
# A cor é a identidade visual do orbe: posição diz o canal (no objeto ou orbitando o jogador), cor
# diz quem está falando. Cor sozinha não basta — o glifo cobre daltonismo e as primeiras horas de
# jogo, quando ninguém decorou paleta nenhuma.
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


# Diz se a cabeça já nasce disponível para o jogador. É o único caso em que o HeadRegistry
# desbloqueia sozinho, sem ninguém pedir.
func starts_unlocked() -> bool:
	return origin == Origin.PLAYER


# Descrição curta para log e para os relatórios do menu de debug.
func _to_string() -> String:
	return "HeadData(%s)" % id
