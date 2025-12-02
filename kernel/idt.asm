; ========================================
; IDT - INTERRUPT SHIT
; ========================================
init_idt:
    ; build 256 IDT entries with default handler
    mov edi, idt_table
    mov ecx, 256
    
    .loop:
        ; handler address (low part)
        mov eax, default_isr
        mov [edi], ax
        
        ; code segment selector
        mov word [edi+2], 0x08
        
        ; reserved byte
        mov byte [edi+4], 0
        
        ; type and attributes
        mov byte [edi+5], 0x8E
        
        ; handler address (high part)
        shr eax, 16
        mov [edi+6], ax
        
        add edi, 8
        loop .loop
    
    ; set up our actual interrupt handlers
    ; timer on IRQ0 (INT 0x20)
    mov edi, idt_table + (0x20 * 8)
    mov eax, irq0_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; keyboard on IRQ1 (INT 0x21)
    mov edi, idt_table + (0x21 * 8)
    mov eax, irq1_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; network (RTL8139) on IRQ11 (INT 0x2B)
    mov edi, idt_table + (0x2B * 8)
    mov eax, irq11_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; PS/2 mouse on IRQ12 (INT 0x2C)
    mov edi, idt_table + (0x2C * 8)
    mov eax, irq12_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; system call on INT 0x80
    mov edi, idt_table + (0x80 * 8)
    mov eax, syscall_handler
    mov [edi], ax
    mov word [edi+2], 0x08      ; kernel code segment
    mov byte [edi+5], 0xEE      ; present, DPL=3 (user), interrupt gate
    shr eax, 16
    mov [edi+6], ax
    
    ; load that shit
    lidt [idt_descriptor]
    ret

default_isr:
    iret

; IDT
align 16
idt_table: times 256*8 db 0
idt_descriptor:
    dw 256*8 - 1
    dd idt_table

; null IDT for rebooting
null_idt:
    dw 0
    dd 0
