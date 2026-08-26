# HopeFarm

Jogo em **Godot 4.7** (GL Compatibility, GDScript).

## Arquitetura

Os sistemas conversam por um **Event Bus**: um Singleton (`EventBus`) onde quem faz algo anuncia o fato e
quem se interessa escuta, sem que os dois se conheçam.

Todos os eventos do jogo ficam em [`autoload/EventBus.gd`](autoload/EventBus.gd), cada um com um comentário
dizendo quem emite e quem escuta.

📖 **[Guia do Event Bus](docs/event_bus.md)** — como criar, emitir e escutar um evento, e como depurar.

> Esta branch (`2.1(DEBUG)-teste-event-bus`) inclui uma camada de validação: sistemas mínimos, uma cena de
> playground e um verificador de fluxo. Serve para exercitar o bus e ensinar o padrão — não é design de
> gameplay.

## Debug

`scenes/dev/EventBusPlayground.tscn` permite iniciar produção, coletar, avançar dias e vender com botões.
**F3** abre o overlay do Event Bus: emissões por frame, eventos mais emitidos, eventos que ninguém escutou e
histórico das últimas emissões.

Para conferir o fluxo sem abrir o editor:

```bash
godot --headless --path . res://scenes/dev/SmokeTestEventBus.tscn
```
