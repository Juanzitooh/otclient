# Elemental motion

Animação transparente da assinatura refinada do Elemental. O símbolo surge primeiro; os traços azul e verde avançam junto com o nome; “Colete, construa, lute e viva essa aventura” aparece logo abaixo da linha verde, alinhado à palavra Elemental.

## Arquivos

- `elemental-logo-reveal.svg`: fonte vetorial animada, com fundo transparente.
- `elemental-logo-reveal.mov`: versão transparente de 6 segundos em 1920×1080 e 24 fps, adequada para composição em um editor de vídeo.
- `render_elemental_motion.py`: recria o MOV a partir dos vetores da identidade.

Para comparar a paleta com a versão anterior, veja [`../identity/elemental-color-slogan-tests.svg`](../identity/elemental-color-slogan-tests.svg). A entrega das assinaturas está em [`../identity/brand-package/`](../identity/brand-package/).

Para regenerar o motion, o ambiente precisa de Python com Pillow, Inkscape e FFmpeg:

```sh
python3 design/motion/render_elemental_motion.py
```
