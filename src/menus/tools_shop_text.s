.include 'src/ingame/macros.i'

.scope shops {
gils:
    move_to(27, 6)
    .text 'Gils'
    .db 0

welcome_and_actions:
    .dw 0x0054 - 2
    .text 'Puis-je vous aider ?'
    ;.text 'いらっしゃい! どんなごようけんで?'
    .db 1
    .dw 0x0148 - 4
    .text 'Achat Vente Sortir'
    .db 0
    ;.text 'かう   うる   でる'

quantity:
    .dw 0x0052
    .text 'Que désirez vous ?'
    .db 1
    .dw 0x0144
    .text 'Quantité'
    .db 1
    .dw 0x0146 + 14 * 2
    .text '1'
    .db 0
}
