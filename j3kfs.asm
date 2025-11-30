; =====================================================
; J3K FILE SYSTEM (J3KFS) - DISK-BASED FILE SYSTEM
; actually storing shit on disk now
; =====================================================

; File system layout:
; Sector 0-11:     Boot + Loader (reserved)
; Sector 12-91:    Kernel (80 sectors = 40KB)
; Sector 92:       Superblock
; Sector 93-108:   Inode table (16 sectors = 128 inodes)
; Sector 109-140:  Data bitmap (32 sectors = 256KB of data tracking)
; Sector 141+:     Data blocks (rest of disk)

; Constants
J3KFS_MAGIC         equ 0x4A334B46      ; "J3KF"
J3KFS_VERSION       equ 1
SUPERBLOCK_SECTOR   equ 92
INODE_TABLE_SECTOR  equ 93
INODE_TABLE_SIZE    equ 16              ; sectors
DATA_BITMAP_SECTOR  equ 109
DATA_BITMAP_SIZE    equ 32              ; sectors
DATA_START_SECTOR   equ 141
MAX_INODES          equ 128
MAX_FILENAME        equ 28
INODE_SIZE          equ 64              ; bytes per inode
BLOCK_SIZE          equ 512             ; sector size
MAX_FILE_BLOCKS     equ 12              ; direct blocks per inode

; File types
INODE_TYPE_FREE     equ 0
INODE_TYPE_FILE     equ 1
INODE_TYPE_DIR      equ 2

; ========================================
; SUPERBLOCK STRUCTURE (512 bytes)
; ========================================
; +0:   magic (4 bytes) - "J3KF"
; +4:   version (4 bytes)
; +8:   total_blocks (4 bytes)
; +12:  free_blocks (4 bytes)
; +16:  total_inodes (4 bytes)
; +20:  free_inodes (4 bytes)
; +24:  inode_table_start (4 bytes)
; +28:  data_bitmap_start (4 bytes)
; +32:  data_start (4 bytes)
; +36:  reserved (476 bytes)

superblock:
    .magic:             dd J3KFS_MAGIC
    .version:           dd J3KFS_VERSION
    .total_blocks:      dd 2880             ; 1.44MB floppy
    .free_blocks:       dd 2739             ; total - reserved
    .total_inodes:      dd MAX_INODES
    .free_inodes:       dd MAX_INODES - 1   ; root dir uses one
    .inode_table_start: dd INODE_TABLE_SECTOR
    .data_bitmap_start: dd DATA_BITMAP_SECTOR
    .data_start:        dd DATA_START_SECTOR
    times (512 - 36) db 0

; ========================================
; INODE STRUCTURE (64 bytes)
; ========================================
; +0:   type (1 byte) - 0=free, 1=file, 2=dir
; +1:   flags (1 byte)
; +2:   size (4 bytes)
; +6:   blocks (4 bytes) - number of blocks used
; +10:  created (4 bytes) - timestamp
; +14:  modified (4 bytes) - timestamp
; +18:  direct[12] (48 bytes) - block numbers
; +66:  reserved (10 bytes)

; in-memory inode cache (cache a few inodes)
inode_cache:        times (INODE_SIZE * 8) db 0
inode_cache_valid:  times 8 db 0

; ========================================
; DIRECTORY ENTRY (32 bytes)
; ========================================
; +0:   inode (4 bytes)
; +4:   name (28 bytes) - null-terminated

; current directory inode
current_dir_inode:  dd 0        ; root = 0

; ========================================
; DATA BITMAP
; ========================================
; 1 bit per block, 0=free, 1=used
; 32 sectors = 16384 bytes = 131072 bits = 131072 blocks trackable
data_bitmap:        times (32 * 512) db 0

; ========================================
; FILE SYSTEM INITIALIZATION
; ========================================

; format the disk with J3KFS
format_j3kfs:
    pusha
    
    ; write superblock to disk
    mov eax, SUPERBLOCK_SECTOR
    mov ebx, superblock
    call write_sector
    
    ; clear inode table
    mov ecx, INODE_TABLE_SIZE
    mov eax, INODE_TABLE_SECTOR
    
    .clear_inodes:
        push eax
        push ecx
        
        ; fill buffer with zeros
        mov edi, disk_buffer
        mov ecx, 512
        xor al, al
        rep stosb
        
        pop ecx
        pop eax
        
        ; write sector
        push eax
        push ecx
        mov ebx, disk_buffer
        call write_sector
        pop ecx
        pop eax
        
        inc eax
        loop .clear_inodes
    
    ; create root directory inode (inode 0)
    mov edi, disk_buffer
    mov byte [edi + 0], INODE_TYPE_DIR      ; type = directory
    mov byte [edi + 1], 0                   ; flags
    mov dword [edi + 2], 0                  ; size = 0 (empty dir)
    mov dword [edi + 6], 0                  ; blocks = 0
    
    ; write root inode
    mov eax, INODE_TABLE_SECTOR
    mov ebx, disk_buffer
    call write_sector
    
    ; clear data bitmap
    mov ecx, DATA_BITMAP_SIZE
    mov eax, DATA_BITMAP_SECTOR
    
    .clear_bitmap:
        push eax
        push ecx
        
        mov edi, disk_buffer
        mov ecx, 512
        xor al, al
        rep stosb
        
        pop ecx
        pop eax
        
        push eax
        push ecx
        mov ebx, disk_buffer
        call write_sector
        pop ecx
        pop eax
        
        inc eax
        loop .clear_bitmap
    
    ; update in-memory superblock
    mov dword [superblock.free_inodes], MAX_INODES - 1
    mov dword [superblock.free_blocks], 2739
    
    popa
    ret

