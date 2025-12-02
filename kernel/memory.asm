; ========================================
; MEMORY ALLOCATOR - MALLOC/FREE
; ========================================
; Memory Layout (after kernel loads):
;   0x00000000 - 0x000003FF : Real mode IVT (1KB)
;   0x00000400 - 0x000004FF : BIOS Data Area (256 bytes)
;   0x00000500 - 0x00007BFF : Free conventional memory (~29KB)
;   0x00007C00 - 0x00007DFF : Boot sector (512 bytes)
;   0x00007E00 - 0x00007FFF : Boot scratch space (512 bytes)
;   0x00008000 - 0x0000FFFF : Free (~32KB)
;   0x00010000 - 0x0001FFFF : Kernel code/data (~64KB actual, 120 sectors max)
;   0x00020000 - 0x0008FFFF : Free (~448KB)
;   0x00090000 - 0x0009FFFF : Stack (grows down, 64KB)
;   0x000A0000 - 0x000BFFFF : VGA video memory (128KB)
;   0x000C0000 - 0x000FFFFF : BIOS ROM area (256KB)
;   0x00100000 - 0x001FFFFF : Heap (1MB) ← malloc/free uses this
;   0x00200000+             : Extended memory (for future expansion)

; heap starts at 1MB (after kernel and stack)
HEAP_START equ 0x100000
HEAP_SIZE equ 0x100000      ; 1MB heap

; block header structure (16 bytes):
; offset 0: size (4 bytes)
; offset 4: is_free flag (4 bytes) - 1 if free, 0 if allocated
; offset 8: next block pointer (4 bytes)
; offset 12: magic number (4 bytes) - 0xDEADBEEF
BLOCK_HEADER_SIZE equ 16
HEAP_MAGIC equ 0xDEADBEEF

; page management for hot/cold memory
PAGE_SIZE equ 4096
PAGE_COUNT equ 256          ; track 256 pages (1MB / 4KB)
PAGE_HOT_THRESHOLD equ 10   ; accesses before page is "hot"
PAGE_COLD_THRESHOLD equ 2   ; ticks without access = "cold"

; page states
PAGE_FREE equ 0
PAGE_ALLOCATED equ 1
PAGE_HOT equ 2
PAGE_COLD equ 3
PAGE_COMPRESSED equ 4
PAGE_SWAPPED equ 5

heap_initialized: dd 0
heap_first_block: dd HEAP_START

; page tracking table (16 bytes per page)
; offset 0: state (1 byte)
; offset 1: access_count (1 byte)
; offset 2: ticks_since_access (2 bytes)
; offset 4: physical_addr (4 bytes)
; offset 8: compressed_size (4 bytes)
; offset 12: flags (4 bytes)
page_table: times (PAGE_COUNT * 16) db 0
page_stats_hot: dd 0
page_stats_cold: dd 0
page_stats_compressed: dd 0
page_stats_swapped: dd 0

; memory pressure management
memory_pressure: dd 0           ; 0=low, 1=medium, 2=high
free_page_count: dd PAGE_COUNT
compress_on_cold: db 1          ; auto-compress when page becomes cold

; initialize the heap
init_heap:
    pusha
    
    ; check if already initialized
    cmp dword [heap_initialized], 1
    je .done
    
    ; set up the first free block
    mov edi, HEAP_START
    mov dword [edi], HEAP_SIZE - BLOCK_HEADER_SIZE  ; size
    mov dword [edi + 4], 1                          ; is_free = true
    mov dword [edi + 8], 0                          ; next = NULL
    mov dword [edi + 12], HEAP_MAGIC                ; magic
    
    mov dword [heap_initialized], 1
    
    .done:
        popa
        ret

