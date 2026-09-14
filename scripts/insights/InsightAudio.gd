# InsightAudio.gd — O som dos insights: toca quando o jogador descobre algo pela primeira vez.
#
# Escuta insight_revealed no bus e pede o som ao AudioManager. Nenhum arquivo do sistema de insights
# chama isto: tirar esta cena da main.tscn só deixa a descoberta muda, sem quebrar nada. Releitura
# não toca nada — o som é a recompensa da descoberta, e repeti-lo a cada clique ensina o jogador a
# ignorá-lo.
#
# É uma cena, e não código no AudioManager, por dois motivos: o AudioManager é um Autoload de script,
# sem Inspector onde o designer escolha o som; e ele cuida de tocar áudio, não de saber que existem
# insights.
#
# PLACEHOLDER: sem first_read_sfx atribuído no Inspector, o som é sintetizado em código (duas notas
# curtas). O log do boot avisa quando o placeholder está em uso. O som final entra pelo Inspector,
# sem mexer neste script — ver a issue de substituição de placeholder.
#
# O guia completo está em docs/insights.md.
class_name InsightAudio
extends Node

# PLACEHOLDER: parâmetros da síntese do som provisório. Não são balanceamento: somem junto com o
# placeholder no dia em que o som final entrar.
const PLACEHOLDER_SAMPLE_RATE: int = 22050
const PLACEHOLDER_FIRST_NOTE_HZ: float = 659.25     # Mi5
const PLACEHOLDER_SECOND_NOTE_HZ: float = 987.77    # Si5
const PLACEHOLDER_NOTE_DELAY: float = 0.09
const PLACEHOLDER_NOTE_LENGTH: float = 0.35
const PLACEHOLDER_ATTACK: float = 0.005
const PLACEHOLDER_DECAY: float = 12.0
const PLACEHOLDER_PEAK: float = 0.35

# Som da primeira leitura de um insight. Vazio usa o placeholder sintetizado.
@export var first_read_sfx: AudioStream
@export var first_read_volume_db: float = -6.0

var _placeholder_sfx: AudioStreamWAV = null


func _ready() -> void:
	EventBus.insight_revealed.connect(_on_insight_revealed)
	if first_read_sfx == null:
		_placeholder_sfx = _build_placeholder_chime()
		print("[Insights] - PLACEHOLDER: som de primeira leitura sintetizado em código (first_read_sfx vazio)")


# Toca o som da descoberta. Releitura sai sem som, de propósito (ver o topo do arquivo).
func _on_insight_revealed(event: InsightRevealedEvent) -> void:
	if not event.first_time:
		return
	var stream: AudioStream = first_read_sfx if first_read_sfx != null else _placeholder_sfx
	AudioManager.play_sfx(stream, first_read_volume_db)


# PLACEHOLDER: monta um sininho de duas notas em memória. Sintetizado, e não um arquivo de áudio
# qualquer, para não entrar no projeto um asset sem dono que depois ninguém lembra de substituir.
func _build_placeholder_chime() -> AudioStreamWAV:
	var frame_count: int = int((PLACEHOLDER_NOTE_DELAY + PLACEHOLDER_NOTE_LENGTH) * PLACEHOLDER_SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frame_count * 2)
	for frame: int in frame_count:
		var time: float = float(frame) / float(PLACEHOLDER_SAMPLE_RATE)
		var sample: float = _placeholder_note(time, PLACEHOLDER_FIRST_NOTE_HZ) \
			+ _placeholder_note(time - PLACEHOLDER_NOTE_DELAY, PLACEHOLDER_SECOND_NOTE_HZ)
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = PLACEHOLDER_SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


# PLACEHOLDER: uma nota senoidal com ataque curto (sem o estalo do começo abrupto) e decaimento
# exponencial. Fora da janela da nota devolve silêncio.
func _placeholder_note(time: float, frequency: float) -> float:
	if time < 0.0 or time > PLACEHOLDER_NOTE_LENGTH:
		return 0.0
	var attack: float = minf(time / PLACEHOLDER_ATTACK, 1.0)
	return sin(TAU * frequency * time) * exp(-time * PLACEHOLDER_DECAY) * attack * PLACEHOLDER_PEAK
