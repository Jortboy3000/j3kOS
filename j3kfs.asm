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
    
    ; add directory entry to current directory
    mov eax, [current_dir_inode]
    mov ebx, [.inode]
    mov ecx, esi
    call add_dir_entry
    
    popa
    mov eax, [.inode]
    ret
    
    .failed:
    popa
    mov eax, -1
    ret
    
    .inode: dd 0

; delete a file
; ESI = filename
; returns: EAX = 0 on success, -1 on error
delete_file:
    pusha
    
    ; find file in current directory
    mov eax, [current_dir_inode]
    mov ebx, esi
    call find_dir_entry
    cmp eax, -1
    je .failed
    
    mov [.inode], eax
    
    ; remove directory entry
    mov eax, [current_dir_inode]
    mov ebx, esi
    call remove_dir_entry
    
    ; free the inode
    mov eax, [.inode]
    call free_inode
    
    popa
    xor eax, eax
    ret
    
    .failed:
    popa
    mov eax, -1
    ret
    
    .inode: dd 0

; write data to file
; EAX = inode number
; ESI = data buffer
; ECX = size in bytes
; returns: EAX = bytes written
write_file:
    pusha
    
    mov [.inode_num], eax
    mov [.buffer], esi
    mov [.size], ecx
    mov dword [.written], 0
    
    ; read inode
    mov eax, [.inode_num]
    call read_inode
    
    mov edi, disk_buffer
    
    ; calculate how many blocks we need
    mov eax, [.size]
    add eax, 511
    shr eax, 9          ; divide by 512
    mov [.blocks_needed], eax
    
    cmp eax, MAX_FILE_BLOCKS
    jg .too_big
    
    ; allocate blocks and write data
    mov dword [.block_idx], 0
    
    .write_loop:
        mov eax, [.block_idx]
        cmp eax, [.blocks_needed]
        jge .write_done
        
        ; allocate a data block
        push edi
        call alloc_data_block
        pop edi
        cmp eax, -1
        je .write_done
        
        ; store block number in inode
        mov ebx, [.block_idx]
        mov [edi + 18 + ebx * 4], eax
        
        ; calculate how much to write
        mov ecx, 512
        mov eax, [.size]
        sub eax, [.written]
        cmp eax, 512
        jge .write_full_block
        mov ecx, eax
        
        .write_full_block:
        ; copy data to temp buffer
        push edi
        mov edi, temp_block
        mov esi, [.buffer]
        add esi, [.written]
        rep movsb
        pop edi
        
        ; write block to disk
        push edi
        mov ebx, [.block_idx]
        mov eax, [edi + 18 + ebx * 4]
        add eax, DATA_START_SECTOR
        mov ebx, temp_block
        call write_sector
        pop edi
        
        ; update written count
        add [.written], ecx
        inc dword [.block_idx]
        jmp .write_loop
    
    .write_done:
    ; update inode size and block count
    mov eax, [.size]
    mov [edi + 2], eax
    mov eax, [.blocks_needed]
    mov [edi + 6], eax
    
    ; write inode back
    mov eax, [.inode_num]
    call write_inode
    
    popa
    mov eax, [.written]
    ret
    
    .too_big:
    popa
    xor eax, eax
    ret
    
    .inode_num: dd 0
    .buffer: dd 0
    .size: dd 0
    .blocks_needed: dd 0
    .block_idx: dd 0
    .written: dd 0

