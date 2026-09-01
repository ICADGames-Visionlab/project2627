#Feito pelo Enzo com uso do Claude

# AudioManager

Autoload (singleton) responsável por centralizar todo o áudio do jogo:
volume dos buses, tocar SFX/música e persistir a preferência de volume
em disco. Qualquer outro script pode chamá-lo diretamente, sem precisar
de referência (`AudioManager.tocar_sfx(...)`).

Script: `res://scripts/singletons/audio_manager.gd`

## Configuração inicial

1. Salve `audio_manager.gd` em `res://scripts/singletons/` (mesma pasta do EventBus).
2. Vá em **Project > Project Settings > Autoload**.
3. Em **Path**, aponte para o arquivo. Em **Node Name**, use exatamente `AudioManager`.
4. Clique em **Add**.

Não adicione `class_name AudioManager` neste script — o nome do Autoload
já cria essa referência global, e ter os dois juntos causa conflito de nome.

Sem esse registro, `AudioManager` não existe globalmente e qualquer
chamada tipo `AudioManager.tocar_sfx(...)` vai dar erro de identificador
não encontrado.

## Quando usar

- Qualquer som avulso do jogo (clique de UI, passo, tiro, colisão) → `tocar_sfx()`.
- Trocar ou parar a música de fundo → `tocar_musica()` / `parar_musica()`.
- Ler ou alterar o volume geral do jogo (ex: pelo SettingsManager) → `volume_geral` / `set_volume_geral()`.
- Qualquer cena que precise "lembrar" o volume entre telas ou entre sessões do jogo.

## Quando não usar

- Para áudio posicional 3D com atenuação por distância, o ideal é usar
  `AudioStreamPlayer2D`/`3D` direto no objeto da cena — o AudioManager
  cuida do volume geral, não substitui isso.
- Não é lugar para lógica de gameplay (pontuação, física, etc.) — só áudio.

## API pública

| Membro | Descrição |
|---|---|
| `volume_geral: float` | Volume geral atual (0.0 a 1.0), já refletido no bus Master. |
| `set_volume_geral(valor)` | Define o volume geral e salva a preferência no disco. |
| `tocar_sfx(stream, volume_db = 0.0)` | Toca um efeito sonoro avulso, sem cortar outros já tocando (pool de 8 players). |
| `tocar_musica(stream)` | Troca a música de fundo. Ignora se já for a música atual. |
| `parar_musica()` | Para a música de fundo. |

Loop de música depende da configuração de importação do arquivo de
áudio (não é controlado pelo AudioManager).

Preferências salvas em `user://audio_settings.cfg` (arquivo próprio,
separado do `user://settings.cfg` usado pelo SettingsManager para vídeo).

## Integração com o SettingsManager

O `SettingsManager` (cena de UI) não mexe mais no `AudioServer`
diretamente. Ele só reflete o estado do AudioManager e delega mudanças:

```gdscript
# No _ready(): mostra o valor atual
slider_geral.value = AudioManager.volume_geral

# Quando o slider muda: delega pro singleton
func _on_volume_geral_changed(valor: float) -> void:
    AudioManager.set_volume_geral(valor)
```

Isso mantém a UI "burra" (só exibe e repassa) e toda a lógica de áudio
num único lugar — inclusive para telas de configuração futuras.

## Prós e contras de ser um singleton (Autoload)

**Prós**
- Acesso global de qualquer script, sem passar referências manualmente.
- Sobrevive a trocas de cena — essencial pra música continuar tocando
  entre telas (menu → gameplay → pause).
- Fonte única de verdade: um só lugar concentra volume, SFX e persistência.
- Fácil de expandir depois (fade entre músicas, buses separados de
  Música/SFX, ducking) sem tocar no código de gameplay.

**Contras**
- Estado global: qualquer script pode chamar, o que deixa dependências
  menos explícitas e dificulta isolar/testar partes do jogo separadamente.
- Autoload nunca é destruído automaticamente — streams referenciados
  incorretamente podem ficar ocupando memória por mais tempo que o necessário.
- Tende a virar um "objeto Deus" se for acumulando responsabilidades
  que não são de áudio — vale manter o escopo dele restrito.
- Difícil ter múltiplas instâncias independentes (ex: mixers separados
  por split-screen), já que por natureza é único e global.

## Possíveis expansões futuras

- Buses separados de Música e SFX (as constantes `BUS_MUSICA`/`BUS_SFX`
  já existem no script, hoje apontando pro "Master").
- Crossfade entre músicas em `tocar_musica()`.
- Volume "duck" automático da música quando um SFX importante toca.
