# GlossaryMark.gd — A marca que o jogador pode pôr numa palavra do glossário: lixo ou estrela.
#
# É só o enum, e ele mora num script com class_name em vez de dentro do ProfilingJournal por um
# motivo prático: um enum só serve de TIPO em assinatura de função e de signal quando vem de um
# script com class_name (GlossaryMark.Kind), como NPCDefinition.EmotionSlot. Declarado dentro de um
# Autoload, ele viraria int solto com um comentário em cada assinatura — que é o que o projeto faz
# hoje com GameClock.DayEndReason (ver o EventBus), e o que dá pra evitar aqui.
#
# O ESTADO das marcas continua no ProfilingJournal: este arquivo não guarda nada.
#
# O guia completo está em docs/sistema_de_profiling.md.
class_name GlossaryMark
extends RefCounted

# NONE não é uma marca: é a palavra sem marca nenhuma, e é o que o diário devolve pra qualquer
# palavra que o jogador não tocou.
enum Kind { NONE, TRASH, STAR }

# PLACEHOLDER: os glifos das marcas, até existir ícone de arte. São texto de ferramenta de tela, não
# frase de jogador — não passam por tr().
const TRASH_GLYPH: String = "✗"
const STAR_GLYPH: String = "★"


# O glifo de uma marca, ou string vazia pra NONE. Fica aqui, e não na tela, porque o chip do
# glossário e o glossário do diário (quando ele existir) vão desenhar a mesma marca.
static func get_glyph(kind: Kind) -> String:
	match kind:
		Kind.TRASH:
			return TRASH_GLYPH
		Kind.STAR:
			return STAR_GLYPH
		_:
			return ""


# Nome da marca para log e menu de debug. Texto de ferramenta, não de jogador.
static func get_debug_name(kind: Kind) -> String:
	match kind:
		Kind.TRASH:
			return "lixo"
		Kind.STAR:
			return "estrela"
		_:
			return "sem marca"
