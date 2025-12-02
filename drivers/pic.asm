; ========================================
; PIC - REMAP THIS FUCKING THING
; ========================================
init_pic:
    ; ICW1 - initialize both PICs
    mov al, 0x11
    out 0x20, al        ; master
    out 0xA0, al        ; slave
    
    ; ICW2 - set vector offsets
    mov al, 0x20
    out 0x21, al        ; master at 0x20
    mov al, 0x28
    out 0xA1, al        ; slave at 0x28
    
    ; ICW3 - tell em how they're connected
    mov al, 0x04
    out 0x21, al        ; slave on IRQ2
    mov al, 0x02
    out 0xA1, al        ; cascade shit
    
    ; ICW4 - 8086 mode whatever
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    
    ; enable timer, keyboard, IRQ11 (network), and IRQ12 (mouse)
    mov al, 0xFC        ; IRQ0 and IRQ1 enabled
    out 0x21, al
    mov al, 0xF3        ; IRQ11 and IRQ12 enabled (bits 3 and 4 = 0)
    out 0xA1, al
    ret
