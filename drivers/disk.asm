; ========================================
; DISK I/O - READ/WRITE SECTORS
; ========================================

; swap space management
SWAP_START_SECTOR equ 501       ; start sector for swap space (after kernel)
SWAP_SECTORS equ 256            ; 256 sectors = 128KB swap space
swap_bitmap: times 32 db 0      ; 256 bits for 256 swap slots
swap_write_count: dd 0          ; stats
swap_read_count: dd 0

; write sector to disk
; eax = LBA sector number
; edi = source buffer
write_disk_sector:
    pusha
    
    ; wait for disk ready (with timeout)
    mov dx, 0x1F7
    mov ecx, 100000
    .wait_ready:
        in al, dx
        test al, 0x80
        jz .ready
        dec ecx
        jnz .wait_ready
        ; timeout - just return (fail silently for now)
        popa
        ret
    .ready:
    
    ; send sector count (1)
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    
    ; send LBA
    mov dx, 0x1F3
    out dx, al
    
    mov ebx, eax
    shr ebx, 8
    mov dx, 0x1F4
    mov al, bl
    out dx, al
    
    shr ebx, 8
    mov dx, 0x1F5
    mov al, bl
    out dx, al
    
    shr ebx, 8
    mov dx, 0x1F6
    mov al, bl
    and al, 0x0F
    or al, 0xE0         ; LBA mode, master
    out dx, al
    
    ; send write command
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al
    
    ; wait for ready (with timeout)
    mov ecx, 100000
    .wait_write:
        in al, dx
        test al, 0x80
        jz .write_data
        dec ecx
        jnz .wait_write
        ; timeout
        popa
        ret
        
    .write_data:
    ; write 256 words (512 bytes)
    mov ecx, 256
    mov dx, 0x1F0
    .write_loop:
        mov ax, [edi]
        out dx, ax
        add edi, 2
        loop .write_loop
    
    popa
    ret

; read sector from disk
; eax = LBA sector number
; edi = dest buffer
read_disk_sector:
    pusha
    
    ; wait for disk ready (with timeout)
    mov dx, 0x1F7
    mov ecx, 100000
    .wait_ready:
        in al, dx
        test al, 0x80
        jz .ready
        dec ecx
        jnz .wait_ready
        ; timeout
        popa
        ret
    .ready:
    
    ; send sector count (1)
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    
    ; send LBA
    mov dx, 0x1F3
    out dx, al
    
    mov ebx, eax
    shr ebx, 8
    mov dx, 0x1F4
    mov al, bl
    out dx, al
    
    shr ebx, 8
    mov dx, 0x1F5
    mov al, bl
    out dx, al
    
    shr ebx, 8
    mov dx, 0x1F6
    mov al, bl
    and al, 0x0F
    or al, 0xE0         ; LBA mode, master
    out dx, al
    
    ; send read command
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al
    
    ; wait for ready (with timeout)
    mov ecx, 100000
    .wait_read:
        in al, dx
        test al, 0x80
        jz .read_data
        dec ecx
        jnz .wait_read
        ; timeout
        popa
        ret
        
    .read_data:
    ; check for error
    in al, dx
    test al, 0x01
    jnz .disk_error
    
    ; read 256 words (512 bytes)
    mov ecx, 256
    mov dx, 0x1F0
    .read_loop:
        in ax, dx
        mov [edi], ax
        add edi, 2
        loop .read_loop
    
    popa
    ret
    
    .disk_error:
        popa
        ret

; allocate a swap slot
; returns: eax = swap slot number, or -1 if full
alloc_swap_slot:
    push ebx
    push ecx
    push edx
    
    xor ebx, ebx        ; byte index
    .byte_loop:
        cmp ebx, 32
        jge .no_slot
        
        mov al, [swap_bitmap + ebx]
        cmp al, 0xFF
        je .next_byte
        
        ; find free bit in this byte
        xor ecx, ecx
        .bit_loop:
            cmp ecx, 8
            jge .next_byte
            
            mov dl, 1
            shl dl, cl
            test al, dl
            jz .found_slot
            
            inc ecx
            jmp .bit_loop
        
        .next_byte:
            inc ebx
            jmp .byte_loop
    
    .found_slot:
        ; mark bit as used
        or byte [swap_bitmap + ebx], dl
        
        ; calculate slot number
        mov eax, ebx
        shl eax, 3
        add eax, ecx
        jmp .done
    
    .no_slot:
        mov eax, -1
    
    .done:
        pop edx
        pop ecx
        pop ebx
        ret

; free a swap slot
; eax = swap slot number
free_swap_slot:
    push ebx
    push ecx
    push edx
    
    ; calculate byte and bit
    mov ebx, eax
    shr ebx, 3          ; byte index
    mov ecx, eax
    and ecx, 7          ; bit index
    
    ; clear bit
    mov dl, 1
    shl dl, cl
    not dl
    and byte [swap_bitmap + ebx], dl
    
    pop edx
    pop ecx
    pop ebx
    ret

; swap page out to disk
; eax = page index
swap_page_out:
    pusha
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page can be swapped
    movzx ecx, byte [ebx]
    cmp ecx, PAGE_COLD
    je .can_swap
    cmp ecx, PAGE_COMPRESSED
    je .can_swap
    jmp .done           ; can't swap hot or allocated pages
    
    .can_swap:
        ; allocate swap slot
        call alloc_swap_slot
        cmp eax, -1
        je .done        ; no swap space available
        
        mov edx, eax    ; save swap slot
        
        ; calculate disk sector (8 sectors per 4KB page)
        mov eax, edx
        shl eax, 3      ; * 8 sectors
        add eax, SWAP_START_SECTOR
        
        ; get physical address
        mov edi, [ebx + 4]
        
        ; write 8 sectors (4KB)
        mov ecx, 8
        .write_sectors:
            push eax
            push ecx
            call write_disk_sector
            pop ecx
            pop eax
            inc eax
            add edi, 512
            loop .write_sectors
        
        ; update page state
        mov byte [ebx], PAGE_SWAPPED
        mov dword [ebx + 8], edx    ; store swap slot in compressed_size field
        
        ; update stats
        dec dword [page_stats_cold]
        inc dword [page_stats_swapped]
        inc dword [swap_write_count]
        inc dword [free_page_count]
    
    .done:
        popa
        ret

; swap page in from disk
; eax = page index
swap_page_in:
    pusha
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page is swapped
    cmp byte [ebx], PAGE_SWAPPED
    jne .done
    
    ; get swap slot
    mov edx, [ebx + 8]
    
    ; calculate disk sector
    mov eax, edx
    shl eax, 3
    add eax, SWAP_START_SECTOR
    
    ; get physical address
    mov edi, [ebx + 4]
    
    ; read 8 sectors (4KB)
    mov ecx, 8
    .read_sectors:
        push eax
        push ecx
        call read_disk_sector
        pop ecx
        pop eax
        inc eax
        add edi, 512
        loop .read_sectors
    
    ; free swap slot
    mov eax, edx
    call free_swap_slot
    
    ; update page state
    mov byte [ebx], PAGE_COLD   ; mark as cold initially
    mov dword [ebx + 8], 0
    
    ; update stats
    dec dword [page_stats_swapped]
    inc dword [page_stats_cold]
    inc dword [swap_read_count]
    dec dword [free_page_count]
    
    .done:
        popa
        ret
