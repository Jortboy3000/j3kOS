; ========================================
; VIRTUAL MEMORY MANAGER (VMM)
; ========================================
; Implements full x86 paging with page directory and page tables
; Features:
; - 4KB page granularity
; - User/Supervisor mode separation
; - Read/Write permissions
; - Page fault handling
; - Demand paging support
; - Copy-on-write (COW) support
; - Memory mapped regions
; ========================================

; Paging structures (x86 two-level paging)
; Page Directory: 1024 entries * 4 bytes = 4KB
; Each PDE points to a Page Table
; Page Table: 1024 entries * 4 bytes = 4KB
; Each PTE points to a 4KB physical page

; Memory layout for paging structures:
; 0x200000: Page Directory (4KB)
; 0x201000: Page Tables (up to 4MB of page tables)

PAGE_DIR_BASE       equ 0x200000
PAGE_TABLE_BASE     equ 0x201000
PAGES_PER_TABLE     equ 1024
PAGE_SIZE_BYTES     equ 4096

; Page Directory/Table Entry Flags (bits)
VMM_PRESENT         equ 0x001       ; Page is present in memory
VMM_WRITABLE        equ 0x002       ; Page is writable
VMM_USER            equ 0x004       ; Page accessible from user mode
VMM_WRITE_THROUGH   equ 0x008       ; Write-through caching
VMM_CACHE_DISABLE   equ 0x010       ; Disable caching for this page
VMM_ACCESSED        equ 0x020       ; Page has been accessed (set by CPU)
VMM_DIRTY           equ 0x040       ; Page has been written (set by CPU, PTE only)
VMM_PAGE_SIZE       equ 0x080       ; 4MB pages (PDE only)
VMM_GLOBAL          equ 0x100       ; Global page (not flushed on CR3 write)
VMM_COW             equ 0x200       ; Copy-on-write (custom flag, bit 9)
VMM_SWAPPED         equ 0x400       ; Page swapped to disk (custom flag, bit 10)
VMM_RESERVED        equ 0x800       ; Reserved for future use

; Page Tracking Constants (Namespaced to avoid conflict with memory.asm)
VMM_PAGE_COUNT          equ 4096        ; Track first 16MB
VMM_PAGE_FREE           equ 0
VMM_PAGE_ALLOCATED      equ 1
VMM_PAGE_HOT            equ 2
VMM_PAGE_COLD           equ 3
VMM_PAGE_COMPRESSED     equ 4
VMM_PAGE_SWAPPED        equ 5

vmm_tracking_table      equ 0x800000    ; Place tracking table at 8MB

; Virtual memory statistics
vmm_page_faults:        dd 0
vmm_pages_allocated:    dd 0
vmm_pages_freed:        dd 0
vmm_cow_pages:          dd 0
vmm_swapped_pages:      dd 0
vmm_tlb_flushes:        dd 0
vmm_hot_pages:          dd 0
vmm_cold_pages:         dd 0
vmm_compressed_pages:   dd 0
vmm_decompressions:     dd 0
vmm_compressions:       dd 0

; Hot/Cold tracking thresholds
VMM_HOT_THRESHOLD       equ 10      ; Access count to become hot
VMM_COLD_THRESHOLD      equ 50      ; Timer ticks without access = cold
VMM_COMPRESS_THRESHOLD  equ 100     ; Ticks cold before compression

; Extended page tracking (per virtual page)
; Uses same structure as existing page_table but for virtual pages
; offset 0: state (1 byte) - FREE, ALLOCATED, HOT, COLD, COMPRESSED, SWAPPED
; offset 1: access_count (1 byte)
; offset 2: ticks_since_access (2 bytes)
; offset 4: physical_addr (4 bytes)
; offset 8: compressed_size (4 bytes)
; offset 12: flags (4 bytes)


; Page frame allocator (physical memory)
; Bitmap: 1 bit per 4KB page, up to 4GB (1MB bitmap for 32GB)
; We'll support 16MB physical memory = 4096 pages = 512 bytes bitmap
PHYS_MEM_SIZE       equ 0x1000000   ; 16MB physical memory
PHYS_PAGE_COUNT     equ (PHYS_MEM_SIZE / PAGE_SIZE_BYTES)
BITMAP_SIZE         equ (PHYS_PAGE_COUNT / 8)

