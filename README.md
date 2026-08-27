# Ghost

HUD flutuante para o League of Legends: aceita a partida automaticamente e troca seu status entre Online, Ausente e Offline sem sair do cliente.

![A HUD do Ghost](ghost.png)

> Projeto não oficial, sem vínculo com a Riot Games.

## O que faz

- Aceita o ready check sozinho, com atraso configurável
- Status do chat em um clique — incluindo *aparecer offline*, que o cliente não oferece
- **Offline fixado**: entrar em partida faz o cliente te tirar do offline sozinho. Enquanto o botão mostra `Offline ✓`, o Ghost devolve. Escolher Online ou Ausente solta
- Atalhos globais: `Ctrl+Alt+A` (auto-aceitar) e `Ctrl+Alt+O` (offline/online)
- **Auto-pick e auto-ban**: você monta as filas numa grade com os ícones do próprio cliente, e na sua vez o Ghost pega o primeiro que ainda estiver livre
- **Tela de abertura**: você marca quais automações quer usar e a HUD sobe só com elas
- **Runa automática**: travou o campeão, o Ghost busca a runa mais jogada dele naquela lane no op.gg e grava na sua página `Ghost`
- **Aviso de autofill**: caiu numa lane que você não pediu, o Ghost para o auto-pick em vez de travar um campeão que não joga ali
- Mostra em que ponto o cliente está: fora de fila, na fila, seleção de campeão, em partida
- Janela sem borda, arrastável, sempre por cima — e ela reabre onde você deixou, com o auto-aceitar como estava

Um script PowerShell. Sem instalação, sem dependência externa. Uma instância por vez.

