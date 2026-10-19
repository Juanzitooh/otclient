@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"
set "SOLUTION=%REPO_ROOT%\vc18\otclient.sln"
set "VS_CONFIG=%SCRIPT_DIR%windows-build.vsconfig"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "BOOTSTRAPPER=%TEMP%\elemental-vs-buildtools-setup.exe"
set "VS_INSTALL_PATH=%ProgramFiles%\Microsoft Visual Studio\18\BuildTools"

if not exist "%SOLUTION%" (
  echo ERRO: execute este script a partir de uma copia do repositorio otclient-next.
  exit /b 1
)
if not exist "%VS_CONFIG%" (
  echo ERRO: configuracao de componentes ausente: "%VS_CONFIG%"
  exit /b 1
)

call :find_vs
if defined VS_INSTALLATION goto :build

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo ERRO: PowerShell nao esta disponivel para baixar o instalador oficial.
  exit /b 1
)
if exist "%BOOTSTRAPPER%" del /Q "%BOOTSTRAPPER%"

echo Baixando o instalador oficial do Visual Studio Build Tools 2026...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/stable/vs_buildtools.exe' -OutFile '%BOOTSTRAPPER%'"
if errorlevel 1 (
  echo ERRO: nao foi possivel baixar o instalador da Microsoft.
  exit /b 1
)
if not exist "%BOOTSTRAPPER%" (
  echo ERRO: o instalador nao foi criado em "%BOOTSTRAPPER%".
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$signature=Get-AuthenticodeSignature -LiteralPath '%BOOTSTRAPPER%'; if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') { exit 1 }"
if errorlevel 1 (
  del /Q "%BOOTSTRAPPER%" 2>nul
  echo ERRO: o instalador baixado nao tem uma assinatura Microsoft valida.
  exit /b 1
)

echo Instalando MSVC x86/x64, MSBuild e Windows SDK. O instalador pode solicitar elevacao.
start "" /wait "%BOOTSTRAPPER%" --passive --wait --norestart --installPath "%VS_INSTALL_PATH%" --config "%VS_CONFIG%"
set "INSTALL_RESULT=%ERRORLEVEL%"
if "%INSTALL_RESULT%"=="3010" (
  echo A instalacao terminou, mas o Windows pediu reinicializacao. Reinicie e rode este script novamente.
  exit /b 3010
)
if not "%INSTALL_RESULT%"=="0" (
  echo ERRO: instalacao do Visual Studio Build Tools terminou com codigo %INSTALL_RESULT%.
  exit /b %INSTALL_RESULT%
)

call :find_vs
if not defined VS_INSTALLATION (
  echo ERRO: a instalacao terminou, mas o Visual Studio 2026 com ferramentas C++ nao foi localizado.
  exit /b 1
)

:build
where git.exe >nul 2>nul
if errorlevel 1 (
  echo ERRO: instale Git for Windows e abra um novo Prompt de Comando antes do build.
  exit /b 1
)

echo Ferramentas encontradas em "%VS_INSTALLATION%".
echo O build tambem prepara o vcpkg e compila OpenGL/DirectX para x64/x86.
call "%SCRIPT_DIR%build-windows.bat"
exit /b %ERRORLEVEL%

:find_vs
set "VS_INSTALLATION="
if not exist "%VSWHERE%" exit /b 0
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -version "[18.0,19.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALLATION=%%I"
exit /b 0