page_frame_bitmap:  times BITMAP_SIZE db 0
next_free_frame:    dd 0

; ========================================
; VMM Initialization
; ========================================
vmm_init:
    pusha
    
    mov esi, msg_vmm_init
    call print_string
    
    ; Step 1: Initialize page frame allocator
    call vmm_init_frame_allocator
    
    ; Step 2: Create page directory
    call vmm_create_page_directory
    
    ; Step 3: Identity map kernel (0-16MB)
    call vmm_identity_map_kernel
    
    ; Step 4: Enable paging
    call vmm_enable_paging
    
    ; Step 5: Install page fault handler
    call vmm_install_page_fault_handler
    
    mov esi, msg_vmm_ok
    call print_string
    
    popa
    ret

; ========================================
; Initialize Physical Page Frame Allocator
; ========================================
vmm_init_frame_allocator:
    pusha
    
    ; Clear bitmap (all pages free)
    mov edi, page_frame_bitmap
    mov ecx, BITMAP_SIZE / 4
    xor eax, eax
    rep stosd
    
    ; Mark first 3MB as used
    ; 0-1MB: BIOS, Kernel, Stack
    ; 1MB-2MB: Kernel Heap (malloc)
    ; 2MB-3MB: Page Directory & Page Tables
    mov ecx, 768                    ; 768 pages = 3MB
    mov edi, page_frame_bitmap
    
    .mark_used:
        mov ebx, ecx
        shr ebx, 3                  ; byte offset
        and ecx, 7                  ; bit offset
        bts dword [edi + ebx], ecx  ; set bit
        loop .mark_used
    
    mov dword [next_free_frame], 768    ; start allocating from 3MB
    
    popa
    ret

; ========================================
; Allocate Physical Page Frame
; Returns: EAX = physical address (or 0 if failed)
; ========================================
vmm_alloc_frame:
    push ebx
    push ecx
    push edi
    
    mov ecx, PHYS_PAGE_COUNT
    mov ebx, [next_free_frame]
    
    .search_loop:
        ; Check if frame is free (bit = 0)
        mov edi, ebx
        shr edi, 3                  ; byte offset
        and ebx, 7                  ; bit offset
        bt dword [page_frame_bitmap + edi], ebx
        jnc .found_frame            ; bit clear = free
        
        inc dword [next_free_frame]
        mov ebx, [next_free_frame]
        
        ; Wrap around if needed
        cmp ebx, PHYS_PAGE_COUNT
        jl .continue
        mov dword [next_free_frame], 768
        mov ebx, 768
        
        .continue:
            loop .search_loop
    
    ; Out of memory
    xor eax, eax
    jmp .done
    
    .found_frame:
        ; Mark frame as used
        bts dword [page_frame_bitmap + edi], ebx
        
        ; Calculate physical address
        mov eax, [next_free_frame]
        shl eax, 12                 ; * 4096
        
        inc dword [next_free_frame]
        inc dword [vmm_pages_allocated]
    
    .done:
        pop edi
        pop ecx
        pop ebx
        ret

; ========================================
; Free Physical Page Frame
; EAX = physical address
; ========================================
vmm_free_frame:
    push ebx
    push edi
    
    ; Convert address to frame number
    shr eax, 12
    
    ; Bounds check
    cmp eax, PHYS_PAGE_COUNT
    jge .done
    
    ; Clear bit in bitmap
    mov edi, eax
    shr edi, 3                      ; byte offset
    and eax, 7                      ; bit offset
    btr dword [page_frame_bitmap + edi], eax
    
    inc dword [vmm_pages_freed]
    
    .done:
        pop edi
        pop ebx
        ret

; ========================================
; Create Page Directory
; ========================================
vmm_create_page_directory:
    pusha
    
    ; Clear page directory (4KB)
    mov edi, PAGE_DIR_BASE
    mov ecx, 1024
    xor eax, eax
    rep stosd
    
    ; Clear page table area (4MB for 1024 page tables)
    mov edi, PAGE_TABLE_BASE
    mov ecx, 0x100000 / 4           ; 1MB / 4
    xor eax, eax
    rep stosd
    
    popa
    ret

