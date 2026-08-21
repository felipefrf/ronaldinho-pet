# Plano executivo — Ronaldinho Pet

## Objetivo

Entregar um companion macOS portátil que reage ao Codex App, Codex CLI, Claude
Desktop e Claude Code quando cada host disponibilizar hooks, sem perder estados
quando várias sessões terminam ou trabalham ao mesmo tempo.

Instalação alvo do código-fonte:

```sh
git clone <repo>
cd ronaldinho-pet
./install.sh
```

O instalador deve ser repetível, preservar configurações existentes e não conter
caminhos da máquina do autor.

Essa modalidade requer Xcode Command Line Tools. Instalação de um clique sem esse
pré-requisito só será anunciada com binário universal assinado e notarizado.

## Decisões de implementação

### 1. Um app e um helper

- Renomear `RonaldinhoClaudePet.app` para `RonaldinhoPet.app`.
- Instalar app, scripts e estado em
  `~/Library/Application Support/RonaldinhoPet/`.
- Usar apenas Swift, shell e APIs nativas do macOS. Nenhuma dependência externa.
- Manter uma única instância do app aberta.

### 2. Estado por sessão, sem banco

Cada snapshot usa schema versionado com `source`, `session_id`, `turn`, `revision`,
`event_id`, `event`, `state`, mensagem, origem de UI, terminal, `received_at` e
`last_activity_at`. O helper valida o ID, adquire lock por sessão, aplica a
transição, incrementa `revision` e substitui atomicamente um arquivo em `sessions/`.

A identidade canônica é sempre `(source, session_id)`. Nome de snapshot, lock,
ack e GC usam SHA-256 dessa chave, nunca o ID cru. Fontes diferentes com o mesmo
`session_id` permanecem isoladas.

- `UserPromptSubmit` inicia novo `turn` e permite voltar a `running`.
- Atividade mantém `running`, mas não reabre turno concluído.
- Pedido de input muda o turno atual para `waiting`.
- `Stop`/falha conclui o turno. O helper cria `event_id` determinístico a partir
  de `(source, session_id, turn, evento terminal)`; retry idêntico não ressuscita
  unread nem cria nova conclusão.

Todos os hooks do pet serão síncronos e curtos. O contrato do Claude documenta que
hooks bloqueiam por padrão e que `UserPromptSubmit` e `Stop` ocorrem uma vez por
turno; assim o próximo prompt não pode ultrapassar o `Stop` anterior. Não usaremos
`async: true`. Um teste de dois turnos verifica `Stop(N)` antes de `Prompt(N+1)` e
o adaptador rejeita payload sem `session_id`. Hosts sem essa garantia ficam sem
suporte; PID do hook não será usado como falsa correlação.

Ack não reescreve snapshot: grava marker atômico separado com `session_id`, `turn`
e `event_id`. Um clique antigo não consegue apagar um novo `Stop` concorrente.

O app agrega os arquivos com esta prioridade:

1. sessão aguardando aprovação/input;
2. falha não reconhecida;
3. qualquer sessão rodando;
4. conclusões não reconhecidas;
5. idle.

Consequências desejadas:

- dois `Stop` simultâneos permanecem como duas conclusões;
- um `Stop` nunca esconde outra sessão ainda rodando;
- reconhecer uma conclusão não reconhece as demais;
- `running` silencioso vira `stale/unknown` após prazo configurável; timeout nunca
  declara conclusão nem apaga o registro;
- atividade comum não reabre um turno terminal; somente novo prompt abre turno.

O app mostra o estado prioritário e a contagem de conclusões/falhas pendentes. O
clique reconhece apenas o `event_id` exibido. GC de terminais é separado e
limitado a 200 registros; por padrão remove apenas terminais/stale com mais de 30
dias, nunca `running`/`waiting` ativos. JSON corrompido ou de versão futura é
ignorado com diagnóstico.

Arquivos por sessão são suficientes para o volume local e evitam SQLite, daemon,
socket e migrações.

### 3. Adaptadores finos por host

- Claude Code: hooks em `~/.claude/settings.json`, lendo JSON por stdin.
- Codex CLI: hooks em `~/.codex/hooks.json`; `notify` só será tocado se smoke test
  provar que hooks não cobrem o final e seu contrato estiver conhecido.
- Claude Desktop e Codex App só reutilizam adaptadores depois de smoke test provar
  hooks compartilhados e ID estável.
- O payload real será preservado em testes de fixture sem dados pessoais.
- Sem `session_id` estável, o adaptador diagnostica e não altera o pet.

| Host | Configuração | Payload/ID | Status inicial |
|---|---|---|---|
| Claude Code | `~/.claude/settings.json` | `session_id`; fixture local pendente | contrato oficial confirmado |
| Claude Desktop | mesma config/runtime | `session_id`; fixture local pendente | contrato oficial confirmado |
| Codex CLI | `~/.codex/hooks.json` | fixture real pendente | UNVERIFIED |
| Codex App companion | compartilhamento a provar | fixture real pendente | UNVERIFIED |
| Codex App pet nativo | `~/.codex/pets` | n/a | UNVERIFIED neste repositório |

