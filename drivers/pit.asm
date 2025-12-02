; ========================================
; PIT - TIMER SHIT (100Hz)
; ========================================
init_pit:
    ; set up the timer for 100Hz
    mov al, 0x36        ; channel 0, rate generator
    out 0x43, al
    
    ; divisor = 1193182 / 100 = 11932
    mov ax, 11932
    out 0x40, al        ; low byte
    mov al, ah
    out 0x40, al        ; high byte
    ret

timer_ticks: dd 0

; IRQ0 Handler - Timer
irq0_handler:
    pusha
    inc dword [timer_ticks]
    
    ; Call VMM page aging every 100 ticks (1 second)
    mov eax, [timer_ticks]
    mov edx, 0
    mov ecx, 100
    div ecx
    test edx, edx
    jnz .skip_vmm
    
    call vmm_page_timer_tick
    
    .skip_vmm:
    
    ; Send EOI to PIC
    mov al, 0x20
    out 0x20, al
    
    popa
    iret