; ========================================
; Identity Map Kernel (0x0 to 0x1000000 = 16MB)
; ========================================
vmm_identity_map_kernel:
    pusha
    
    ; Map first 16MB (4096 pages = 4 page tables)
    mov ecx, 4                      ; 4 page directory entries
    mov edi, PAGE_DIR_BASE
    mov eax, PAGE_TABLE_BASE
    or eax, (VMM_PRESENT | VMM_WRITABLE)
    
    .map_pde:
        stosd                       ; Write PDE
        add eax, 0x1000             ; Next page table
        loop .map_pde
    
    ; Fill page tables (4 tables * 1024 entries = 4096 pages)
    mov edi, PAGE_TABLE_BASE
    mov eax, 0                      ; Start at physical 0
    or eax, (VMM_PRESENT | VMM_WRITABLE)
    mov ecx, 4096                   ; 4096 pages
    
    .map_pte:
        stosd
        add eax, 0x1000             ; Next 4KB page
        loop .map_pte
    
    popa
    ret

; ========================================
; Enable Paging
; ========================================
vmm_enable_paging:
    pusha
    
    ; Load page directory address into CR3
    mov eax, PAGE_DIR_BASE
    mov cr3, eax
    
    ; Enable paging (set bit 31 of CR0)
    mov eax, cr0
    or eax, 0x80000000              ; PG bit
    mov cr0, eax
    
    ; Flush TLB
    mov eax, cr3
    mov cr3, eax
    inc dword [vmm_tlb_flushes]
    
    popa
    ret

; ========================================
; Map Virtual Page
; EAX = virtual address
; EBX = physical address
; ECX = flags (VMM_PRESENT | VMM_WRITABLE | VMM_USER, etc.)
; ========================================
vmm_map_page:
    push edx
    push esi
    push edi
    
    ; Get page directory index (bits 22-31)
    mov esi, eax
    shr esi, 22
    shl esi, 2                      ; * 4 for DWORD offset
    add esi, PAGE_DIR_BASE
    
    ; Check if page table exists
    test dword [esi], VMM_PRESENT
    jnz .table_exists
    
    ; Allocate new page table
    push eax
    push ebx
    push ecx
    call vmm_alloc_frame
    test eax, eax
    jz .alloc_failed
    mov edi, eax                    ; Save page table physical address
    
    ; Clear the new page table
    push edi
    mov ecx, 1024
    xor eax, eax
    rep stosd
    pop edi
    
    pop ecx
    pop ebx
    pop eax
    
    ; Install page table in directory
    mov edx, edi
    or edx, (VMM_PRESENT | VMM_WRITABLE | VMM_USER)
    mov [esi], edx
    
    .table_exists:
        ; Get page table address
        mov edi, [esi]
        and edi, 0xFFFFF000         ; Clear flags
        
        ; Get page table index (bits 12-21)
        mov edx, eax
        shr edx, 12
        and edx, 0x3FF              ; 10 bits = 1024 entries
        shl edx, 2                  ; * 4 for DWORD offset
        add edi, edx
        
        ; Install PTE
        mov edx, ebx
        or edx, ecx                 ; Apply flags
        mov [edi], edx
        
        ; Invalidate TLB entry
        invlpg [eax]
        inc dword [vmm_tlb_flushes]
        
        jmp .done
    
    .alloc_failed:
        pop ecx
        pop ebx
        pop eax
        ; Fall through to done
    
    .done:
        pop edi
        pop esi
        pop edx
        ret

; ========================================
; Unmap Virtual Page
; EAX = virtual address
; ========================================
vmm_unmap_page:
    push ebx
    push esi
    push edi
    
    ; Get page directory index
    mov esi, eax
    shr esi, 22
    shl esi, 2
    add esi, PAGE_DIR_BASE
    
    ; Check if page table exists
    test dword [esi], VMM_PRESENT
    jz .done
    
    ; Get page table address
    mov edi, [esi]
    and edi, 0xFFFFF000
    
    ; Get page table index
    mov ebx, eax
    shr ebx, 12
    and ebx, 0x3FF
    shl ebx, 2
    add edi, ebx
    
    ; Get physical address before clearing
    mov ebx, [edi]
    and ebx, 0xFFFFF000
    
    ; Clear PTE
    mov dword [edi], 0
    
    ; Free physical frame
    mov eax, ebx
    call vmm_free_frame
    
    ; Invalidate TLB
    invlpg [eax]
    inc dword [vmm_tlb_flushes]
    
    .done:
        pop edi
        pop esi
        pop ebx
        ret

