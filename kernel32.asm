; j3kOS 32-bit Kernel
; the actual OS, runs in protected mode
; by jortboy3k (@jortboy3k)

[BITS 32]
[ORG 0x10000]

; ========================================
; KERNEL ENTRY - LET'S FUCKING GO
; ========================================
kernel_start:
    ; loader already set up segments for us
    ; clear the screen
    call clear_screen
    
    ; say hi
    mov esi, msg_boot
    call print_string
    
    ; set up interrupts
    call init_idt
    
    ; initialize PIC (interrupt controller)
    call init_pic
    
    ; start the timer
    call init_pit
    
    ; get keyboard working
    call init_keyboard
    
    ; enable interrupts you cuck
    sti
    
    ; we're ready
    mov esi, msg_ready
    call print_string
    
    ; run the shell
    call shell_main
    
    ; if we get here something's fucked
    cli
    hlt

; ========================================
; VIDEO OUTPUT - PRINT SHIT TO SCREEN
; ========================================
VIDEO_MEM equ 0xB8000
VGA_WIDTH equ 80
VGA_HEIGHT equ 25
WHITE_ON_BLACK equ 0x0F

cursor_x: dd 0
cursor_y: dd 0

clear_screen:
    pusha
    mov edi, VIDEO_MEM
    mov ecx, VGA_WIDTH * VGA_HEIGHT
    mov ax, 0x0F20
    rep stosw
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    popa
    ret

print_string:
    ; ESI = string to print
    pusha
    .loop:
        lodsb
        test al, al
        jz .done
        call print_char
        jmp .loop
    .done:
        popa
        ret

print_char:
    ; AL = character
    pusha
    
    ; handle newlines
    cmp al, 10
    je .newline
    
    ; figure out where to write in video mem
    mov ebx, [cursor_y]
    imul ebx, VGA_WIDTH
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VIDEO_MEM
    
    ; write the char
    mov ah, WHITE_ON_BLACK
    mov [ebx], ax
    
    ; move cursor
    inc dword [cursor_x]
    cmp dword [cursor_x], VGA_WIDTH
    jl .done
    
    .newline:
        mov dword [cursor_x], 0
        inc dword [cursor_y]
        
        ; scroll if we hit the bottom
        cmp dword [cursor_y], VGA_HEIGHT
        jl .done
        call scroll_screen
        dec dword [cursor_y]
    
    .done:
        popa
        ret

scroll_screen:
    pusha
    ; copy all lines up one
    mov edi, VIDEO_MEM
    mov esi, VIDEO_MEM + VGA_WIDTH*2
    mov ecx, VGA_WIDTH * (VGA_HEIGHT-1)
    rep movsw
    
    ; clear the last line
    mov ecx, VGA_WIDTH
    mov ax, 0x0F20
    rep stosw
    popa
    ret

print_hex:
    ; EAX = value to print
    pusha
    mov ecx, 8
    .loop:
        rol eax, 4
        push eax
        and eax, 0x0F
        add al, '0'
        cmp al, '9'
        jle .digit
        add al, 7
    .digit:
        call print_char
        pop eax
        loop .loop
    popa
    ret

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
    
    ; load that shit
    lidt [idt_descriptor]
    ret

default_isr:
    iret

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
    
    ; only enable timer and keyboard
    mov al, 0xFC        ; IRQ0 and IRQ1 enabled
    out 0x21, al
    mov al, 0xFF        ; mask all slave IRQs
    out 0xA1, al
    ret

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

irq0_handler:
    pusha
    
    ; count up
    inc dword [timer_ticks]
    
    ; tell PIC we're done
    mov al, 0x20
    out 0x20, al
    
    popa
    iret

; ========================================
; KEYBOARD - SCAN CODES N SHIT
; ========================================
KEY_BUFFER_SIZE equ 256

key_buffer: times KEY_BUFFER_SIZE db 0
key_read_pos: dd 0
key_write_pos: dd 0

; scancode to ascii table (US QWERTY)
scancode_to_ascii:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
    db 'q','w','e','r','t','y','u','i','o','p','[',']',13,0,'a','s'
    db 'd','f','g','h','j','k','l',';',39,'`',0,'\','z','x','c','v'
    db 'b','n','m',',','.','/',0,'*',0,' ',0

init_keyboard:
    ; BIOS already did the work
    ret

irq1_handler:
    pusha
    
    ; grab the scancode
    in al, 0x60
    
    ; ignore key releases
    test al, 0x80
    jnz .done
    
    ; convert scancode to ASCII
    movzx ebx, al
    cmp ebx, 58
    jge .done
    
    mov al, [scancode_to_ascii + ebx]
    test al, al
    jz .done
    
    ; throw it in the buffer
    mov ebx, [key_write_pos]
    mov [key_buffer + ebx], al
    inc ebx
    and ebx, KEY_BUFFER_SIZE - 1
    mov [key_write_pos], ebx
    
    .done:
        ; tell PIC we're done
        mov al, 0x20
        out 0x20, al
        
        popa
        iret

