# Build Windows automatizado

O script `scripts/build-windows.bat` compila as quatro configurações já
declaradas em `vc18/otclient.sln`, em sequência:

| Configuração | Plataforma | Executável |
| --- | --- | --- |
| OpenGL | x64 | `otclient_gl_x64.exe` |
| DirectX/ANGLE | x64 | `otclient_dx_x64.exe` |
| OpenGL | x86 | `otclient_gl.exe` |
| DirectX/ANGLE | x86 | `otclient_dx.exe` |

O pacote `windows-x64` recebe OpenGL por padrão e usa o caminho
`bin/elemental.exe`, compatível com o feed atual do launcher. Para escolher
DirectX/ANGLE nesse alvo, defina `ELEMENTAL_WINDOWS_RENDERER=DirectX`. As outras
três variantes vão para `windows-variants/` para teste manual. O manifesto do
launcher ainda publica um único alvo Windows x64; as variantes x86 não são
selecionadas pelo launcher.

## Preparar uma VM nova

Instale o Windows na VM uma vez e clone o checkout `otclient-next` dentro do
disco virtual. Abra um Prompt de Comando nessa cópia e execute:

```bat
scripts\setup-windows-build.bat
```

Na primeira execução, o script baixa o instalador oficial do Visual Studio
Build Tools 2026, confere a assinatura Authenticode da Microsoft e instala
MSVC x86/x64, MSBuild e Windows SDK pela configuração versionada em
`scripts/windows-build.vsconfig`. O instalador pode solicitar permissão de
administrador e reinicialização. Depois, o script chama
`build-windows.bat`, que baixa e inicializa o vcpkg se necessário e compila as
quatro variantes. Em execuções seguintes, ele detecta as ferramentas instaladas
e segue direto ao build. Git for Windows é requisito porque o checkout e o
bootstrap do vcpkg usam Git.

Esse fluxo prepara as ferramentas dentro de uma VM Windows existente; não
cria a VM, instala o Windows nem configura o hipervisor. A instalação do Windows
e o primeiro acesso à VM continuam sendo uma etapa única manual.

## Requisitos

Use Windows 11 64-bit com virtualização habilitada e espaço livre para Windows,
Build Tools, dependências do vcpkg, checkout e saídas dos quatro pacotes. A
Microsoft lista 64 GB como requisito mínimo de armazenamento para uma VM
Windows 11 e 20–50 GB livres como típico para Visual Studio 2026; isso não é uma
soma fixa de espaço usado, mas mostra que 100 GB pode ficar apertado depois de
adicionar checkout, cache e pacotes. Para uma VM de build que mantenha esses
arquivos, reserve aproximadamente 150–200 GB. Se só houver um SSD de 100 GB,
use uma instalação mínima do Build Tools e transfira a saída para uma pasta
compartilhada do host, sem guardar builds antigos na VM. Consulte os
[requisitos do Windows 11](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements)
e os [requisitos do Visual Studio 2026](https://learn.microsoft.com/en-US/VisualStudio/releases/2026/VS-system-requirements)
antes de provisionar o disco.

A solução compila em sequência com no máximo dois jobs do MSBuild para limitar
o uso de memória.

Use uma cópia do checkout dentro do disco virtual dedicado à compilação. A
solução guarda objetos e dependências compiladas junto ao checkout em
`vc18/` e `vcpkg_installed/`; o vcpkg também mantém seus pacotes no diretório
apontado por `VCPKG_ROOT`. Uma pasta compartilhada do host pode funcionar para
artefatos finais, mas fica sujeita à velocidade do hipervisor e do
compartilhamento. Prefira compilar dentro da VM e transferir apenas o resultado.

## Execução

No Prompt de Comando, a partir do checkout:

```bat
set "ELEMENTAL_VCPKG_ROOT=D:\ElementalBuild\vcpkg"
set "ELEMENTAL_WINDOWS_OUTPUT=D:\ElementalBuild\artifacts"
scripts\build-windows.bat
```

Para colocar DirectX/ANGLE no alvo distribuído pelo launcher:

```bat
set "ELEMENTAL_WINDOWS_RENDERER=DirectX"
scripts\build-windows.bat
```

Essas variáveis valem apenas para a janela atual do Prompt de Comando. Se não
forem definidas, o vcpkg fica em `%LOCALAPPDATA%\Elemental\vcpkg` e os pacotes
finais em `.builds\windows\<data-hora>` dentro do checkout.

Cada execução cria uma pasta nova, preserva builds anteriores e registra um
log por configuração. A estrutura gerada é:

```text
<data-hora>/
├── logs/
├── source-commit.txt
├── windows-x64/                    # pacote completo para o feed do launcher
└── windows-variants/
    ├── directx-x64/ ou opengl-x64/ # alternativa x64 ao renderer selecionado
    ├── directx-x86/
    └── opengl-x86/
```

Copie `windows-x64/` para `artifacts/windows-x64/` usado por
`elemental-launcher/scripts/publish-release.sh`. Para a atualização incremental
de sprites e sons, prepare também `artifacts/client-assets/<versão>/`; o feed
separa esses arquivos do pacote desktop. As variantes em `windows-variants/`
são pacotes completos de validação manual e não entram no manifesto atual do
launcher.

## Limite de validação

O script verifica ferramentas, resultado do MSBuild e executáveis antes de
preparar os pacotes. A validação do renderer e da execução real ainda precisa
ser feita no Windows; compilar em uma VM sem aceleração gráfica não comprova
compatibilidade com drivers nem desempenho no computador dos colaboradores.