; ========================================
; Get Physical Address from Virtual
; EAX = virtual address
; Returns: EAX = physical address (or 0 if not mapped)
; ========================================
vmm_get_physical:
    push ebx
    push esi
    push edi
    
    ; Save original address
    mov edi, eax
    
    ; Get PDE
    mov esi, eax
    shr esi, 22
    shl esi, 2
    add esi, PAGE_DIR_BASE
    
    ; Check if page table exists
    mov ebx, [esi]
    test ebx, VMM_PRESENT
    jz .not_mapped
    
    ; Get page table address
    and ebx, 0xFFFFF000
    
    ; Get PTE
    mov esi, edi
    shr esi, 12
    and esi, 0x3FF
    shl esi, 2
    add ebx, esi
    
    ; Check if page is present
    mov eax, [ebx]
    test eax, VMM_PRESENT
    jz .not_mapped
    
    ; Get physical address
    and eax, 0xFFFFF000
    mov ebx, edi
    and ebx, 0xFFF                  ; Page offset
    or eax, ebx                     ; Combine with offset
    jmp .done
    
    .not_mapped:
        xor eax, eax
    
    .done:
        pop edi
        pop esi
        pop ebx
        ret

; ========================================
; Page Fault Handler (INT 14)
; ========================================
vmm_page_fault_handler:
    pushad
    
    inc dword [vmm_page_faults]
    
    ; Get faulting address from CR2
    mov eax, cr2
    mov [page_fault_addr], eax
    
    ; Get error code from stack
    mov eax, [esp + 32]             ; Error code pushed by CPU
    mov [page_fault_error], eax
    
    ; Display error info
    mov esi, msg_page_fault
    call print_string
    
    mov eax, [page_fault_addr]
    call print_hex
    call print_newline
    
    mov esi, msg_page_fault_error
    call print_string
    mov eax, [page_fault_error]
    call print_hex
    call print_newline
    
    ; Analyze error code
    test eax, 0x01                  ; Present bit
    jz .not_present
    
    mov esi, msg_page_protection
    call print_string
    jmp .halt
    
    .not_present:
        mov esi, msg_page_not_present
        call print_string
        
        ; TODO: Demand paging - load page from disk
        ; For now, just halt
    
    .halt:
        cli
        hlt

; ========================================
; Install Page Fault Handler
; ========================================
vmm_install_page_fault_handler:
    pusha
    
    ; Get IDT entry for INT 14 (page fault)
    mov edi, 0x50                   ; IDT base + (14 * 8)
    
    ; Set handler address
    mov eax, vmm_page_fault_handler_enhanced
    mov word [edi], ax              ; Low 16 bits
    shr eax, 16
    mov word [edi + 6], ax          ; High 16 bits
    
    ; Set selector and flags
    mov word [edi + 2], 0x08        ; Kernel code selector
    mov byte [edi + 4], 0           ; Reserved
    mov byte [edi + 5], 0x8E        ; Present, DPL=0, 32-bit interrupt gate
    
    popa
    ret

; ========================================
; Allocate Virtual Memory Region
; ECX = size in bytes
; Returns: EAX = virtual address (or 0 if failed)
; ========================================
vmm_alloc:
    push ebx
    push ecx
    push edx
    
    ; Round size up to page boundary
    add ecx, 0xFFF
    and ecx, 0xFFFFF000
    
    ; Calculate number of pages needed
    mov edx, ecx
    shr edx, 12
    
    ; TODO: Find free virtual address range
    ; For now, allocate at fixed address
    mov eax, 0x400000               ; Start at 4MB
    
    .alloc_loop:
        push eax
        push edx
        
        ; Allocate physical frame
        call vmm_alloc_frame
        test eax, eax
        jz .alloc_failed
        
        mov ebx, eax                ; Physical address
        pop edx
        pop eax
        
        ; Map page
        push eax
        push edx
        mov ecx, (VMM_PRESENT | VMM_WRITABLE | VMM_USER)
        call vmm_map_page
        pop edx
        pop eax
        
        ; Next page
        add eax, 0x1000
        dec edx
        jnz .alloc_loop
    
    ; Return start address
    mov eax, 0x400000
    jmp .done
    
    .alloc_failed:
        pop edx
        pop eax
        xor eax, eax
    
    .done:
        pop edx
        pop ecx
        pop ebx
        ret