A referência oficial do Claude confirma que os mesmos hooks disparam no terminal,
IDE e Desktop; stdin contém `session_id`, e hooks síncronos bloqueiam a execução.
Antes de habilitar a configuração no instalador, fixtures anonimizadas de
`SessionStart`, `UserPromptSubmit`, `PermissionRequest`/`Notification`, `Stop`,
`StopFailure` e `SessionEnd` serão exercitadas no parser. O smoke real decide PASS.

### 4. Clique e foco

- Guardar `TERM_PROGRAM`/bundle id quando houver terminal.
- Ao clicar, agir sobre o registro exibido; `waiting` apenas foca, enquanto
  falha/conclusão reconhece somente seu `event_id`.
- Na primeira versão, focar o aplicativo correto. Foco exato da aba/janela será
  adicionado somente se os payloads permitirem fazê-lo sem automação frágil por
  terminal.
- Para eventos originados nos apps desktop, focar Codex ou Claude pelo bundle id.

### 5. Pet nativo do Codex App

Depois de validar o agregador, instalar `pet.json` e `spritesheet.webp` em
`~/.codex/pets/ronaldinho-gaucho/` para quem quiser usar também o renderizador
nativo do Codex. O instalador não altera a seleção atual do usuário.

## Instalador seguro e portátil

`install.sh` deverá:

1. validar macOS/versão, `swiftc`, asset e direito de redistribuição sem mutação;
2. montar e validar toda a instalação em diretório temporário;
3. calcular o merge e fazer backup somente quando a configuração mudar;
4. instalar usando `$HOME`, nunca caminhos absolutos gravados no repositório;
5. gerar quoting seguro e reconhecer ownership por igualdade exata das entradas
   geradas, nunca substring;
6. preservar hooks, plugins, permissões e `notify` existentes;
7. preservar mode/owner dos settings; fazer backup do app/scripts/config atuais,
   aplicar o conjunto e restaurar todo o conjunto se qualquer escrita falhar;
8. rerun byte-estável, sem duplicata nem backup em no-op;
9. substituir o app inteiro, sem arquivos obsoletos;
10. imprimir o que instalou e qualquer passo manual restante.

Também haverá `uninstall.sh`, removendo somente arquivos e entradas pertencentes
ao Ronaldinho e preservando todo o restante.

O commit termina após app, scripts e configs serem gravados e validados. Abrir o
app ocorre depois e uma falha de launch é reportada sem fingir rollback da
instalação já válida.

O instalador detecta `~/.claude/ronaldinho-pet`, remove somente hooks antigos
exatamente reconhecidos e preserva backup do estado. Config inválida, symlink
inesperado ou permissão insegura falha antes de mutar.

## Verificação mínima obrigatória

Helper, app e configurador recebem uma raiz explícita injetável para teste; produção
usa `~/Library/Application Support/RonaldinhoPet`. Um `./test.sh` usa essa raiz e
`$HOME` temporários, instala sentinelas na home real e falha se qualquer arquivo
escapar. Ele deve:

- Compilar o app e helpers do zero.
- Validar que o repositório não contém `/Users/<nome>`, segredos ou artefatos de
  build.
- Instalar duas vezes e provar resultado idêntico, sem duplicata/backup no no-op.
- Preservar configurações sintéticas contendo hooks desconhecidos.
- Testar HOME com espaço, config inválida sem mutação e rollback injetado.
- Simular duas sessões concluindo simultaneamente.
- Simular o mesmo `session_id` em duas fontes e provar isolamento.
- Simular uma sessão concluindo enquanto outra continua rodando.
- Simular atividade atrasada tentando reabrir turno terminado.
- Simular ack concorrente com novo `Stop` e reconhecer uma conclusão sem apagar outra.
- Disparar 100 updates concorrentes; testar duplicata, JSON corrompido/versão
  futura, stale, GC, duas partidas do app e uninstall preservando desconhecidos.
- Executar um smoke test real em cada host disponível nesta máquina; marcar como
  não verificado qualquer host que não possa ser exercitado.

## Ordem de execução

1. Materializar schema/transições e `test.sh`; capturar fixtures anonimizadas.
2. Generalizar nomes/diretórios e implementar helper por sessão, ack markers e
   funções puras de seleção.
3. Entregar primeiro Claude Code e instalador transacional.
4. Adicionar cada host somente após seu smoke preencher a matriz.
5. Consolidar uninstall, migração e, por último, pet nativo do Codex.
6. Documentar apenas suporte comprovado, pré-requisitos e limitações.

## Fora do primeiro release

- servidor, telemetria, conta, sincronização em nuvem ou suporte não-macOS;
- banco de dados;
- automação por Accessibility para localizar abas específicas;
- binário assinado/notarizado no release de código-fonte; será etapa própria antes
  de anunciar instalação de um clique.

## Critério de pronto

Uma pessoa em outro Mac com Command Line Tools consegue executar o `./install.sh`
da raiz, preservar configurações e ver um único Ronaldinho agregando sessões. Cada
host anunciado está PASS; UNVERIFIED não aparece como suportado no README.

Antes de publicar o spritesheet, o responsável confirma o direito de redistribuí-lo
e define as licenças do código e do asset. Isso bloqueia publicação, não o
desenvolvimento local do núcleo.
