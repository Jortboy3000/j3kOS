; ========================================
; UTILS - STRING AND MATH HELPERS
; ========================================

; print decimal number
; EAX = number to print
print_decimal:
    pusha
    
    ; handle 0
    test eax, eax
    jnz .not_zero
    mov al, '0'
    call print_char
    popa
    ret
    
    .not_zero:
    mov ebx, 10
    xor ecx, ecx    ; digit counter
    
    ; convert to string (reversed)
    .convert_loop:
        xor edx, edx
        div ebx         ; EAX = EAX / 10, EDX = remainder
        add dl, '0'
        push edx
        inc ecx
        test eax, eax
        jnz .convert_loop
    
    ; print digits
    .print_loop:
        pop eax
        call print_char
        loop .print_loop
    
    popa
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

strncmp:
    ; ESI = str1, EDI = str2, ECX = length
    ; returns 0 in EAX if first n chars match
    pusha
    .loop:
        test ecx, ecx
        jz .equal
        lodsb
        mov bl, [edi]
        inc edi
        cmp al, bl
        jne .not_equal
        dec ecx
        jmp .loop
    .equal:
        mov dword [esp+28], 0  ; they match
        popa
        ret
    .not_equal:
        mov dword [esp+28], 1  ; nope
        popa
        ret

strcmp_simple:
    ; ESI = str1, EDI = str2 (on stack)
    ; returns 0 in EAX if match
    .loop:
        mov al, [esi]
        mov bl, [edi]
        cmp al, bl
        jne .not_equal
        test al, al
        jz .equal
        cmp al, ' '
        je .equal
        inc esi
        inc edi
        jmp .loop
    .equal:
        xor eax, eax
        ret
    .not_equal:
        mov eax, 1
        ret