; malloc - allocate memory
; ECX = size in bytes
; returns EAX = pointer to allocated memory (or 0 if failed)
malloc:
    push ebx
    push edx
    push esi
    push edi
    
    ; validate input
    test ecx, ecx
    jz .invalid_size
    
    ; check for overflow (max allocation 256KB)
    cmp ecx, 0x40000
    ja .invalid_size
    
    ; make sure heap is initialized
    call init_heap
    
    ; align size to 16 bytes for better cache performance
    add ecx, 15
    and ecx, 0xFFFFFFF0
    
    ; find a free block that fits (first-fit algorithm)
    mov esi, HEAP_START
    
    .find_loop:
        ; bounds check - make sure we're still in heap
        mov eax, esi
        sub eax, HEAP_START
        cmp eax, HEAP_SIZE
        jae .not_found
        
        ; check if this is a valid block
        cmp dword [esi + 12], HEAP_MAGIC
        jne .not_found
        
        ; is it free?
        cmp dword [esi + 4], 1
        jne .next_block
        
        ; is it big enough?
        mov eax, [esi]      ; block size
        cmp eax, ecx
        jl .next_block
        
        ; found a good block! allocate it
        mov dword [esi + 4], 0  ; mark as allocated
        
        ; TODO: split block if it's much larger than needed
        ; (optimization for later)
        
        ; return pointer (skip header)
        lea eax, [esi + BLOCK_HEADER_SIZE]
        jmp .done
        
        .next_block:
            mov esi, [esi + 8]  ; next block
            test esi, esi
            jnz .find_loop
    
    .not_found:
    .invalid_size:
        xor eax, eax        ; return NULL
    
    .done:
        pop edi
        pop esi
        pop edx
        pop ebx
        ret

; free - deallocate memory
; EAX = pointer to memory
free:
    push ebx
    push esi
    push edi
    
    ; validate pointer is not NULL
    test eax, eax
    jz .invalid
    
    ; validate pointer is within heap bounds
    cmp eax, HEAP_START + BLOCK_HEADER_SIZE
    jb .invalid
    mov ebx, HEAP_START + HEAP_SIZE
    cmp eax, ebx
    jae .invalid
    
    ; get block header (pointer - 16)
    sub eax, BLOCK_HEADER_SIZE
    mov esi, eax
    
    ; verify magic number
    cmp dword [esi + 12], HEAP_MAGIC
    jne .invalid
    
    ; check if already free (double-free protection)
    cmp dword [esi + 4], 1
    je .invalid
    
    ; mark as free
    mov dword [esi + 4], 1
    
    ; TODO: coalesce adjacent free blocks
    ; (optimization for later to reduce fragmentation)
    
    .invalid:
        pop edi
        pop esi
        pop ebx
        ret

; ========================================
; PAGE MANAGEMENT - HOT/COLD MEMORY
; ========================================
; Advanced memory management with page tracking, compression, and swapping
; Pages can be: FREE, ALLOCATED, HOT (frequently accessed), COLD (rarely used),
; COMPRESSED (RLE compressed in memory), or SWAPPED (saved to disk)

; initialize page management system
init_page_mgmt:
    pusha
    
    ; mark all pages as free initially
    mov ecx, PAGE_COUNT
    mov edi, page_table
    xor eax, eax
    .init_loop:
        stosb               ; state = FREE
        stosb               ; access_count = 0
        stosw               ; ticks_since_access = 0
        stosd               ; physical_addr = 0
        stosd               ; compressed_size = 0
        stosd               ; flags = 0
        loop .init_loop
    
    popa
    ret

; allocate a page (4KB)
; returns EAX = page index (or -1 if failed)
alloc_page:
    push ebx
    push ecx
    push edi
    
    ; find first free page
    mov ecx, PAGE_COUNT
    mov edi, page_table
    xor ebx, ebx
    
    .search_loop:
        cmp byte [edi], PAGE_FREE
        je .found_page
        add edi, 16
        inc ebx
        loop .search_loop
    
    ; no free pages
    mov eax, -1
    jmp .done
    
    .found_page:
        ; mark as allocated
        mov byte [edi], PAGE_ALLOCATED
        mov byte [edi + 1], 0           ; access_count = 0
        mov word [edi + 2], 0           ; ticks_since_access = 0
        
        ; calculate physical address
        mov eax, ebx
        shl eax, 12                     ; * 4096
        add eax, HEAP_START
        mov [edi + 4], eax              ; store physical addr
        
        ; update free count
        dec dword [free_page_count]
        
        mov eax, ebx                    ; return page index
    
    .done:
        pop edi
        pop ecx
        pop ebx
        ret

; free a page
; EAX = page index
free_page:
    push ebx
    push edi
    
    ; bounds check
    cmp eax, PAGE_COUNT
    jge .done
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4                          ; * 16
    add ebx, page_table
    
    ; check if compressed/swapped, need to free that too
    cmp byte [ebx], PAGE_COMPRESSED
    je .free_compressed
    cmp byte [ebx], PAGE_SWAPPED
    je .free_swapped
    jmp .mark_free
    
    .free_compressed:
        dec dword [page_stats_compressed]
        jmp .mark_free
    
    .free_swapped:
        dec dword [page_stats_swapped]
        jmp .mark_free
    
    .mark_free:
        mov byte [ebx], PAGE_FREE
        mov dword [ebx + 4], 0
        mov dword [ebx + 8], 0
        
        ; update free count
        inc dword [free_page_count]
    
    .done:
        pop edi
        pop ebx
        ret