getchar:
    ; returns character in AL or 0 if nothing there
    push ebx
    mov eax, [key_read_pos]
    mov ebx, [key_write_pos]
    cmp eax, ebx
    je .empty
    
    ; grab the char
    movzx eax, byte [key_buffer + eax]
    
    ; move read position
    mov ebx, [key_read_pos]
    inc ebx
    and ebx, KEY_BUFFER_SIZE - 1
    mov [key_read_pos], ebx
    
    pop ebx
    ret
    
    .empty:
        xor eax, eax
        pop ebx
        ret

getchar_wait:
    ; wait for a fucking key press
    .wait:
        call getchar
        test al, al
        jz .wait
        ret

; ========================================
; SHELL - COMMAND LINE SHIT
; ========================================
CMD_BUFFER_SIZE equ 128
cmd_buffer: times CMD_BUFFER_SIZE db 0
cmd_length: dd 0

shell_main:
    ; show the prompt
    mov esi, msg_prompt
    call print_string
    
    .loop:
        ; get a char from keyboard
        call getchar_wait
        
        ; did they hit enter?
        cmp al, 13
        je .execute
        
        ; backspace?
        cmp al, 8
        je .backspace
        
        ; add to command buffer
        mov ebx, [cmd_length]
        cmp ebx, CMD_BUFFER_SIZE-1
        jge .loop
        
        mov [cmd_buffer + ebx], al
        inc dword [cmd_length]
        
        ; echo it
        call print_char
        jmp .loop
    
    .backspace:
        cmp dword [cmd_length], 0
        je .loop
        
        dec dword [cmd_length]
        
        ; move cursor back
        dec dword [cursor_x]
        
        ; print space over the char
        mov al, ' '
        call print_char
        
        ; move cursor back again
        dec dword [cursor_x]
        jmp .loop
    
    .execute:
        ; newline
        mov al, 10
        call print_char
        
        ; null terminate
        mov ebx, [cmd_length]
        mov byte [cmd_buffer + ebx], 0
        
        ; run whatever they typed
        call process_command
        
        ; reset buffer
        mov dword [cmd_length], 0
        
        ; show prompt again
        mov esi, msg_prompt
        call print_string
        jmp .loop

process_command:
    ; nothing typed? whatever
    cmp dword [cmd_length], 0
    je .done
    
    ; is it "help"?
    mov esi, cmd_buffer
    mov edi, cmd_help
    call strcmp
    test eax, eax
    jz .show_help
    
    ; is it "clear"?
    mov esi, cmd_buffer
    mov edi, cmd_clear
    call strcmp
    test eax, eax
    jz .do_clear
    
    ; is it "time"?
    mov esi, cmd_buffer
    mov edi, cmd_time
    call strcmp
    test eax, eax
    jz .show_time
    
    ; idk what you typed
    mov esi, msg_unknown
    call print_string
    jmp .done
    
    .show_help:
        mov esi, msg_help_text
        call print_string
        jmp .done
    
    .do_clear:
        call clear_screen
        jmp .done
    
    .show_time:
        mov esi, msg_time_text
        call print_string
        mov eax, [timer_ticks]
        call print_hex
        mov al, 10
        call print_char
        jmp .done
    
    .done:
        ret

strcmp:
    ; ESI = str1, EDI = str2
    ; returns 0 in EAX if they match
    pusha
    .loop:
        lodsb
        mov bl, [edi]
        inc edi
        cmp al, bl
        jne .not_equal
        test al, al
        jz .equal
        jmp .loop
    .equal:
        mov dword [esp+28], 0  ; they match
        popa
        ret
    .not_equal:
        mov dword [esp+28], 1  ; nope
        popa
        ret

; ========================================
; DATA N MESSAGES
; ========================================
msg_boot:       db 'j3kOS 32-bit Protected Mode', 10
                db 'by Jortboy3k (@jortboy3k)', 10, 10, 0
msg_ready:      db 'System ready. Type "help" for commands.', 10, 10, 0
msg_prompt:     db '> ', 0
msg_unknown:    db 'Unknown command. Type "help" for commands.', 10, 0
msg_help_text:  db 'Available commands:', 10
                db '  help  - Show this help', 10
                db '  clear - Clear screen', 10
                db '  time  - Show timer ticks', 10, 0
msg_time_text:  db 'Timer ticks: 0x', 0

cmd_help:       db 'help', 0
cmd_clear:      db 'clear', 0
cmd_time:       db 'time', 0

; IDT
align 16
idt_table: times 256*8 db 0
idt_descriptor:
    dw 256*8 - 1
    dd idt_table

; Padding to 10KB
times 10240-($-$$) db 0