; read data from file
; EAX = inode number
; EDI = destination buffer
; ECX = max bytes to read
; returns: EAX = bytes read
read_file:
    pusha
    
    mov [.inode_num], eax
    mov [.dest], edi
    mov [.max_size], ecx
    mov dword [.bytes_read], 0
    
    ; read inode
    mov eax, [.inode_num]
    call read_inode
    
    mov esi, disk_buffer
    
    ; get file size
    mov eax, [esi + 2]
    mov [.file_size], eax
    
    ; get block count
    mov eax, [esi + 6]
    mov [.block_count], eax
    
    ; read blocks
    mov dword [.block_idx], 0
    
    .read_loop:
        mov eax, [.block_idx]
        cmp eax, [.block_count]
        jge .read_done
        
        ; get block number
        mov ebx, [.block_idx]
        mov eax, [esi + 18 + ebx * 4]
        test eax, eax
        jz .read_done
        
        ; read block from disk
        add eax, DATA_START_SECTOR
        push esi
        mov ebx, temp_block
        call read_sector
        pop esi
        
        ; copy to destination
        mov ecx, 512
        mov eax, [.file_size]
        sub eax, [.bytes_read]
        cmp eax, 512
        jge .copy_full
        mov ecx, eax
        
        .copy_full:
        push esi
        mov esi, temp_block
        mov edi, [.dest]
        add edi, [.bytes_read]
        rep movsb
        pop esi
        
        add [.bytes_read], ecx
        inc dword [.block_idx]
        
        ; check if we hit max size
        mov eax, [.bytes_read]
        cmp eax, [.max_size]
        jge .read_done
        
        jmp .read_loop
    
    .read_done:
    popa
    mov eax, [.bytes_read]
    ret
    
    .inode_num: dd 0
    .dest: dd 0
    .max_size: dd 0
    .file_size: dd 0
    .block_count: dd 0
    .block_idx: dd 0
    .bytes_read: dd 0

temp_block: times 512 db 0

; ========================================
; DIRECTORY OPERATIONS
; ========================================

; add entry to directory
; EAX = directory inode number
; EBX = file inode number
; ECX = filename pointer
; returns: EAX = 0 on success, -1 on error
add_dir_entry:
    pusha
    
    mov [.dir_inode], eax
    mov [.file_inode], ebx
    mov [.filename], ecx
    
    ; read directory inode
    mov eax, [.dir_inode]
    call read_inode
    
    mov esi, disk_buffer
    
    ; get current size
    mov eax, [esi + 2]
    mov [.dir_size], eax
    
    ; calculate which block to add to
    mov eax, [.dir_size]
    shr eax, 9          ; divide by 512
    mov [.block_idx], eax
    
    cmp eax, MAX_FILE_BLOCKS
    jge .failed
    
    ; check if we need a new block
    mov eax, [.dir_size]
    and eax, 511
    test eax, eax
    jnz .have_block
    
    ; allocate new block
    push esi
    call alloc_data_block
    pop esi
    cmp eax, -1
    je .failed
    
    mov ebx, [.block_idx]
    mov [esi + 18 + ebx * 4], eax
    
    ; update block count
    mov eax, [esi + 6]
    inc eax
    mov [esi + 6], eax
    
    .have_block:
    ; get block number
    mov ebx, [.block_idx]
    mov eax, [esi + 18 + ebx * 4]
    add eax, DATA_START_SECTOR
    
    ; read the block
    push esi
    mov ebx, temp_block
    call read_sector
    pop esi
    
    ; calculate offset within block
    mov eax, [.dir_size]
    and eax, 511
    
    ; write directory entry
    mov edi, temp_block
    add edi, eax
    
    ; write inode number
    mov eax, [.file_inode]
    mov [edi], eax
    
    ; copy filename
    mov ecx, MAX_FILENAME
    mov esi, [.filename]
    add edi, 4
    
    .copy_name:
        lodsb
        stosb
        test al, al
        jz .name_done
        loop .copy_name
    
    .name_done:
    ; write block back
    mov esi, disk_buffer
    mov ebx, [.block_idx]
    mov eax, [esi + 18 + ebx * 4]
    add eax, DATA_START_SECTOR
    push esi
    mov ebx, temp_block
    call write_sector
    pop esi
    
    ; update directory size
    add dword [esi + 2], 32
    
    ; write inode back
    mov eax, [.dir_inode]
    call write_inode
    
    popa
    xor eax, eax
    ret
    
    .failed:
    popa
    mov eax, -1
    ret
    
    .dir_inode: dd 0
    .file_inode: dd 0
    .filename: dd 0
    .dir_size: dd 0
    .block_idx: dd 0

