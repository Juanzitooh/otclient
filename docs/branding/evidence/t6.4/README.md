# T6.4 — QA runtime da identidade desktop

## Origem e build

- Checkout: `codex/elemental-client-branding`, commit `45ef02acc764a99a75be930d6ab91af6b509080b`, baseado no snapshot T6.3 `otclient-next@cce2717bc`.
- Binário Linux Debug pré-existente: `otclient`, 293.070.720 bytes, SHA-256 `8cfec4e8dac827de427adcc66ff0b5d6beb871572ba5cc77ddc5f3320a31ea0b`.
- Não houve alterações C++ nesta task; o cliente existente carregou os módulos e imagens atualizados diretamente da worktree. Nenhuma suíte de testes foi executada.

## Sessões observadas

Cada captura usou uma sessão Xvfb local, sem listener TCP, uma instância por vez, locale `pt` e perfil isolado passado por `--user-dir`:

- 1366×768: [`login-1366x768.png`](login-1366x768.png), [`client-1366x768.log`](client-1366x768.log), [`geometry-1366x768.txt`](geometry-1366x768.txt).
- 1920×1080: [`login-1920x1080.png`](login-1920x1080.png), [`client-1920x1080.log`](client-1920x1080.log), [`geometry-1920x1080.txt`](geometry-1920x1080.txt).
- SHA-256 das capturas: `8cf2b99657ddfdede279b2add3fbe1f460597072e641e0d769b6721c15d6ebf5` (1366×768); `323a18696d07e7582cd10792256958eaad840f2c959cc653bea7bf08deb415f2` (1920×1080).
- Perfis temporários: `/tmp/elemental-t64-runtime-01a14234-r2/user-qa-1366-r2` e `/tmp/elemental-t64-runtime-01a14234-r2/user-qa-1920`.
- As janelas ficaram em `(0, 0)` com dimensões iguais ao display. `client_bottommenu`, `client_background` e `client_entergame` carregaram nas duas sessões. Não foram observadas falhas de import de estilo, alias indefinido ou estilo desconhecido.
- Os logs registram avisos de widgets legados durante o encerramento do cliente. Eles não impediram o carregamento/renderização da tela.
- Nenhuma credencial foi digitada, cadastro foi enviado ou conexão de jogo iniciada.

## Resultado e gate

As capturas mostram o símbolo e wordmark Portal da Origem sobre a arte hero aprovada. O wordmark antigo do rodapé foi removido; a assinatura foi aplicada como imagem no painel de fundo, onde permanece visível fora do recorte do rodapé.

O login e os painéis superior e inferior ainda são os componentes legados. O painel esquerdo Elemental, os modais de cadastro e recuperação sobre fundo desfocado, e a nova charlist são posteriores, em T6.5 e T6.6. Esta captura é uma prova de integração da marca, não representa o redesign completo do fluxo.

O usuário já selecionou a prova 01 do Portal da Origem, com E serifado dentro das quatro forças, e aprovou continuar com a aplicação no cliente. A marca não foi alterada no `clienticon.png`.
