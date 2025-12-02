; ========================================
; SYSTEM CALLS - INT 0x80 INTERFACE
; ========================================

; syscall numbers
SYSCALL_EXIT    equ 0
SYSCALL_PRINT   equ 1
SYSCALL_READ    equ 2
SYSCALL_MALLOC  equ 3
SYSCALL_FREE    equ 4

syscall_handler:
    ; save all registers
    pusha
    push ds
    push es
    
    ; set up kernel segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    
    ; EAX = syscall number
    ; EBX, ECX, EDX = arguments
    
    cmp eax, SYSCALL_EXIT
    je .syscall_exit
    cmp eax, SYSCALL_PRINT
    je .syscall_print
    cmp eax, SYSCALL_READ
    je .syscall_read
    cmp eax, SYSCALL_MALLOC
    je .syscall_malloc
    cmp eax, SYSCALL_FREE
    je .syscall_free
    
    ; unknown syscall
    mov eax, -1
    jmp .done
    
    .syscall_exit:
        ; just halt for now
        cli
        hlt
    
    .syscall_print:
        ; EBX = string pointer
        mov esi, ebx
        call print_string
        xor eax, eax
        jmp .done
    
    .syscall_read:
        ; EBX = buffer, ECX = max length
        call getchar_wait
        mov byte [ebx], al
        mov eax, 1      ; return 1 byte read
        jmp .done
    
    .syscall_malloc:
        ; ECX = size
        call malloc
        ; EAX already contains the result
        jmp .done
    
    .syscall_free:
        ; EBX = pointer
        mov eax, ebx
        call free
        xor eax, eax
        jmp .done
    
    .done:
        ; restore registers
        mov [.syscall_return], eax
        pop es
        pop ds
        popa
        mov eax, [.syscall_return]
        iret
    
    .syscall_return: dd 0