## Usar

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ghost.ps1
```

| Parâmetro | Padrão | |
|---|---|---|
| `-IntervaloMs` | `700` | Frequência da checagem |
| `-AtrasoSegundos` | `0` | Espera antes de aceitar, com contagem na HUD |
| `-AutoAceitarLigado` | off | Já abre ativo |
| `-SegundosAteTravar` | `18` | Tempo com o campeão marcado antes de travar. `0` = instalock |
| `-Direto` | off | Pula a tela de abertura e usa o que ficou salvo |
| `-Runas` | on | Grava a runa do campeão travado na página `Ghost` |
| `-IgnorarAutofill` | off | Escolhe em qualquer lane, mesmo numa que você não pediu |
| `-Simular` | off | Escreve no log o que faria na seleção, sem tocar nela |

Ou clique no `ghost.bat`.

Preferências ficam em `%APPDATA%\Ghost\ghost.json` — apagar o arquivo volta tudo ao padrão. Os ícones dos campeões ficam em `%APPDATA%\Ghost\icones\` (~6 MB, baixados uma vez do próprio cliente).

Ícone: `ghost-gerar-icone.ps1`. Versão só de console: `lol-auto-accept.ps1`.

## Escolher e banir

O botão **Campeões** abre uma grade com os 173 campeões, usando os ícones que o cliente já tem em disco. Clique escolhe, clique direito bane, clique na fila tira de lá. A ordem da fila é a ordem de preferência.

Na sua vez, o Ghost pega o primeiro da fila que ainda estiver livre — pulando quem já foi banido, já foi escolhido, ou está marcado por um aliado.

O ban sai direto. O pick **marca o campeão e trava depois**, não de imediato: marcar avisa o time o que você vai pegar, e até travar dá tempo de mudar de ideia na mão. `-SegundosAteTravar 0` volta ao instalock.

Os botões `Pick` e `Ban` na HUD ligam cada um. Ficam **âmbar** quando estão ligados com a fila vazia — ligado sem fila não faz nada, e verde ali prometeria uma automação que não vai acontecer.

> Rode com `-Simular` na primeira partida. Ele escreve no log o que faria, sem tocar na seleção.

## Escolher o que aparece

O Ghost começou fazendo uma coisa — aceitar partida — e hoje faz cinco. Ninguém usa as cinco. Quem só quer aparecer offline não tem por que olhar para uma faixa de auto-pick apagada em toda partida.

Então ele pergunta antes de subir. Você marca o que quer, aperta OK, e a HUD aparece só com aquilo — **a altura da janela é resultado do que ficou ligado**, não um número fixo. Marcando só status e auto-aceitar, ela fica com pouco mais de um terço do tamanho cheio.

A escolha fica salva no `ghost.json`. **Clique direito na barra do topo** reabre a tela quando quiser mudar. `-Direto` pula a pergunta e usa o que estava salvo — é o que você põe no atalho depois de decidir.

Desmarcar ali não é só esconder o botão: **desliga a automação junto**. Um recurso invisível que continuasse agindo por trás seria pior do que deixá-lo à vista ou tirá-lo de vez.

O `_` ao lado do `X` minimiza para a barra de tarefas — a janela não tem barra de título própria para isso.

## Runa automática

Travou o campeão — no automático ou escolhendo na mão —, o Ghost pega a lane que você recebeu, busca no op.gg a runa mais jogada daquele campeão nela, grava na sua página e seleciona.

**Antes de usar, renomeie uma das suas páginas de runa para `Ghost`.** Ele só escreve numa página cujo nome comece com isso. Não achou, não faz nada e avisa no log. Essa é a regra que impede um bug aqui de comer uma página que você montou à mão.

E ele **edita a página no lugar** (`PUT`), nunca apaga e recria — apagar dando certo e recriar falhando te deixaria com um slot a menos.

A página fica com o nome `Ghost Runa <Campeão>`.

### De onde vem a runa

Do op.gg, e isso tem um custo que vale dizer em voz alta: **não é API pública, é raspagem**. O dia que eles mudarem a estrutura da página, quebra. E o Ghost, que até aqui não dependia de nada externo, passa a precisar de internet.

Por isso existe a queda: op.gg fora do ar, campeão sem página lá, ou modo sem lane (cega, ARAM) e ele usa a **recomendação da própria Riot**, servida pelo cliente. Não é a build de maior winrate, mas funciona offline e não quebra. O recurso piora em vez de parar.

O log sempre diz qual das duas foi usada.

Os 173 campeões funcionam, inclusive os quatro cujo apelido interno da Riot não bate com o nome — `MonkeyKing` para Wukong, `Nunu`, `Renata` e `Bard`. O op.gg aceita todos eles; foram testados um a um.

### Nada entra sem conferir

O cliente **não valida id de runa**: mandei `1,2,3` e ele gravou `1,2,3,-1,-1,-1` sem reclamar. Quem tem que barrar lixo é o Ghost. Toda runa passa por uma checagem de faixa — estilo entre 8000 e 8500, runa comum de 4 dígitos, fragmento entre 5001 e 5011 — antes de chegar perto da sua página. A conferência acontece duas vezes: na leitura de cada fonte e de novo na hora de gravar, que é a única função que escreve na sua conta.

### Por que a busca roda em outro processo

As chamadas HTTP do Ghost acontecem na thread da interface. Para resposta local de 2 KB isso não custa nada. A página do op.gg tem ~640 KB e vem de fora: baixar ali congelaria a HUD no meio da seleção de campeão, que é justo quando ela precisa responder. Então o `curl` sai num processo separado e o resultado é colhido num tick seguinte. Medido aqui: ~0,6s por busca, sem travar nada.

## Quando o autofill te pega

A fila de pick é uma só e não sabe de lane. Montada pensando em mid, ela vira um problema no segundo em que o cliente te joga de suporte: sem checagem nenhuma, o Ghost travaria o primeiro da fila do mesmo jeito, com você olhando.

Então ele compara a lane atribuída com as que você pediu. Se não bater, o auto-pick **para**: o botão `Pick` fica âmbar e o log diz qual lane veio. Você escolhe na mão, que é o certo a fazer ali.

O gate só bloqueia quando tem certeza. Ele **libera** quando não existe lane atribuída (cega, ARAM), quando você pediu fill, e quando não conseguiu ler sua preferência no lobby. Falhar liberando mantém o comportamento antigo; falhar bloqueando tiraria seu pick no meio da seleção, sem motivo visível.

O **ban não passa pelo gate** — banir campeão não depende da sua lane.

As lanes pedidas são lidas do lobby enquanto você está nele, porque no champ select o lobby já não existe. Os nomes desses campos na LCU não são documentados e já mudaram entre versões do cliente, então o Ghost tenta mais de um e escreve no log o que leu — se aparecer `Lanes pedidas: ...` com o que você escolheu, está lendo certo.

> Ainda não foi testado contra o cliente rodando. Rode uma partida com `-Simular` antes de confiar nele.

## Como funciona

O cliente do LoL expõe uma API REST local — a **LCU API** — em `https://127.0.0.1:<porta>`. A interface do jogo é um app web que fala com ela, então todo botão da tela é uma chamada HTTP. O Ghost usa os mesmos endpoints:

| Endpoint | |
|---|---|
| `GET /lol-matchmaking/v1/ready-check` | tem partida? |
| `POST /lol-matchmaking/v1/ready-check/accept` | aceitar |
| `GET` / `PUT /lol-chat/v1/me` | ler e trocar o status |
| `GET /lol-gameflow/v1/gameflow-phase` | em que ponto o cliente está |
| `GET /lol-lobby/v2/lobby` | as lanes que você pediu |
| `GET /lol-perks/v1/pages` | suas páginas de runa |
| `PUT /lol-perks/v1/pages/<id>` | grava a runa na página |
| `PUT /lol-perks/v1/currentpage` | seleciona a página |
| `GET /lol-perks/v1/recommended-pages/...` | a runa que a Riot sugere |
| `GET /lol-champ-select/v1/session` | de quem é a vez, e do quê |
| `PATCH /lol-champ-select/v1/session/actions/<id>` | escolher ou banir |
| `GET /lol-game-data/assets/v1/champion-summary.json` | lista de campeões |
| `GET /lol-game-data/assets/v1/champion-icons/<id>.png` | os ícones |

Porta e senha saem do `lockfile` que o cliente grava na pasta de instalação (`LeagueClient:PID:PORTA:SENHA:https`), com senha nova a cada abertura. Nada de leitura de memória, clique simulado ou detecção de pixel.