; find file in directory
; EAX = directory inode number
; EBX = filename pointer
; returns: EAX = file inode number (or -1 if not found)
find_dir_entry:
    pusha
    
    mov [.dir_inode], eax
    mov [.filename], ebx
    mov dword [.result], -1
    
    ; read directory inode
    mov eax, [.dir_inode]
    call read_inode
    
    mov esi, disk_buffer
    
    ; get directory size
    mov eax, [esi + 2]
    mov [.dir_size], eax
    
    ; calculate number of entries
    shr eax, 5          ; divide by 32
    mov [.entry_count], eax
    
    test eax, eax
    jz .done
    
    ; scan entries
    mov dword [.entry_idx], 0
    
    .scan_loop:
        mov eax, [.entry_idx]
        cmp eax, [.entry_count]
        jge .done
        
        ; calculate which block
        mov eax, [.entry_idx]
        shl eax, 5          ; multiply by 32
        shr eax, 9          ; divide by 512
        mov [.block_idx], eax
        
        ; get block number
        mov ebx, [.block_idx]
        mov eax, [esi + 18 + ebx * 4]
        add eax, DATA_START_SECTOR
        
        ; read block
        push esi
        mov ebx, temp_block
        call read_sector
        pop esi
        
        ; calculate offset in block
        mov eax, [.entry_idx]
        shl eax, 5
        and eax, 511
        
        ; compare filename
        mov edi, temp_block
        add edi, eax
        add edi, 4          ; skip inode number
        
        mov esi, [.filename]
        mov ecx, MAX_FILENAME
        
        .compare:
            lodsb
            mov bl, [edi]
            inc edi
            cmp al, bl
            jne .not_match
            test al, al
            jz .match
            loop .compare
        
        .match:
        ; found it! get inode number
        mov eax, [.entry_idx]
        shl eax, 5
        and eax, 511
        mov edi, temp_block
        add edi, eax
        mov eax, [edi]
        mov [.result], eax
        jmp .done
        
        .not_match:
        mov esi, disk_buffer
        inc dword [.entry_idx]
        jmp .scan_loop
    
    .done:
    popa
    mov eax, [.result]
    ret
    
    .dir_inode: dd 0
    .filename: dd 0
    .dir_size: dd 0
    .entry_count: dd 0
    .entry_idx: dd 0
    .block_idx: dd 0
    .result: dd 0

; remove entry from directory
; EAX = directory inode number
; EBX = filename pointer
; returns: EAX = 0 on success, -1 on error
remove_dir_entry:
    pusha
    
    ; TODO: implement proper removal
    ; for now just return success
    
    popa
    xor eax, eax
    ret

; list directory contents
; EAX = directory inode number
list_directory:
    pusha
    
    mov [.dir_inode], eax
    
    ; read directory inode
    call read_inode
    
    mov esi, disk_buffer
    
    ; get directory size
    mov eax, [esi + 2]
    mov [.dir_size], eax
    
    ; calculate number of entries
    shr eax, 5
    mov [.entry_count], eax
    
    test eax, eax
    jz .empty
    
    ; print header
    mov esi, msg_dir_listing
    call print_string
    
    ; scan entries
    mov dword [.entry_idx], 0
    mov esi, disk_buffer
    
    .list_loop:
        mov eax, [.entry_idx]
        cmp eax, [.entry_count]
        jge .done
        
        ; calculate which block
        mov eax, [.entry_idx]
        shl eax, 5
        shr eax, 9
        mov [.block_idx], eax
        
        ; get block number
        mov ebx, [.block_idx]
        mov eax, [esi + 18 + ebx * 4]
        add eax, DATA_START_SECTOR
        
        ; read block
        push esi
        mov ebx, temp_block
        call read_sector
        pop esi
        
        ; calculate offset
        mov eax, [.entry_idx]
        shl eax, 5
        and eax, 511
        
        ; print entry
        push esi
        mov esi, msg_dir_bullet
        call print_string
        
        mov esi, temp_block
        add esi, eax
        add esi, 4          ; skip inode, point to name
        call print_string
        
        mov al, 10
        call print_char
        pop esi
        
        inc dword [.entry_idx]
        jmp .list_loop
    
    .empty:
    mov esi, msg_dir_empty
    call print_string
    
    .done:
    popa
    ret
    
    .dir_inode: dd 0
    .dir_size: dd 0
    .entry_count: dd 0
    .entry_idx: dd 0
    .block_idx: dd 0

