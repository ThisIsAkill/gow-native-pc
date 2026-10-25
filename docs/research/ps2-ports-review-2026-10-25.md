# Revisão do relatório de ports PS2 (2026-10-25)

Revisão do `ps2-ports-landscape.md` (2026-10-24) contra o estado atual: runtime fixado + `engine/patches/01`–`09`, testado
no build separado `C:\gow-build-locals`. Cada item em aberto foi investigado no código. **Nada desta revisão foi aplicado.**

Medições: Xeon E5-2666 v3 + RX 580 2048SP, roteiro automático no navio, **opções padrão do launcher** (tela cheia
1920×1080, 16:9, FXAA, 2x dinâmico, som e captura de VU1 ligados).

## Onde o tempo de cada quadro vai hoje

Traçado por quadro (`PS2X_GS_WORKER_TRACE`):
1. O EE dispara a lista de desenho do quadro (~1,77 MB).
2. O worker do VU1 a processa em **12,6–14,3 ms** (VIF1 → VU1 nativo → XGKICK → estágio do GS).
3. Em seguida o EE faz **~3 ms em série** (pequeno envio, espera do DMA, `vid::Flip`) e dispara o quadro seguinte.

Ou seja, quadro ≈ VU1 + 3 ms. O VU1 é o caminho crítico. O EE só pesa nesses 3 ms em série e em CPUs mais lentas.

| Thread | Ocupação em combate | Maiores custos |
|---|---|---|
| Worker do VU1 | ~70% | laço `runNative` e chamada indireta por bloco (~20%), corpos dos blocos nativos (~40%), timing exato do VU1 (~8%), VIF unpack (~5%) |
| Jogo (EE) | ~48% com `-Codegen locals` | funções do jogo (ex.: `sub_00162F18` 11%), **mixer de som do IOP ~14%**, despacho de chamadas ~2% |

## Situação de cada item do relatório