## Testes

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .	estesodar.ps1
```

Três arquivos: o gate de autofill, o layout da HUD e as runas. Eles **recortam as funções de dentro do `ghost.ps1`** em vez de duplicar código — o script é um arquivo só, com janela e loop no nível de cima, então dot-source abriria a HUD. Assim não existe cópia para sair de sincronia.

O de runas precisa de internet (busca de verdade no op.gg). Nenhum deles abre janela, e nenhum escreve na sua conta.

Eles já pagaram o próprio custo: acharam a barra invertida engolida pelo curl e o fato de o cliente aceitar id de runa inventado.

## Decisões técnicas

**`curl.exe` no lugar de `Invoke-RestMethod`** — a LCU exige TLS 1.3, que o .NET Framework não fecha. O sintoma é um "conexão subjacente fechada" que não diz nada.

**Corpo JSON por arquivo (`-d @arquivo`)** — passar aspas por linha de comando atravessa dois analisadores e chega corrompido; a LCU responde 400.

**`RegisterHotKey` em vez de hook de teclado** — o hook veria tudo que você digita. O Ghost só é avisado da combinação registrada.

**`.ico` todo em BMP** — o `System.Drawing.Icon` do .NET Framework não lê entrada PNG dentro de `.ico`.

**A fase do cliente define o ritmo da checagem** — em seleção de campeão, em partida ou na tela de fim não existe ready check para pegar, e essas são justo as fases longas. Nelas a checagem cai de `-IntervaloMs` para um tick a cada ~3s — a HUD mostra o intervalo exato, que com os 700ms padrão dá 2,8s, porque a conta arredonda em ticks inteiros. Dentro do jogo, que é onde CPU importa, isso corta a maior parte dos processos de `curl`. Fase desconhecida mantém o ritmo rápido: checar demais custa CPU, checar de menos perde a partida.

**Barra normal no caminho de saída do `curl -K`** — os 173 ícones vêm numa chamada só, com a lista de pares url/arquivo num arquivo de configuração (`-K`), porque na linha de comando ela passaria de 22 mil caracteres. Dentro de aspas nesse arquivo o `curl` trata `\` como início de escape: com `C:\Users\...` ele grava **zero** arquivos e sai calado. Com `C:/Users/...`, os 173. A API de arquivo do Windows aceita as duas.

**Nada de `$c` como variável de laço** — nome de variável no PowerShell não diferencia maiúscula de minúscula, e o escopo é dinâmico: uma função lê o local de quem a chamou. Um `foreach ($c in ...)` apaga a tabela de cores `$C` para tudo que for chamado dali para baixo, e `$C.Verde` vira `$null` sem aviso.

**Nada de closure em evento do WinForms** — o scriptblock de um evento dispara da fila de mensagens, muito depois de a função que o criou ter saído de cena. Tudo que os handlers precisam mora em escopo de script, e eles falam por nome de função. De quem veio o clique sai do próprio controle (`$s.Tag`, `$s.Parent`), não de variável capturada.

**Toda ação de botão passa por um `try`** — exceção dentro de um handler do WinForms não aparece em lugar nenhum: o console está escondido e o WinForms engole. O sintoma é a HUD parada numa linha de log antiga, sem nada explicando. Agora o erro fica na linha de log e em `%APPDATA%\Ghost\erro.txt`.

**O `-AtrasoSegundos` conta pelo relógio, não com `Start-Sleep`** — tudo roda na thread da interface, então dormir ali congelaria a HUD e os atalhos globais justo nos segundos que importam. Do jeito atual a contagem aparece na tela e dá para cancelar desligando o auto-aceitar no meio dela.

## Ícone

`ghost-gerar-icone.ps1` extrai o ícone do `LeagueClient.exe` instalado na sua máquina e aplica escala de cinza na metade esquerda.

O `.ico` gerado **não está no repositório** (veja o `.gitignore`): ele deriva de arte da Riot, e redistribuir asset é diferente de usar localmente. O repositório traz a receita, não o resultado. Sem o ícone o Ghost roda igual.

## Aviso

Automação de cliente é área cinzenta nos termos da Riot. O Ghost usa só a API local que o próprio cliente expõe — mesma abordagem de Blitz e Mobalytics — e não toca em memória nem em gameplay. Ainda assim é automação. Use por sua conta.

**Auto-pick e auto-ban pesam mais que o auto-aceitar**, e vale saber por quê. Aceitar a partida sozinho só afeta você. Escolher e banir sozinho age dentro da seleção, que é compartilhada com mais nove pessoas: um ban automático pode derrubar o campeão que um aliado ia pegar, e um pick automático decide a composição do time sem olhar para ela. É por isso que o padrão marca o campeão e só trava depois de `-SegundosAteTravar` — dá tempo de você intervir. Instalock é uma opção, não o padrão.

## Sobre

Escrito com assistência de IA (Claude). As decisões técnicas acima são as que orientaram o código, e estão comentadas dentro de cada script.

## Licença

MIT — veja [LICENSE](LICENSE).