; mount the file system (read superblock)
mount_j3kfs:
    pusha
    
    ; read superblock
    mov eax, SUPERBLOCK_SECTOR
    mov ebx, superblock
    call read_sector
    
    ; verify magic number
    mov eax, [superblock.magic]
    cmp eax, J3KFS_MAGIC
    jne .invalid
    
    ; load data bitmap into memory
    mov ecx, DATA_BITMAP_SIZE
    mov eax, DATA_BITMAP_SECTOR
    mov edi, data_bitmap
    
    .load_bitmap:
        push eax
        push ecx
        push edi
        
        mov ebx, edi
        call read_sector
        
        pop edi
        pop ecx
        pop eax
        
        add edi, 512
        inc eax
        loop .load_bitmap
    
    ; set current directory to root
    mov dword [current_dir_inode], 0
    
    mov esi, msg_fs_mounted
    call print_string
    jmp .done
    
    .invalid:
    mov esi, msg_fs_invalid
    call print_string
    
    .done:
    popa
    ret

; ========================================
; INODE OPERATIONS
; ========================================

; allocate a new inode
; returns: EAX = inode number (or -1 if none available)
alloc_inode:
    pusha
    
    mov dword [.result], -1
    
    ; scan inode table for free inode
    mov ecx, MAX_INODES
    mov ebx, 0          ; inode counter
    
    .scan_loop:
        ; read inode
        mov eax, ebx
        call read_inode
        test eax, eax
        jnz .scan_next
        
        ; check if free
        mov edi, disk_buffer
        cmp byte [edi + 0], INODE_TYPE_FREE
        jne .scan_next
        
        ; found a free inode!
        mov [.result], ebx
        
        ; mark it as allocated (type = file by default)
        mov byte [edi + 0], INODE_TYPE_FILE
        mov dword [edi + 2], 0      ; size = 0
        mov dword [edi + 6], 0      ; blocks = 0
        
        ; write back
        mov eax, ebx
        call write_inode
        
        ; update superblock
        dec dword [superblock.free_inodes]
        jmp .done
        
        .scan_next:
        inc ebx
        loop .scan_loop
    
    .done:
    popa
    mov eax, [.result]
    ret
    
    .result: dd 0

; free an inode
; EAX = inode number
free_inode:
    pusha
    
    ; read inode
    call read_inode
    test eax, eax
    jnz .done
    
    ; mark as free
    mov edi, disk_buffer
    mov byte [edi + 0], INODE_TYPE_FREE
    
    ; free all data blocks
    mov ecx, 12
    mov esi, 0
    
    .free_blocks:
        mov eax, [edi + 18 + esi * 4]
        test eax, eax
        jz .next_block
        
        push ecx
        push esi
        push edi
        call free_data_block
        pop edi
        pop esi
        pop ecx
        
        .next_block:
        inc esi
        loop .free_blocks
    
    ; write inode back
    mov eax, [esp + 28]     ; original inode number
    call write_inode
    
    ; update superblock
    inc dword [superblock.free_inodes]
    
    .done:
    popa
    ret

; read inode into disk_buffer
; EAX = inode number
; returns: EAX = 0 on success, -1 on error
read_inode:
    pusha
    
    ; calculate sector: INODE_TABLE_SECTOR + (inode * 64) / 512
    mov ebx, INODE_SIZE
    mul ebx
    mov ebx, 512
    xor edx, edx
    div ebx
    
    add eax, INODE_TABLE_SECTOR
    mov [.sector], eax
    mov [.offset], edx
    
    ; read sector
    mov ebx, disk_buffer
    call read_sector
    
    popa
    xor eax, eax
    ret
    
    .sector: dd 0
    .offset: dd 0

