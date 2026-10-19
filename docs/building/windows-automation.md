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

## Requisitos

Instale uma vez o Visual Studio 2026 com o workload **Desktop development with
C++**, ferramentas MSVC x86/x64 e Windows SDK. O script localiza a instalação
por `vswhere`, prepara o ambiente de compilação, baixa e inicializa o vcpkg se
necessário e deixa o MSBuild instalar as dependências declaradas pelo projeto.
Ele não instala o Visual Studio nem altera variáveis globais do Windows.

Use uma cópia do checkout dentro do disco virtual dedicado à compilação. A
solução guarda objetos e dependências compiladas junto ao checkout em
`vc18/` e `vcpkg_installed/`; o vcpkg também mantém seus pacotes no diretório
apontado por `VCPKG_ROOT`. Uma pasta compartilhada do host pode funcionar, mas
fica sujeita à velocidade do hipervisor e do compartilhamento.

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
