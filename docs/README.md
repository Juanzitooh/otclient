# Codex Wiki Bundle for OTClient

## PT-BR

Este README explica como distribuir e usar o bundle de wiki/agents no Codex.

### Objetivo
- Entregar um pacote `.zip` com documentacao (`.md`) para melhorar o contexto do Codex.
- Permitir que cada usuario extraia na raiz do proprio repositorio e personalize localmente.

### Conteudo do bundle
- `AGENTS.global.md`
- `wiki.md`
- `AGENTS.md` por pasta/subpasta
- `.md` tecnicos complementares (ex.: `src/client/*.md`, `tools/build.md`)
- `docs/guides/*.md` (boas praticas de C++, Lua e Git)
- `docs/roadmap_codex.md` (bootstrap de roadmap)

### Nao incluido
- `docs/roadmap/` (planejamento local de cada usuario)
- `docs/README.md` (este guia)

### Requisito de acesso
Para usar no Codex, a conta precisa ter acesso ao produto (normalmente Plus ou superior, conforme disponibilidade da conta/regiao).

### Link padrao do bundle
Release (pagina):

`RELEASE_PAGE_URL=https://github.com/Juanzitooh/otclient/releases/tag/codex`

Download direto do zip:

`WIKI_BUNDLE_URL=https://github.com/Juanzitooh/otclient/releases/download/codex/codex_export_otclient.zip`

### Gerar o zip
```bash
python3 tools/export_wiki_bundle.py
```

Saida padrao: `codex_export_otclient.zip`

### Publicar no GitHub Release
1. Gerar o zip localmente.
2. Criar/atualizar a release.
3. Fazer upload de `codex_export_otclient.zip`.
4. Manter nome e tag padrao para URL estavel.
5. Conferir se os links `RELEASE_PAGE_URL` e `WIKI_BUNDLE_URL` continuam validos.

### Como usar no Codex (usuario final)
1. Baixar o zip no link da release.
2. Extrair na raiz do projeto (mesmo nivel de `src/`, `modules/`, `data/`, `tools/`).
3. Comecar a conversa com:
   - `Use AGENTS.global.md como guia base deste repositorio.`
4. Para tarefas por modulo, citar tambem o `AGENTS.md` da pasta.
5. Para planejamento, citar:
   - `Use docs/roadmap_codex.md para bootstrap do roadmap local.`

### Passo adicional recomendado (traducao para ingles)
Se sua equipe for internacional, traduza a wiki para EN apos a primeira extracao:
1. Traduzir `wiki.md`.
2. Traduzir `AGENTS.global.md`.
3. Traduzir os `AGENTS.md` mais usados no seu fluxo.
4. Reexportar com `python3 tools/export_wiki_bundle.py`.
5. Publicar um zip proprio para seu time.

### Customizacao no seu servidor/repositorio
Voce pode editar localmente e manter seu proprio padrao:
1. Ajustar `AGENTS.global.md`, `wiki.md` e `AGENTS.md`.
2. Regerar o bundle.
3. Publicar em release privada/publica da sua organizacao.

---

## EN

This README explains how to distribute and use the wiki/agents bundle with Codex.

### Goal
- Provide a `.zip` package of `.md` documentation to improve Codex context.
- Let each user extract it at repository root and customize locally.

### Bundle contents
- `AGENTS.global.md`
- `wiki.md`
- `AGENTS.md` files per folder/subfolder
- complementary technical `.md` files (e.g. `src/client/*.md`, `tools/build.md`)
- `docs/guides/*.md` (reusable C++, Lua, and Git good-practice guides)
- `docs/roadmap_codex.md` (roadmap bootstrap policy)

### Not included
- `docs/roadmap/` (user-local planning workspace)
- `docs/README.md` (this guide)

### Access requirement
To use this with Codex, the account must have Codex access (typically Plus or higher, depending on account/region availability).

### Default bundle link
Release page:

`RELEASE_PAGE_URL=https://github.com/Juanzitooh/otclient/releases/tag/codex`

Direct zip download:

`WIKI_BUNDLE_URL=https://github.com/Juanzitooh/otclient/releases/download/codex/codex_export_otclient.zip`

### Generate the zip
```bash
python3 tools/export_wiki_bundle.py
```

Default output: `codex_export_otclient.zip`

### Publish on GitHub Release
1. Generate the zip locally.
2. Create/update the release.
3. Upload `codex_export_otclient.zip`.
4. Keep stable file name and tag strategy for a stable URL.
5. Verify `RELEASE_PAGE_URL` and `WIKI_BUNDLE_URL` are still valid.

### How end users should use it in Codex
1. Download the zip from the release link.
2. Extract at project root (same level as `src/`, `modules/`, `data/`, `tools/`).
3. Start with:
   - `Use AGENTS.global.md as the base guide for this repository.`
4. For module-specific tasks, also reference the local `AGENTS.md`.
5. For planning, reference:
   - `Use docs/roadmap_codex.md to bootstrap the local roadmap.`

### Recommended extra step (translate wiki to English)
If your team is international, translate the wiki after first extraction:
1. Translate `wiki.md`.
2. Translate `AGENTS.global.md`.
3. Translate the most-used `AGENTS.md` files.
4. Re-export with `python3 tools/export_wiki_bundle.py`.
5. Publish your own team bundle zip.

### Customization on your own server/repository
You can maintain your own flavor:
1. Edit `AGENTS.global.md`, `wiki.md`, and local `AGENTS.md` files.
2. Regenerate the bundle.
3. Publish it to your org private/public release.