| Item | Situação |
|---|---|
| `movn`/`movz` 64 bits | **Feito** (patch 06) |
| Pools do runtime dentro do heap do jogo | **Feito** (patch 05, `9499406`) |
| `rand` de 31 bits, `RSQRT` | Já estavam corretos no Tobiichi |
| Correções de upscaling e Z do GoW II | **Feitas** (patch 05); imagem conferida nas capturas |
| Scratchpad DMA interleave, áudio de FMV, memory card aberto, `strtok`/`GetSystemTimeLow` | **Feitos** (patch 05) |
| `SetupThread` argc/argv (`5b1a25a`) | **Descartado**: trava o boot do GoW1 |
| `cop0_count` (`9ccffe1`) | **Em aberto, e o GoW1 precisa** (achado 1) |
| Semântica de float do PS2 (Killzone `0009`, PS2Recomp #272) | **Já coberta**: saturação, divisão por zero, comparações, `CVT.W.S`; arredondamento a zero + FTZ/DAZ na thread do jogo; divisão/raiz ao mais próximo (`ps2_runtime.cpp:2631`, `ps2_runtime_macros.h:232`) |
| GIF FLG=3 (PS2Recomp #384) | **Já coberto** (`GIF_FMT_IMAGE2` em todos os pontos) |
| Heap do IOP sem reuso (Killzone `0028`) | **Em aberto, mesmo defeito** (achado 3) |
| `/fp:fast` | Investigado (achado 6) |
| Gerador "locals" (Killzone `0017`) | **Feito, opcional** (patch 08): EE −22% |
| Despacho sem scheduler (Killzone `0023`) | Baixa prioridade: `dispatchGuestBranch` é ~2% da thread do jogo |
| VIF1/VU1/GIF em thread | Já ativo (`PS2X_GS_WORKER=1` no launcher) |
| IOP em thread própria (Killzone `0015`) | Em aberto; o custo dominante é o mixer de som (achado 2) |
| clang-cl + lld | Em aberto: LLVM não está instalado (achado 8) |
| Medir FPS pela função de quadro | **Feito** (`GOW_PERF_FRAME_PC=0x1837B8`, contador do launcher) |
| Pontos de entrada do VU1 nativo | **Feito** (patch 07 + pipeline) |
| Captura contínua do VU1 | **Feito** (patch 09): de ~15% do worker para ~0 |
| GS do PCSX2 / paraLLEl-GS, texture packs, alta taxa de quadros, decomp com difftest | Continuam válidos a longo prazo; não investigados nesta rodada |

## Achados novos (investigados no código)

### 1. O registrador `Count` da CPU está parado (fidelidade; picos de quadro ao carregar)
`sub_00185A20` lê `mfc0 Count` em `0x185AAC` e `0x185D88`. Ela monta um relógio de 64 bits e processa itens até um prazo
de `0x781EC` ciclos (~1,7 ms a 294,9 MHz). O recompilador traduz `mfc0 Count` como `ctx->cop0_count`, e **nada no runtime
atualiza esse campo**. O prazo nunca chega, e a função faz todo o trabalho pendente no mesmo quadro, em vez de ~1,7 ms
por quadro como no PS2. No GoW II, o mesmo defeito travava o carregador.
- **Correção proposta:** `mfc0 Count` passa a ler o relógio do EE (`m_eeClock.eeCycle`), via um acessor no
  `PS2Runtime` e uma linha no tradutor de COP0. O jeito do GoW II (atualizar em `accountCycles`) não serve aqui, porque o
  caminho rápido do checkpoint do Waffle avança o relógio sem passar por `accountCycles`.
- **Efeito esperado:** carregamentos e streaming distribuídos como no PS2, com menos picos de quadro ao entrar em áreas
  novas. Pode deixar carregamentos um pouco mais longos.
- **Risco:** médio, porque muda o ritmo do carregador. **Teste:** tempos de quadro em transições de área e menu → jogo.

### 2. Mixer de som do IOP: ~14% da thread do jogo com o som ligado
`SoundEngine::step` + `stepEnvelope` + `decodeBlock` rodam a cada amostra (48 kHz), para cada uma das 48 vozes, na
thread do jogo. O patch 09 já tirou a trava por amostra; o custo restante é o cálculo em si.
- **Correção proposta, em ordem de risco:**
  1. Processar por voz em blocos de amostras, em vez de "todas as vozes por amostra".
  2. Calcular o passo do envelope (shift/step) só quando a fase muda, não a cada amostra.
  3. Pular cedo as vozes silenciosas.
  4. Mover a mixagem para uma thread própria (Killzone `0015`), opção maior.
- **Verificação exata:** `GOW_AUDIO_RAW=<arquivo>` grava a saída antes da adaptação de taxa. Os itens 1–3 devem produzir
  o arquivo **idêntico byte a byte**.
- **Efeito esperado:** EE com até ~10% menos ocupação. Ajuda em CPUs mais lentas e nos ~3 ms em série por quadro.

### 3. Heap do IOP nunca reaproveita memória liberada
`IopMemory::allocate` (`ps2xIOP/src/emulator/core/iop_memory.cpp:286`) procura a partir de um cursor que só avança. O
heap vai de `0x70000` a `0x1F0000` (1,5 MB), e o `AllocSysMemory`/`Malloc` dos IRX nativos passa por ele. No Killzone isso
esgotou o heap após algumas fases, e o som dos inimigos sumiu até reiniciar.
- **Proposta:** primeiro um log de alocações e liberações numa sessão longa (troca de áreas), para confirmar se o GoW1
  chega perto do limite. Depois, a busca *first fit* desde a base (Killzone `0028`).
- **Risco:** baixo. **Efeito:** estabilidade em sessões longas.

### 4. VU1: custo por bloco nativo (o caminho crítico)
Os blocos nativos têm em média ~7 pares de instruções. Para cada um, o `runNative` paga a chamada indireta (a linha mais
cara do perfil), o histórico de timing e o despacho. Isso é ~20% do worker. Encadear blocos com sucessor conhecido
(superblocos) no `vu1n_gen.py` reduziria esse custo.
- **Verificação:** `GOW_VU1N_VERIFY=<n>` compara cada execução nativa com o motor exato.
- **Esforço:** médio/alto; mexe no gerador e no timing exato.
- **Efeito estimado:** 1–2 ms por quadro no combate, o que vira FPS diretamente.

### 5. Crescimento da captura contínua
Cada sessão grava centenas de micromemórias novas: 673 arquivos de 16 KB em 3,5 min. Hoje a pasta tem 4.140. A captura
guarda a micromemória inteira a cada combinação nova de programas carregados. O "Acelerar áreas visitadas" fica mais lento
a cada sessão, porque o gerador relê todas.
- **Proposta:** guardar só os blocos novos (pares de instruções ainda não vistos), ou deduplicar por programa.
- **Risco:** baixo. **Efeito:** builds do "Acelerar" mais rápidos e pasta menor.

### 6. `/fp:fast` no código gerado
O jogo (`ps2EntryRunner`) é compilado com `/fp:fast /arch:AVX2`. Em 6 lotes do código EE, no VU1 nativo e no runtime do
VU1, **nenhuma instrução FMA** foi emitida: o arredondamento por fusão de multiplicação e soma não acontece. O
`/fp:fast` ainda permite reordenar contas, supor que não há NaN/Inf e dobrar constantes com arredondamento ao mais
próximo, enquanto o EE roda arredondando a zero.
- **Proposta:** teste A/B com `/fp:precise` só no `ps2EntryRunner`, medindo FPS e procurando diferenças de física e
  colisão.
- **Prioridade:** baixa a média.

### 7. Despacho de chamadas (Killzone `0023`)
`dispatchGuestBranch` é ~2% da thread do jogo. Portar o despacho do Killzone exigiria adaptar o protocolo de retorno do
nosso runtime (séries de checkpoint e de salto). Pouco ganho para o risco; fica para depois.

### 8. Tempo de build
Um build completo leva 45–60 min com MSVC, e qualquer mudança em `ps2_runtime.h` ou `ps2_vu1.h` recompila tudo. O
clang-cl (LLVM) não está instalado; no Killzone ele fez o build completo em 100 s, com o obrigatório `-ffp-contract=off`.
- **Proposta:** instalar LLVM e testar um build do mesmo código com `-Codegen locals`, comparando tempo de build e FPS.

## Ordem sugerida

| # | Item | Ganho | Risco | Esforço |
|---|---|---|---|---|
| 1 | Mixer de som em blocos, verificado byte a byte (achado 2) | EE −~10% | baixo | médio |
| 2 | `Count` do EE no relógio (achado 1) | fidelidade, menos picos ao carregar | médio | baixo |
| 3 | Log do heap do IOP → reuso (achado 3) | estabilidade em sessões longas | baixo | baixo |
| 4 | Captura por blocos novos (achado 5) | "Acelerar" mais rápido | baixo | baixo/médio |
| 5 | Superblocos no VU1 nativo (achado 4) | 1–2 ms por quadro | médio | alto |
| 6 | `/fp:precise` A/B (achado 6) | correção | baixo | baixo, mas 1 build completo |
| 7 | clang-cl (achado 8) | builds em minutos | baixo | médio |

Os patches 08 e 09 continuam válidos e independentes destes itens.
