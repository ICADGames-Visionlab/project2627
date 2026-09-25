# DialoguePlaceholderAudio.gd — Sons provisórios para as pistas do DialogueStyle que ainda não têm
# arquivo (SPEC §16 Fase 5). Mesma técnica do InsightAudio (nota sintetizada em código, cacheada),
# só com uma função de síntese só, parametrizada por pista, para dar uma assinatura própria a cada
# uma sem repetir a rotina cinco vezes. Some sozinho no dia em que o som final entrar no Inspector.
class_name DialoguePlaceholderAudio
extends RefCounted

const SAMPLE_RATE: int = 22050
const ATTACK: float = 0.004

static var _cache: Dictionary = {}   # StringName -> AudioStreamWAV


static func open() -> AudioStreamWAV:
	return _cached(&"open", 440.0, 880.0, 0.14, 10.0, 0.3)


static func close() -> AudioStreamWAV:
	return _cached(&"close", 660.0, 330.0, 0.14, 10.0, 0.3)


static func new_line() -> AudioStreamWAV:
	return _cached(&"new_line", 523.25, 523.25, 0.05, 20.0, 0.16)


static func confirm() -> AudioStreamWAV:
	return _cached(&"confirm", 784.0, 1046.5, 0.09, 16.0, 0.3)


static func hover() -> AudioStreamWAV:
	return _cached(&"hover", 987.77, 987.77, 0.025, 34.0, 0.12)


static func _cached(key: StringName, start_hz: float, end_hz: float, length: float, decay: float, peak: float) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = _build_tone(start_hz, end_hz, length, decay, peak)
	return _cache[key]


# Nota única com glide linear de frequência (start_hz -> end_hz, iguais para um tom parado), ataque
# curto e decaimento exponencial — a mesma receita de sempre (ver InsightAudio._placeholder_note).
static func _build_tone(start_hz: float, end_hz: float, length: float, decay: float, peak: float) -> AudioStreamWAV:
	var frame_count: int = int(length * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frame_count * 2)
	var phase: float = 0.0
	for frame: int in frame_count:
		var time: float = float(frame) / float(SAMPLE_RATE)
		var frequency: float = lerpf(start_hz, end_hz, time / length) if length > 0.0 else start_hz
		phase += frequency / float(SAMPLE_RATE)
		var attack: float = minf(time / ATTACK, 1.0)
		var sample: float = sin(TAU * phase) * exp(-time * decay) * attack * peak
		data.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
