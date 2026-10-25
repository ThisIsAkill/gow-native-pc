<div align="center">

# God of War — Native PC

[English](README.md) · **Português (Brasil)**

Um port nativo para PC de *God of War* (PS2, NTSC-U `SCUS-97399`), feito recompilando estaticamente o código MIPS
R5900 para C++, com launcher instalador, compilação em um clique, suporte a traduções de fãs e meta de 60 fps.

![platform](https://img.shields.io/badge/platform-Windows%20x64-0078D6)
![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus&logoColor=white)
![build](https://img.shields.io/badge/build-CMake%20%2B%20Ninja-064F8C?logo=cmake&logoColor=white)
![based on](https://img.shields.io/badge/based%20on-PS2Recomp-8A2BE2)
![status](https://img.shields.io/badge/status-experimental-orange)
![license](https://img.shields.io/badge/license-GPL--3.0-blue)

</div>

> [!IMPORTANT]
> Este repositório **não contém arquivos do jogo**. Você precisa da sua própria cópia de God of War. O runtime nativo
> (**PS2Recomp**, ampliado por Waffle565, KIexster e pelo port Tobiichi) é **obrigatório**; o launcher o baixa, ele não
> fica guardado aqui. Atribuição completa: [`CREDITS.md`](CREDITS.md).

## Conteúdo

- [O que é](#o-que-é)
- [Obrigatório: o runtime PS2Recomp](#obrigatório-o-runtime-ps2recomp)
- [Requisitos](#requisitos)
- [Como usar](#como-usar)
- [Desempenho](#desempenho)
- [Traduções e idiomas](#traduções-e-idiomas)
- [God of War II](#god-of-war-ii)
- [Estrutura](#estrutura)
- [Créditos e licença](#créditos-e-licença)

## O que é

O executável do jogo (`SCUS_973.99`) é traduzido de MIPS para C++ pelo **PS2Recomp** e compilado como um programa
Windows. O hardware do PS2 (GS, VU1, IOP, som, controle, memory card) é substituído por código nativo — não é um
emulador. Este projeto junta o trabalho de vários autores (veja [`CREDITS.md`](CREDITS.md)) num instalador único:

- **Launcher com instalação**: verifica os requisitos, **baixa o runtime PS2Recomp**, identifica sua ISO, compila o
  jogo com barra de progresso e abre o jogo — tudo na mesma janela.
- **Uma ISO basta**: a original (USA) ou uma tradução de fãs reconhecida. Com várias ISOs (ex.: a original e a
  traduzida) cada idioma fica jogável e o launcher **pergunta em qual idioma você quer jogar**.
- **Otimizado para 60 fps**: o código da VU1 e do IOP vira código nativo; enquanto você joga, o código novo é gravado
  e "Acelerar áreas visitadas" o compila.

## Obrigatório: o runtime PS2Recomp

Sem o runtime nada é recompilado nem roda. Ele **não faz parte deste repositório**: o launcher (**Instalação →
Baixar runtime**) ou o `build.cmd` o baixa em `engine/runtime/`, na versão fixada em
[`engine/runtime.toml`](engine/runtime.toml) (Tobiichi-Port, que inclui o PS2Recomp de ran-j com as extensões de
Waffle565 e KIexster), e aplica [`engine/patches`](engine/patches).

## Requisitos

| | |
|---|---|
| Sistema | Windows 10/11 64 bits |
| Processador | x86-64 com **AVX2** (Intel 2013+, AMD 2015+); 4 núcleos ou mais |
| Memória | 8 GB (16 GB recomendado para compilar) |
| Placa de vídeo | OpenGL 4.3+ |
| Disco | ~25 GB livres (disco extraído + compilação) |
| Ferramentas | [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) ("Desenvolvimento para desktop com C++"), [Git](https://git-scm.com/download/win), [Python 3](https://www.python.org/downloads/windows/) |
| Jogo | Sua ISO de **God of War (NTSC-U, SCUS-97399)** ou uma tradução reconhecida |

## Como usar

1. Baixe o launcher pronto em **Releases** (ou compile: `build.cmd -Stages launcher`).
2. Abra o launcher → aba **Instalação**:
   1. instale o que faltar em **Requisitos**;
   2. **Baixar runtime**;
   3. **Adicionar ISO…** (uma ou mais);
   4. **Instalar e compilar** — a primeira vez leva de 20 a 60 minutos, conforme o processador; com "Otimizar para
      60 fps" o jogo abre sozinho por 4 minutos no fim (não mexa).
3. **JOGAR**. Em **Outros → Idioma do jogo** você troca o idioma.

Pelo terminal: `build.cmd -Discs "D:\God of War (USA).iso"` (exemplos no [`build.cmd`](build.cmd)).

## Desempenho

O jogo é limitado a 60 quadros por design (a lógica segue o VBlank de 60 Hz do PS2). Resultados medidos e relatados
em várias máquinas, com cada combinação de código testada: [`docs/tested-hardware.md`](docs/tested-hardware.md).
A mesma configuração pode dar resultados diferentes em outra máquina — trate a tabela como referência.

## Traduções e idiomas

Traduções de fãs são reconhecidas pelo executável (`games/gow1/game.toml`, `[[editions]]`). Uma tradução que só muda
dados (textos) roda sozinha ou sobre o disco original: [`docs/translations.md`](docs/translations.md).

## God of War II

Planejado: a arquitetura é por jogo (`games/<id>/`), mas o port do GoW II ainda não existe. O que falta:
[`games/gow2/README.md`](games/gow2/README.md).

## Estrutura

```
engine/     runtime.toml (qual runtime baixar) + patches numerados (com origem e motivo em cada um)
games/      perfis por jogo: gow1 (jogável), gow2 (planejado)
launcher/   o launcher Qt 6: instalação + jogo
tools/      disc/ (identificar, extrair, preparar discos), pipeline/ (compilação)
docs/       arquitetura, hardware testado, traduções, como adicionar um jogo
data/       (gerado, fora do git) discos preparados, saves, logs, código gravado
```

Para quem for manter o código (inclusive IAs): [`AGENTS.md`](AGENTS.md).

## Créditos e licença

GPL-3.0 — veja [`LICENSE`](LICENSE). Este projeto é derivado do PS2Recomp (ran-j), do God-Of-War-Native-Port
(Waffle565), do god-of-war-recomp (KIexster) e do Tobiichi-Port (YYOzcan); a lista completa e o que veio de cada um
está em [`CREDITS.md`](CREDITS.md). God of War é marca registrada da Sony Interactive Entertainment.

Repositório: `https://github.com/<seu-usuario>/gow-native-pc`