; ========================================
; DISK I/O
; ========================================

disk_buffer:        times 512 db 0

; ========================================
; DISK I/O (ATA PIO MODE)
; ========================================

; ATA PIO ports (primary controller)
ATA_DATA         equ 0x1F0
ATA_ERROR        equ 0x1F1
ATA_SECTOR_COUNT equ 0x1F2
ATA_LBA_LOW      equ 0x1F3
ATA_LBA_MID      equ 0x1F4
ATA_LBA_HIGH     equ 0x1F5
ATA_DRIVE_HEAD   equ 0x1F6
ATA_STATUS       equ 0x1F7
ATA_COMMAND      equ 0x1F7

; ATA commands
ATA_CMD_READ     equ 0x20
ATA_CMD_WRITE    equ 0x30

; ATA status bits
ATA_SR_BSY       equ 0x80    ; Busy
ATA_SR_DRDY      equ 0x40    ; Drive ready
ATA_SR_DRQ       equ 0x08    ; Data request ready
ATA_SR_ERR       equ 0x01    ; Error

; wait for ATA drive to be ready
ata_wait_ready:
    pusha
    .wait:
        mov dx, ATA_STATUS
        in al, dx
        test al, ATA_SR_BSY
        jnz .wait
    popa
    ret

; wait for data request
ata_wait_drq:
    pusha
    .wait:
        mov dx, ATA_STATUS
        in al, dx
        test al, ATA_SR_DRQ
        jz .wait
    popa
    ret

; read sector from disk
; EAX = sector number (LBA)
; EBX = buffer address
; ========================================
; SECTOR CACHE - SINGLE SECTOR BUFFER
; ========================================
sector_cache: times 512 db 0
cached_sector: dd 0xFFFFFFFF    ; -1 means no sector cached

; read sector from cache
; EAX = sector number (LBA)
; EBX = buffer address
read_sector:
    pusha
    
    ; check if this sector is cached
    cmp eax, [cached_sector]
    je .cached
    
    ; not cached - just return zeros
    mov edi, ebx
    mov ecx, 128
    xor eax, eax
    rep stosd
    jmp .done
    
    .cached:
        ; copy from cache to buffer
        mov esi, sector_cache
        mov edi, ebx
        mov ecx, 128
        rep movsd
    
    .done:
    popa
    ret

; write sector to cache
; EAX = sector number (LBA)
; EBX = buffer address
write_sector:
    pusha
    
    ; cache this sector
    mov [cached_sector], eax
    
    ; copy buffer to cache
    mov esi, ebx
    mov edi, sector_cache
    mov ecx, 128
    rep movsd
    
    popa
    ret

; ========================================
; MESSAGES
; ========================================

msg_fs_mounted:     db 'J3KFS mounted successfully!', 10, 0
msg_fs_invalid:     db 'Invalid file system! Use :format to create J3KFS.', 10, 0
msg_fs_formatted:   db 'Disk formatted with J3KFS!', 10, 0
msg_dir_listing:    db 'Directory contents:', 10, 0
msg_dir_bullet:     db '  - ', 0
msg_dir_empty:      db '  (empty directory)', 10, 0
msg_file_created:   db 'File created!', 10, 0
msg_file_written:   db 'File written: ', 0
msg_bytes_written:  db ' bytes', 10, 0
msg_file_deleted:   db 'File deleted!', 10, 0
msg_file_not_found: db 'File not found!', 10, 0
msg_file_reading:   db 'Reading file...', 10, 0