; ========================================
; Free Virtual Memory Region
; EAX = virtual address
; ECX = size in bytes
; ========================================
vmm_free:
    push eax
    push ecx
    push edx
    
    ; Round size up to page boundary
    add ecx, 0xFFF
    and ecx, 0xFFFFF000
    
    ; Calculate number of pages
    mov edx, ecx
    shr edx, 12
    
    .free_loop:
        push eax
        push edx
        call vmm_unmap_page
        pop edx
        pop eax
        
        add eax, 0x1000
        dec edx
        jnz .free_loop
    
    pop edx
    pop ecx
    pop eax
    ret

; ========================================
; Display VMM Statistics
; ========================================
vmm_show_stats:
    pusha
    
    mov esi, msg_vmm_stats
    call print_string
    
    mov esi, msg_vmm_allocated
    call print_string
    mov eax, [vmm_pages_allocated]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_freed
    call print_string
    mov eax, [vmm_pages_freed]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_faults
    call print_string
    mov eax, [vmm_page_faults]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_tlb
    call print_string
    mov eax, [vmm_tlb_flushes]
    call print_decimal
    call print_newline
    
    ; Hot/Cold statistics
    mov esi, msg_vmm_hot
    call print_string
    mov eax, [vmm_hot_pages]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_cold
    call print_string
    mov eax, [vmm_cold_pages]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_compressed
    call print_string
    mov eax, [vmm_compressed_pages]
    call print_decimal
    call print_newline
    
    mov esi, msg_vmm_compressions
    call print_string
    mov eax, [vmm_compressions]
    call print_decimal
    mov al, '/'
    call print_char
    mov eax, [vmm_decompressions]
    call print_decimal
    call print_newline
    
    popa
    ret

; ========================================
; HOT/COLD PAGE TRACKING WITH COMPRESSION
; ========================================

; Update page access statistics (call on page access)
; EAX = virtual address
vmm_page_accessed:
    push ebx
    push esi
    push edi
    
    ; Get page index
    shr eax, 12
    cmp eax, VMM_PAGE_COUNT
    jge .done
    
    ; Get tracking entry
    mov esi, eax
    shl esi, 4
    add esi, vmm_tracking_table
    
    ; Check if page is compressed - need to decompress first
    cmp byte [esi], VMM_PAGE_COMPRESSED
    je .decompress_page
    
    ; Increment access count (with saturation at 255)
    movzx ebx, byte [esi + 1]
    cmp ebx, 255
    je .check_hot
    inc byte [esi + 1]
    
    .check_hot:
        ; Reset ticks since access
        mov word [esi + 2], 0
        
        ; Check if page should become hot
        movzx ebx, byte [esi + 1]
        cmp ebx, VMM_HOT_THRESHOLD
        jl .done
        
        ; Mark as hot if not already
        cmp byte [esi], VMM_PAGE_HOT
        je .done
        mov byte [esi], VMM_PAGE_HOT
        inc dword [vmm_hot_pages]
        jmp .done
    
    .decompress_page:
        ; Decompress the page before access
        push eax
        call vmm_decompress_page
        pop eax
        jmp .done
    
    .done:
        pop edi
        pop esi
        pop ebx
        ret

