@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"
set "SOLUTION=%REPO_ROOT%\vc18\otclient.sln"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist "%SOLUTION%" (
  echo ERRO: solucao Visual Studio nao encontrada: "%SOLUTION%"
  exit /b 1
)
if not exist "%VSWHERE%" (
  echo ERRO: instale o Visual Studio 2026 com Desktop development with C++.
  exit /b 1
)

for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -version "[18.0,19.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALLATION=%%I"
if not defined VS_INSTALLATION (
  echo ERRO: Visual Studio 2026 com ferramentas C++ x86/x64 nao foi encontrado.
  exit /b 1
)

set "VS_DEV_CMD=%VS_INSTALLATION%\Common7\Tools\VsDevCmd.bat"
if not exist "%VS_DEV_CMD%" (
  echo ERRO: VsDevCmd.bat nao foi encontrado em "%VS_INSTALLATION%".
  exit /b 1
)

if defined ELEMENTAL_VCPKG_ROOT (
  set "VCPKG_ROOT=%ELEMENTAL_VCPKG_ROOT%"
) else if defined VCPKG_ROOT (
  set "ELEMENTAL_VCPKG_ROOT=%VCPKG_ROOT%"
) else (
  set "ELEMENTAL_VCPKG_ROOT=%LOCALAPPDATA%\Elemental\vcpkg"
  set "VCPKG_ROOT=%ELEMENTAL_VCPKG_ROOT%"
)

if not defined ELEMENTAL_WINDOWS_RENDERER set "ELEMENTAL_WINDOWS_RENDERER=OpenGL"
if /I not "%ELEMENTAL_WINDOWS_RENDERER%"=="OpenGL" if /I not "%ELEMENTAL_WINDOWS_RENDERER%"=="DirectX" (
  echo ERRO: ELEMENTAL_WINDOWS_RENDERER deve ser OpenGL ou DirectX.
  exit /b 1
)

if defined ELEMENTAL_WINDOWS_OUTPUT (
  for %%I in ("%ELEMENTAL_WINDOWS_OUTPUT%") do set "OUTPUT_PARENT=%%~fI"
) else (
  set "OUTPUT_PARENT=%REPO_ROOT%\.builds\windows"
)

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "BUILD_STAMP=%%I"
if not defined BUILD_STAMP (
  echo ERRO: nao foi possivel gerar o identificador da compilacao.
  exit /b 1
)

set "OUTPUT_ROOT=%OUTPUT_PARENT%\%BUILD_STAMP%"
if exist "%OUTPUT_ROOT%" (
  echo ERRO: a pasta de saida ja existe: "%OUTPUT_ROOT%"
  exit /b 1
)
mkdir "%OUTPUT_ROOT%\logs" || exit /b 1

call "%VS_DEV_CMD%" -arch=x64 -host_arch=x64 -no_logo
if errorlevel 1 (
  echo ERRO: nao foi possivel carregar o ambiente do Visual Studio.
  exit /b 1
)

set "VCPKG_ROOT=%ELEMENTAL_VCPKG_ROOT%"
if not exist "%VCPKG_ROOT%\bootstrap-vcpkg.bat" (
  where git >nul 2>nul
  if errorlevel 1 (
    echo ERRO: instale o Git para preparar o vcpkg.
    exit /b 1
  )
  if exist "%VCPKG_ROOT%" (
    echo ERRO: a pasta do vcpkg existe mas nao contem bootstrap-vcpkg.bat: "%VCPKG_ROOT%"
    exit /b 1
  )
  for %%I in ("%VCPKG_ROOT%\..") do if not exist "%%~fI" mkdir "%%~fI"
  git clone https://github.com/microsoft/vcpkg "%VCPKG_ROOT%"
  if errorlevel 1 exit /b 1
)

if not exist "%VCPKG_ROOT%\vcpkg.exe" (
  call "%VCPKG_ROOT%\bootstrap-vcpkg.bat" -disableMetrics
  if errorlevel 1 exit /b 1
)

where msbuild.exe >nul 2>nul
if errorlevel 1 (
  echo ERRO: MSBuild nao esta disponivel no ambiente atual.
  exit /b 1
)

call :build_variant OpenGL x64 opengl-x64
if errorlevel 1 exit /b 1
call :build_variant DirectX x64 directx-x64
if errorlevel 1 exit /b 1
call :build_variant OpenGL x86 opengl-x86
if errorlevel 1 exit /b 1
call :build_variant DirectX x86 directx-x86
if errorlevel 1 exit /b 1

