; ========================================
; TASK SWITCHING - MULTITASKING N SHIT
; ========================================

; TSS structure (104 bytes)
align 16
tss:
    dd 0            ; previous task link
    dd 0x90000      ; ESP0 (kernel stack)
    dd 0x10         ; SS0 (kernel data segment)
    times 23 dd 0   ; rest of TSS fields
    dw 0            ; reserved
    dw 104          ; IO map base (no IO map)

; task control block
MAX_TASKS equ 8
TASK_RUNNING equ 1
TASK_READY equ 2
TASK_BLOCKED equ 3

task_count: dd 0
current_task: dd 0

align 16
task_table: times (MAX_TASKS * 64) db 0  ; 8 tasks, 64 bytes each
; each task: ESP, EBP, EBX, ESI, EDI, EIP, state, etc

; initialize TSS
init_tss:
    pusha
    
    ; update GDT with TSS address (segment 0x28 = 5th descriptor)
    mov eax, tss
    mov edi, 0x1000 + (5 * 8)  ; GDT is at loader location
    mov [edi + 2], ax          ; base low
    shr eax, 16
    mov [edi + 4], al          ; base mid
    mov [edi + 7], ah          ; base high
    
    ; load TSS
    mov ax, 0x28               ; TSS selector
    ltr ax
    
    popa
    ret

; create a new task
; ESI = task entry point
; returns EAX = task ID (or -1 if failed)
create_task:
    push ebx
    push ecx
    push edi
    
    ; check if we have space
    mov eax, [task_count]
    cmp eax, MAX_TASKS
    jge .no_space
    
    ; get task slot
    mov ebx, eax
    imul ebx, 64
    add ebx, task_table
    
    ; allocate stack (4KB per task)
    mov ecx, 4096
    call malloc
    test eax, eax
    jz .no_space
    
    ; set up task structure
    add eax, 4096              ; stack grows down
    mov [ebx], eax             ; ESP
    mov [ebx + 4], eax         ; EBP
    mov [ebx + 20], esi        ; EIP (entry point)
    mov dword [ebx + 24], TASK_READY  ; state
    
    ; increment task count
    inc dword [task_count]
    
    ; return task ID
    mov eax, [task_count]
    dec eax
    jmp .done
    
    .no_space:
        mov eax, -1
    
    .done:
        pop edi
        pop ecx
        pop ebx
        ret

; switch to next task (called by timer)
switch_task:
    pusha
    
    ; check if we have multiple tasks
    cmp dword [task_count], 2
    jl .done
    
    ; save current task state
    mov eax, [current_task]
    imul eax, 64
    add eax, task_table
    
    mov [eax], esp             ; save ESP
    mov [eax + 4], ebp         ; save EBP
    mov [eax + 8], ebx
    mov [eax + 12], esi
    mov [eax + 16], edi
    
    ; find next ready task
    mov ebx, [current_task]
    .find_next:
        inc ebx
        cmp ebx, [task_count]
        jl .check_task
        xor ebx, ebx           ; wrap around
        
    .check_task:
        mov eax, ebx
        imul eax, 64
        add eax, task_table
        cmp dword [eax + 24], TASK_READY
        je .switch_to_task
        
        cmp ebx, [current_task]
        jne .find_next
        jmp .done              ; no other ready tasks
    
    .switch_to_task:
        mov [current_task], ebx
        
        ; restore task state
        mov esp, [eax]
        mov ebp, [eax + 4]
        mov ebx, [eax + 8]
        mov esi, [eax + 12]
        mov edi, [eax + 16]
    
    .done:
        popa
        ret
