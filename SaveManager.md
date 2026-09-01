# Documentação do Sistema de Save (JSON)

Este documento detalha o funcionamento do sistema de salvamento do projeto. O sistema é baseado em arquivos JSON locais e está dividido em duas partes principais: o gerenciador global (`SaveManager`) e a lógica de interface reativa.

## 1. SaveManager (Autoload)
O `SaveManager` opera como um Singleton (Autoload) e é a única classe que deve interagir diretamente com o sistema de arquivos do jogador. Todos os saves são gravados na pasta `user://` do Godot.

### Comportamento e Segurança
* **Cinto de Segurança (`default_disctionary`):** Em caso de falha de leitura ou arquivos corrompidos, o sistema retorna um dicionário vazio `{}` em vez de `null`. Isso previne crashes no momento do parse de dados em outros scripts.
* **Exclusão Física:** O sistema não limpa as variáveis do arquivo; ele deleta o arquivo físico do disco usando `DirAccess`, garantindo que não fiquem rastros de saves corrompidos ou "fantasmas".

### Métodos Disponíveis
* `save_game(data: Dictionary, current_save: String)`: Serializa o dicionário recebido para JSON e o escreve no arquivo especificado.
* `load_game(current_save: String) -> Dictionary`: Retorna o dicionário populado com os dados do save. Caso o arquivo não exista ou esteja corrompido, retorna `{}`.
* `reset_save(current_save: String)`: Remove fisicamente o arquivo do disco via `DirAccess.remove_absolute()`.
* `has_save(file_slot: String) -> bool`: Validação rápida via `FileAccess.file_exists()` para checar se o slot está em uso.

---

## 2. Lógica de Interface (Menu de Saves)
A interface de seleção de slots utiliza um sistema reativo conectado via funções anônimas (lambdas). Se precisar adicionar novos slots ou alterar o layout, siga a estrutura já implementada.

### Gerenciamento de Estado
* **Conexões Dinâmicas:** Os botões de slot e exclusão ("X") não possuem funções separadas para cada slot. Eles são conectados no `_ready()` usando lambdas: `botao.pressed.connect(func(): start_game(SaveManager.save_file_1))`.
* **Atualização Visual (`update_ui`)**: Sempre que a tela carrega ou um arquivo é deletado, o sistema varre os arquivos. Se `has_save` for verdadeiro, o botão exibe "Continuar" e o botão de exclusão é ativado. Caso contrário, exibe "Novo Jogo" e esconde o "X".
* **Inicialização (`start_game`)**: Ao selecionar um slot vazio, o script gera o dicionário base (com dados primários como `Var1`) antes de transicionar a cena e delegar o slot atual para o `GameController`.

---

## 3. Como Interagir com o Sistema no Jogo

Para os desenvolvedores que precisam salvar novos dados ou resgatar variáveis ao carregar uma fase, utilizem o fluxo abaixo interagindo com o `GameController` (que deve armazenar o slot ativo) e o `SaveManager`.

**Para Salvar o Jogo:**
Construa o estado atual em um dicionário e chame o método de salvamento.
```gdscript
func salvar_progresso():
	var dados = {
		"dinheiro": GameController.dinheiro_atual,
		"rodada": GameController.rodada_atual,
		"inventario": GameController.inventario
	}
	SaveManager.save_game(dados, GameController.currentSaveFile)
```

**Para Carregar o Jogo:**
Chame o carregamento assim que a cena principal for instanciada e distribua os valores.
GDScript
```gdscript
func _ready():
	var dados = SaveManager.load_game(GameController.currentSaveFile)
	
	if not dados.is_empty():
		GameController.dinheiro_atual = dados.get("dinheiro", 1000)
		GameController.rodada_atual = dados.get("rodada", 1)
```

Nota de Manutenção: Ao usar dados.get("chave", valor_padrao), você protege o código caso chaves novas sejam adicionadas no futuro, evitando erros ao carregar arquivos de save de versões antigas do jogo.