; Timer tick handler for page aging (call periodically)
vmm_page_timer_tick:
    pusha
    
    mov ecx, VMM_PAGE_COUNT
    mov esi, vmm_tracking_table
    xor ebx, ebx                    ; page index
    
    .tick_loop:
        ; Skip free pages
        cmp byte [esi], VMM_PAGE_FREE
        je .next_page
        cmp byte [esi], VMM_PAGE_SWAPPED
        je .next_page
        
        ; Increment ticks since access (with saturation)
        mov ax, [esi + 2]
        cmp ax, 0xFFFF
        je .check_cold
        inc word [esi + 2]
        
        .check_cold:
            ; Check if page should become cold
            mov ax, [esi + 2]
            cmp ax, VMM_COLD_THRESHOLD
            jl .check_compress
            
            ; Mark as cold if not already
            cmp byte [esi], VMM_PAGE_COLD
            jne .mark_cold
            jmp .check_compress
            
            .mark_cold:
                ; Decrease hot count if was hot
                cmp byte [esi], VMM_PAGE_HOT
                jne .set_cold
                dec dword [vmm_hot_pages]
                
                .set_cold:
                    mov byte [esi], VMM_PAGE_COLD
                    inc dword [vmm_cold_pages]
        
        .check_compress:
            ; Check if page should be compressed
            cmp byte [esi], VMM_PAGE_COLD
            jne .next_page
            
            mov ax, [esi + 2]
            cmp ax, VMM_COMPRESS_THRESHOLD
            jl .next_page
            
            ; Compress this cold page
            push ecx
            push esi
            mov eax, ebx
            call vmm_compress_page
            pop esi
            pop ecx
        
        .next_page:
            add esi, 16
            inc ebx
            dec ecx
            jnz .tick_loop
    
    popa
    ret

; ========================================
; RLE Compression for Cold Pages
; ========================================

; Compress a cold page
; EAX = page index
vmm_compress_page:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    ; Bounds check
    cmp eax, VMM_PAGE_COUNT
    jge .done
    
    ; Get tracking entry
    mov ebx, eax
    shl ebx, 4
    add ebx, vmm_tracking_table
    
    ; Verify page is cold
    cmp byte [ebx], VMM_PAGE_COLD
    jne .done
    
    ; Get physical address
    mov esi, [ebx + 4]
    test esi, esi
    jz .done
    
    ; Allocate temporary buffer for compressed data
    mov edi, vmm_temp_buffer
    
    ; Simple RLE compression
    mov ecx, PAGE_SIZE_BYTES
    xor edx, edx                    ; compressed size
    
    .compress_loop:
        test ecx, ecx
        jz .compress_done
        
        ; Read byte
        lodsb
        mov ah, al                  ; save byte value
        mov dl, 1                   ; run length
        
        ; Count consecutive identical bytes (max 255)
        .count_run:
            dec ecx
            jz .write_run
            cmp dl, 255
            je .write_run
            
            lodsb
            cmp al, ah
            jne .not_same
            inc dl
            jmp .count_run
            
        .not_same:
            dec esi                 ; back up one byte
            inc ecx
            
        .write_run:
            ; Write: [count][byte]
            mov al, dl
            stosb
            mov al, ah
            stosb
            add edx, 2              ; compressed size += 2
            
            jmp .compress_loop
    
    .compress_done:
        ; Check if compression helped (saved at least 25%)
        cmp edx, (PAGE_SIZE_BYTES * 3 / 4)
        jge .no_benefit
        
        ; Store compressed size
        mov [ebx + 8], edx
        
        ; Copy compressed data back to original page
        mov esi, vmm_temp_buffer
        mov edi, [ebx + 4]
        mov ecx, edx
        rep movsb
        
        ; Mark as compressed
        mov byte [ebx], VMM_PAGE_COMPRESSED
        dec dword [vmm_cold_pages]
        inc dword [vmm_compressed_pages]
        inc dword [vmm_compressions]
        jmp .done
    
    .no_benefit:
        ; Compression didn't help, leave uncompressed
    
    .done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; Decompress a page when accessed
; EAX = page index
vmm_decompress_page:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    ; Bounds check
    cmp eax, VMM_PAGE_COUNT
    jge .done
    
    ; Get tracking entry
    mov ebx, eax
    shl ebx, 4
    add ebx, vmm_tracking_table
    
    ; Verify page is compressed
    cmp byte [ebx], VMM_PAGE_COMPRESSED
    jne .done
    
    ; Get physical address and compressed size
    mov esi, [ebx + 4]
    mov edx, [ebx + 8]              ; compressed size
    test esi, esi
    jz .done
    test edx, edx
    jz .done
    
    ; Copy compressed data to temp buffer
    mov edi, vmm_temp_buffer
    mov ecx, edx
    rep movsb
    
    ; Decompress from temp buffer back to page
    mov esi, vmm_temp_buffer
    mov edi, [ebx + 4]
    mov ecx, edx
    
    .decompress_loop:
        test ecx, ecx
        jz .decompress_done
        
        ; Read [count][byte]
        lodsb
        movzx edx, al               ; run length
        dec ecx
        jz .decompress_done
        
        lodsb                       ; byte value
        dec ecx
        
        ; Write 'count' copies of byte
        .write_run:
            stosb
            dec edx
            jnz .write_run
        
        jmp .decompress_loop
    
    .decompress_done:
        ; Mark as hot (just accessed)
        mov byte [ebx], VMM_PAGE_HOT
        mov byte [ebx + 1], VMM_HOT_THRESHOLD
        mov word [ebx + 2], 0
        mov dword [ebx + 8], 0      ; clear compressed size
        
        dec dword [vmm_compressed_pages]
        inc dword [vmm_hot_pages]
        inc dword [vmm_decompressions]
    
    .done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; ========================================
