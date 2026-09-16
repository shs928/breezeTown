# Breeze Town UI

The game bundles this font so Chinese HUD text, map labels and building signs do
not depend on the player's installed system fonts.

- Source: [Noto Sans SC, Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc)
- Source file: `NotoSansSC[wght].ttf`, downloaded 2026-09-16
- Source SHA-256: `a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`
- License: SIL Open Font License 1.1, preserved in [OFL.txt](OFL.txt)
- Modification: fixed weight 400; subset to GB2312, punctuation, arrows and game
  text; renamed to **Breeze Town UI**. Copyright and license name records remain.
- Rebuild: install `fonttools==4.60.1`, then run
  `python tools/art/build_ui_font.py /path/to/NotoSansSC.ttf` from the repository.

The compiled font is included in the project. Running or exporting the game does
not require Python, FontTools, a network connection or a system Chinese font.