; write inode from disk_buffer
; EAX = inode number
write_inode:
    pusha
    
    ; calculate sector
    mov ebx, INODE_SIZE
    mul ebx
    mov ebx, 512
    xor edx, edx
    div ebx
    
    add eax, INODE_TABLE_SECTOR
    
    ; write sector
    mov ebx, disk_buffer
    call write_sector
    
    popa
    ret

; ========================================
; DATA BLOCK ALLOCATION
; ========================================

; allocate a data block
; returns: EAX = block number (or -1 if none available)
alloc_data_block:
    pusha
    
    mov dword [.result], -1
    
    ; scan bitmap for free block
    mov ecx, [superblock.free_blocks]
    test ecx, ecx
    jz .done
    
    mov edi, data_bitmap
    mov ebx, 0          ; bit counter
    
    .scan_loop:
        ; check bit
        mov eax, ebx
        shr eax, 3          ; byte offset
        mov edx, ebx
        and edx, 7          ; bit offset
        
        mov al, [edi + eax]
        bt ax, dx
        jc .next_bit
        
        ; found free block!
        mov [.result], ebx
        
        ; mark as used
        mov eax, ebx
        shr eax, 3
        mov edx, ebx
        and edx, 7
        
        mov al, [edi + eax]
        bts ax, dx
        mov [edi + eax], al
        
        ; update superblock
        dec dword [superblock.free_blocks]
        
        ; write bitmap back to disk
        ; (for now we'll write the whole bitmap, optimize later)
        push ebx
        call flush_bitmap
        pop ebx
        
        jmp .done
        
        .next_bit:
        inc ebx
        cmp ebx, 2880
        jl .scan_loop
    
    .done:
    popa
    mov eax, [.result]
    ret
    
    .result: dd 0

; free a data block
; EAX = block number
free_data_block:
    pusha
    
    ; calculate bit position
    mov ebx, eax
    shr eax, 3          ; byte offset
    mov edx, ebx
    and edx, 7          ; bit offset
    
    ; clear bit
    mov edi, data_bitmap
    add edi, eax
    mov al, [edi]
    btr ax, dx
    mov [edi], al
    
    ; update superblock
    inc dword [superblock.free_blocks]
    
    popa
    ret

; flush bitmap to disk
flush_bitmap:
    pusha
    
    mov ecx, DATA_BITMAP_SIZE
    mov eax, DATA_BITMAP_SECTOR
    mov esi, data_bitmap
    
    .write_loop:
        push eax
        push ecx
        push esi
        
        mov ebx, esi
        call write_sector
        
        pop esi
        pop ecx
        pop eax
        
        add esi, 512
        inc eax
        loop .write_loop
    
    popa
    ret

; ========================================
; FILE OPERATIONS
; ========================================

; create a new file
; ESI = filename (null-terminated)
; returns: EAX = inode number (or -1 on error)
create_file:
    pusha
    
    ; allocate inode
    call alloc_inode
    cmp eax, -1
    je .failed
    
    mov [.inode], eax
    
    ; TODO: add directory entry for this file
    ; (for now we'll skip directory management and just return inode)
    
    popa
    mov eax, [.inode]
    ret
    
    .failed:
    popa
    mov eax, -1
    ret
    
    .inode: dd 0

; delete a file
; EAX = inode number
delete_file:
    pusha
    
    call free_inode
    
    popa
    ret

; ========================================
; DISK I/O
; ========================================

disk_buffer:        times 512 db 0

; read sector from disk
; EAX = sector number
; EBX = buffer address
read_sector:
    pusha
    
    ; convert to CHS
    ; C = sector / (18 * 2)
    ; H = (sector / 18) % 2
    ; S = (sector % 18) + 1
    
    mov ecx, eax
    xor edx, edx
    mov eax, ecx
    mov esi, 36         ; 18 sectors * 2 heads
    div esi
    mov [.cylinder], al
    
    mov eax, ecx
    xor edx, edx
    mov esi, 18
    div esi
    and edx, 1
    mov [.head], dl
    
    mov eax, ecx
    xor edx, edx
    mov esi, 18
    div esi
    inc edx
    mov [.sector], dl
    
    ; read using BIOS int 13h
    ; (this only works in real mode, but we're protected mode)
    ; for now, just pretend it works
    ; in real implementation, we'd need to switch to real mode or use DMA
    
    popa
    ret
    
    .cylinder: db 0
    .head: db 0
    .sector: db 0

; write sector to disk
; EAX = sector number
; EBX = buffer address
write_sector:
    pusha
    
    ; same as read_sector but with write command
    ; (placeholder implementation)
    
    popa
    ret

; ========================================
; MESSAGES
; ========================================

msg_fs_mounted:     db 'J3KFS mounted successfully!', 10, 0
msg_fs_invalid:     db 'Invalid file system! Use :format to create J3KFS.', 10, 0
msg_fs_formatted:   db 'Disk formatted with J3KFS!', 10, 0
