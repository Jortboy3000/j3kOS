; =====================================================
; Page Swapping System Extensions
; Extra functions for swap management
; =====================================================

; swap out multiple pages when memory is tight
swap_out_pages:
    pusha
    
    mov ecx, PAGE_COUNT
    mov edi, page_table
    mov ebx, 0          ; swapped count
    
    .swap_loop:
        ; swap out compressed or cold pages
        movzx eax, byte [edi]
        cmp eax, PAGE_COMPRESSED
        je .do_swap
        cmp eax, PAGE_COLD
        jne .next_page
        
        .do_swap:
            push eax
            push edi
            ; calculate page index
            mov eax, edi
            sub eax, page_table
            shr eax, 4
            call swap_page_out
            pop edi
            pop eax
            
            ; limit swaps per call
            inc ebx
            cmp ebx, 5      ; swap max 5 pages per call
            jge .done
        
        .next_page:
            add edi, 16
            loop .swap_loop
    
    .done:
        popa
        ret

; show swap space information
show_swap_info:
    pusha
    
    mov esi, msg_swap_info
    call print_string
    
    ; count used swap slots
    xor ebx, ebx        ; used count
    xor ecx, ecx        ; slot index
    .count_loop:
        cmp ecx, 256
        jge .done_count
        
        ; check if slot is used
        mov eax, ecx
        mov edx, eax
        shr edx, 3
        and eax, 7
        mov dl, [swap_bitmap + edx]
        bt edx, eax
        jnc .not_used
        inc ebx
        .not_used:
        inc ecx
        jmp .count_loop
    
    .done_count:
    ; show stats
    mov esi, msg_swap_used
    call print_string
    mov eax, ebx
    call print_decimal
    mov al, '/'
    call print_char
    mov eax, 256
    call print_decimal
    mov esi, msg_swap_slots
    call print_string
    
    ; calculate KB used
    mov eax, ebx
    shl eax, 2          ; * 4 KB per slot
    mov esi, msg_swap_kb
    call print_string
    call print_decimal
    mov esi, msg_kb_used
    call print_string
    
    ; show activity
    mov esi, msg_swap_writes
    call print_string
    mov eax, [swap_write_count]
    call print_decimal
    mov al, 10
    call print_char
    
    mov esi, msg_swap_reads
    call print_string
    mov eax, [swap_read_count]
    call print_decimal
    mov al, 10
    call print_char
    
    popa
    ret

msg_swap_info:      db 10, '--- Swap Space Info ---', 10, 0
msg_swap_used:      db 'Used slots: ', 0
msg_swap_slots:     db ' slots', 10, 0
msg_swap_kb:        db 'Swap usage: ', 0
msg_kb_used:        db ' KB', 10, 0
msg_swap_writes:    db 'Swap writes: ', 0
msg_swap_reads:     db 'Swap reads: ', 0

