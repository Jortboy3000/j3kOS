; ========================================
; VIDEO OUTPUT - PRINT SHIT TO SCREEN
; ========================================
VIDEO_MEM equ 0xB8000
VGA_WIDTH equ 80
VGA_HEIGHT equ 25
WHITE_ON_BLACK equ 0x0F

cursor_x: dd 0
cursor_y: dd 0
boot_mode: db 0  ; 0=normal, 1=safe, 2=verbose

clear_screen:
    pusha
    mov edi, VIDEO_MEM
    mov ecx, VGA_WIDTH * VGA_HEIGHT
    mov ax, 0x0F20
    rep stosw
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    call update_cursor
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
    jl .update_cursor_pos
    
    .newline:
        mov dword [cursor_x], 0
        inc dword [cursor_y]
        
        ; scroll if we hit the bottom
        cmp dword [cursor_y], VGA_HEIGHT
        jl .update_cursor_pos
        call scroll_screen
        dec dword [cursor_y]
    
    .update_cursor_pos:
        call update_cursor
    
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

; ========================================
; CURSOR MANAGEMENT - MAKE IT BLINK
; ========================================
enable_cursor:
    pusha
    ; Set cursor shape (scanlines 13-15 = thick block)
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    
    inc dx
    mov al, 13          ; Start scanline
    out dx, al
    
    dec dx
    mov al, 0x0B
    out dx, al
    
    inc dx
    mov al, 15          ; End scanline
    out dx, al
    popa
    ret

update_cursor:
    pusha
    ; Calculate linear position: y * 80 + x
    mov eax, [cursor_y]
    mov ebx, VGA_WIDTH
    mul ebx
    add eax, [cursor_x]
    mov ebx, eax
    
    ; Set low byte
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    
    inc dx
    mov al, bl
    out dx, al
    
    ; Set high byte
    dec dx
    mov al, 0x0E
    out dx, al
    
    inc dx
    mov al, bh
    out dx, al
    
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

print_newline:
    ; print a newline character
    pusha
    mov al, 10
    call print_char
    popa
    ret

print_hex_dump:
    ; ESI = buffer, ECX = length (max 256 bytes for display)
    pusha
    push ecx
    
    cmp ecx, 256
    jle .print_loop
    mov ecx, 256
    
.print_loop:
    test ecx, ecx
    jz .done_dump
    
    ; print byte as hex
    lodsb
    movzx eax, al
    push ecx
    push esi
    
    ; print high nibble
    mov cl, al
    shr cl, 4
    and cl, 0x0F
    add cl, '0'
    cmp cl, '9'
    jle .high_digit
    add cl, 7
.high_digit:
    mov al, cl
    call print_char
    
    ; print low nibble
    pop esi
    push esi
    mov al, [esi-1]
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jle .low_digit
    add al, 7
.low_digit:
    call print_char
    
    ; space between bytes
    mov al, ' '
    call print_char
    
    pop esi
    pop ecx
    dec ecx
    
    ; newline every 16 bytes
    mov eax, esi
    sub eax, [esp + 28]
    and eax, 0x0F
    test eax, eax
    jnz .print_loop
    
    call print_newline
    jmp .print_loop
    
.done_dump:
    pop ecx
    call print_newline
    popa
    ret

; print byte as hex
; AL = byte
print_hex_byte:
    pusha
    mov bl, al
    shr al, 4
    call .print_nibble
    mov al, bl
    and al, 0x0F
    call .print_nibble
    popa
    ret
    .print_nibble:
        cmp al, 10
        jl .digit
        add al, 'A' - 10
        call print_char
        ret
        .digit:
            add al, '0'
            call print_char
            ret

; print word as hex
; AX = word
print_hex_word:
    pusha
    push eax
    shr eax, 8
    call print_hex_byte
    pop eax
    call print_hex_byte
    popa
    ret