; access a page (track for hot/cold)
; EAX = page index
access_page:
    push ebx
    push edi
    
    ; bounds check
    cmp eax, PAGE_COUNT
    jge .done
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page is swapped out - need to swap in first
    cmp byte [ebx], PAGE_SWAPPED
    jne .not_swapped
    
    push eax
    call swap_page_in
    pop eax
    
    .not_swapped:
    ; increment access count
    inc byte [ebx + 1]
    mov word [ebx + 2], 0               ; reset ticks_since_access
    
    ; check if should promote to hot
    cmp byte [ebx + 1], PAGE_HOT_THRESHOLD
    jl .done
    
    ; promote to hot if not already
    cmp byte [ebx], PAGE_HOT
    je .done
    
    mov byte [ebx], PAGE_HOT
    inc dword [page_stats_hot]
    
    .done:
        pop edi
        pop ebx
        ret

; update page aging (call from timer)
update_page_aging:
    pusha
    
    mov ecx, PAGE_COUNT
    mov edi, page_table
    
    .age_loop:
        ; skip free pages
        cmp byte [edi], PAGE_FREE
        je .next_page
        
        ; increment ticks since access
        inc word [edi + 2]
        
        ; check if should demote to cold
        cmp word [edi + 2], PAGE_COLD_THRESHOLD
        jl .next_page
        
        ; demote hot page to cold
        cmp byte [edi], PAGE_HOT
        jne .check_allocated
        
        mov byte [edi], PAGE_COLD
        dec dword [page_stats_hot]
        inc dword [page_stats_cold]
        
        ; auto-compress if enabled
        cmp byte [compress_on_cold], 1
        jne .next_page
        
        push eax
        push edi
        ; calculate page index
        mov eax, edi
        sub eax, page_table
        shr eax, 4
        call vmm_compress_page
        pop edi
        pop eax
        jmp .next_page
        
        .check_allocated:
            ; demote allocated to cold
            cmp byte [edi], PAGE_ALLOCATED
            jne .next_page
            
            mov byte [edi], PAGE_COLD
            inc dword [page_stats_cold]
            
            ; auto-compress if enabled
            cmp byte [compress_on_cold], 1
            jne .next_page
            
            push eax
            push edi
            ; calculate page index
            mov eax, edi
            sub eax, page_table
            shr eax, 4
            call vmm_compress_page
            pop edi
            pop eax
        
        .next_page:
            add edi, 16
            loop .age_loop
    
    ; calculate memory pressure
    call calculate_memory_pressure
    
    popa
    ret

; calculate current memory pressure
calculate_memory_pressure:
    pusha
    
    ; count free pages
    xor ebx, ebx        ; free count
    mov ecx, PAGE_COUNT
    mov edi, page_table
    
    .count_loop:
        cmp byte [edi], PAGE_FREE
        jne .not_free
        inc ebx
        .not_free:
        add edi, 16
        loop .count_loop
    
    mov [free_page_count], ebx
    
    ; calculate pressure level
    ; high pressure: < 10% free (< 25 pages)
    ; medium pressure: < 25% free (< 64 pages)
    ; low pressure: >= 25% free
    
    cmp ebx, 25
    jl .high_pressure
    cmp ebx, 64
    jl .medium_pressure
    
    ; low pressure
    mov dword [memory_pressure], 0
    jmp .done
    
    .medium_pressure:
        mov dword [memory_pressure], 1
        ; compress some cold pages proactively
        call compress_cold_pages
        jmp .done
    
    .high_pressure:
        mov dword [memory_pressure], 2
        ; aggressively compress cold pages
        call compress_cold_pages
        ; swap out compressed pages if still high pressure
        call swap_out_pages
        ; swap out compressed pages if still high pressure
        call swap_out_pages
    
    .done:
        popa
        ret

; compress cold pages
compress_cold_pages:
    pusha
    
    mov ecx, PAGE_COUNT
    mov edi, page_table
    xor ebx, ebx        ; page index
    
    .scan_loop:
        ; check if page is cold
        cmp byte [edi], PAGE_COLD
        jne .next_page
        
        ; try to compress it
        push ecx
        push edi
        mov eax, ebx
        call vmm_compress_page
        pop edi
        pop ecx
        
        .next_page:
        add edi, 16
        inc ebx
        loop .scan_loop
    
    popa
    ret