git -C "%REPO_ROOT%" rev-parse HEAD > "%OUTPUT_ROOT%\source-commit.txt" 2>nul
git -C "%REPO_ROOT%" status --short >> "%OUTPUT_ROOT%\source-commit.txt" 2>nul
>> "%OUTPUT_ROOT%\source-commit.txt" echo Renderer empacotado no alvo windows-x64: %ELEMENTAL_WINDOWS_RENDERER%

if /I "%ELEMENTAL_WINDOWS_RENDERER%"=="OpenGL" (
  call :stage_bundle "%REPO_ROOT%\otclient_gl_x64.exe" "%OUTPUT_ROOT%\windows-x64" "bin\elemental.exe"
  if errorlevel 1 exit /b 1
  call :stage_bundle "%REPO_ROOT%\otclient_dx_x64.exe" "%OUTPUT_ROOT%\windows-variants\directx-x64" "otclient_dx_x64.exe"
  if errorlevel 1 exit /b 1
) else (
  call :stage_bundle "%REPO_ROOT%\otclient_dx_x64.exe" "%OUTPUT_ROOT%\windows-x64" "bin\elemental.exe"
  if errorlevel 1 exit /b 1
  call :stage_bundle "%REPO_ROOT%\otclient_gl_x64.exe" "%OUTPUT_ROOT%\windows-variants\opengl-x64" "otclient_gl_x64.exe"
  if errorlevel 1 exit /b 1
)

call :stage_bundle "%REPO_ROOT%\otclient_gl.exe" "%OUTPUT_ROOT%\windows-variants\opengl-x86" "otclient_gl.exe"
if errorlevel 1 exit /b 1
call :stage_bundle "%REPO_ROOT%\otclient_dx.exe" "%OUTPUT_ROOT%\windows-variants\directx-x86" "otclient_dx.exe"
if errorlevel 1 exit /b 1

echo.
echo Build Windows concluido: "%OUTPUT_ROOT%"
echo O alvo windows-x64 esta pronto para scripts/publish-release.sh.
echo As variantes em windows-variants sao para teste manual.
exit /b 0

:build_variant
set "BUILD_CONFIGURATION=%~1"
set "BUILD_PLATFORM=%~2"
set "BUILD_LABEL=%~3"
set "BUILD_LOG=%OUTPUT_ROOT%\logs\%BUILD_LABEL%.log"
echo Compilando %BUILD_CONFIGURATION% %BUILD_PLATFORM%...
msbuild.exe "%SOLUTION%" /m:2 /t:Build /p:Configuration=%BUILD_CONFIGURATION% /p:Platform=%BUILD_PLATFORM% /p:CanarySharedVcpkgDisable=true /verbosity:minimal > "%BUILD_LOG%" 2>&1
set "BUILD_RESULT=%ERRORLEVEL%"
if not "%BUILD_RESULT%"=="0" (
  type "%BUILD_LOG%"
  echo ERRO: build %BUILD_CONFIGURATION% %BUILD_PLATFORM% falhou. Log: "%BUILD_LOG%"
  exit /b %BUILD_RESULT%
)
exit /b 0

:stage_bundle
set "STAGE_EXECUTABLE=%~1"
set "STAGE_DIRECTORY=%~2"
set "STAGE_ENTRYPOINT=%~3"
if not exist "%STAGE_EXECUTABLE%" (
  echo ERRO: executavel compilado nao encontrado: "%STAGE_EXECUTABLE%"
  exit /b 1
)
mkdir "%STAGE_DIRECTORY%" 2>nul
for %%D in (data mods modules) do (
  if not exist "%REPO_ROOT%\%%D" (
    echo ERRO: pasta de runtime ausente: "%REPO_ROOT%\%%D"
    exit /b 1
  )
  robocopy "%REPO_ROOT%\%%D" "%STAGE_DIRECTORY%\%%D" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
  if errorlevel 8 exit /b 1
)
for %%F in (init.lua otclientrc.lua config.ini cacert.pem AUTHORS BUGS LICENSE README.md) do (
  if exist "%REPO_ROOT%\%%F" copy /Y "%REPO_ROOT%\%%F" "%STAGE_DIRECTORY%\%%F" >nul
)
for %%D in ("%STAGE_DIRECTORY%\%STAGE_ENTRYPOINT%") do if not exist "%%~dpD" mkdir "%%~dpD"
copy /Y "%STAGE_EXECUTABLE%" "%STAGE_DIRECTORY%\%STAGE_ENTRYPOINT%" >nul
if errorlevel 1 exit /b 1
exit /b 0
