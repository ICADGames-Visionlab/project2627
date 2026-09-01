# DebugFonts.gd — Fonte monoespaçada compartilhada pelos painéis de debug (desempenho e log).
#
# Existe para os overlays não repetirem a lista de famílias nem criarem um SystemFont cada um.
# Sem largura fixa de caractere, os dígitos mudam de tamanho a cada atualização e o número "pula"
# na tela — é o detalhe que separa um painel legível de um borrão piscando.
class_name DebugFonts
extends RefCounted

# Famílias monoespaçadas por ordem de preferência. SystemFont cai na fonte padrão da engine se
# nenhuma delas existir na máquina, então a lista pode ser otimista.
const MONO_FONT_NAMES: Array[String] = [
	"Consolas", "Cascadia Mono", "JetBrains Mono", "DejaVu Sans Mono", "Menlo",
	"Liberation Mono", "Courier New"
]
# Proporção largura/altura típica de uma fonte monoespaçada, usada para dimensionar colunas em
# número de caracteres sem precisar medir a fonte de verdade.
const MONO_CHAR_RATIO: float = 0.62

# Instância única, criada na primeira vez que alguém pede. Um SystemFont resolve a família contra
# as fontes instaladas na máquina, e não há motivo para pagar isso uma vez por overlay.
static var _mono_font: SystemFont


# Devolve a fonte monoespaçada dos painéis de debug, criando-a na primeira chamada.
static func mono() -> SystemFont:
	if _mono_font == null:
		_mono_font = SystemFont.new()
		_mono_font.font_names = PackedStringArray(MONO_FONT_NAMES)
	return _mono_font