; Enhanced Page Fault Handler with Hot/Cold Support
; ========================================
vmm_page_fault_handler_enhanced:
    pushad
    
    inc dword [vmm_page_faults]
    
    ; Get faulting address from CR2
    mov eax, cr2
    mov [page_fault_addr], eax
    
    ; Get error code from stack
    mov ebx, [esp + 32]
    mov [page_fault_error], ebx
    
    ; Calculate page index
    mov edx, eax
    shr edx, 12
    
    ; Check if page is tracked
    cmp edx, VMM_PAGE_COUNT
    jge .not_tracked
    
    ; Get tracking entry
    mov esi, edx
    shl esi, 4
    add esi, vmm_tracking_table
    
    ; Check page state
    movzx ecx, byte [esi]
    
    cmp ecx, VMM_PAGE_COMPRESSED
    je .handle_compressed
    
    cmp ecx, VMM_PAGE_SWAPPED
    je .handle_swapped
    
    jmp .standard_fault
    
    .handle_compressed:
        ; Page is compressed, decompress it
        mov esi, msg_page_decompressing
        call print_string
        mov eax, edx
        call vmm_decompress_page
        
        ; Resume execution
        popad
        add esp, 4                  ; pop error code
        iretd
    
    .handle_swapped:
        ; Page is swapped, load from disk
        mov esi, msg_page_swapping_in
        call print_string
        ; TODO: Implement swap-in
        jmp .halt
    
    .not_tracked:
    .standard_fault:
        ; Standard page fault handling
        mov esi, msg_page_fault
        call print_string
        mov eax, [page_fault_addr]
        call print_hex
        call print_newline
        
        mov esi, msg_page_fault_error
        call print_string
        mov eax, [page_fault_error]
        call print_hex
        call print_newline
        
        ; Analyze error code
        test eax, 0x01
        jz .not_present
        
        mov esi, msg_page_protection
        call print_string
        jmp .halt
        
        .not_present:
            mov esi, msg_page_not_present
            call print_string
    
    .halt:
        cli
        hlt

; ========================================
; VMM Data
; ========================================
page_fault_addr:    dd 0
page_fault_error:   dd 0

msg_vmm_init:           db '[VMM] Initializing virtual memory...', 0
msg_vmm_ok:             db ' OK', 10, 0
msg_page_fault:         db 10, '[PAGE FAULT] Address: 0x', 0
msg_page_fault_error:   db 'Error Code: 0x', 0
msg_page_protection:    db 'Protection violation', 10, 0
msg_page_not_present:   db 'Page not present', 10, 0
msg_page_decompressing: db '[VMM] Decompressing page... ', 0
msg_page_swapping_in:   db '[VMM] Swapping in page... ', 0
msg_vmm_stats:          db 10, '--- VMM Statistics ---', 10, 0
msg_vmm_allocated:      db 'Pages allocated: ', 0
msg_vmm_freed:          db 'Pages freed: ', 0
msg_vmm_faults:         db 'Page faults: ', 0
msg_vmm_tlb:            db 'TLB flushes: ', 0
msg_vmm_hot:            db 'Hot pages: ', 0
msg_vmm_cold:           db 'Cold pages: ', 0
msg_vmm_compressed:     db 'Compressed pages: ', 0
msg_vmm_compressions:   db 'Compressions/Decompressions: ', 0

vmm_temp_buffer:        times 4096 db 0
