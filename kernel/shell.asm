; ========================================
; SHELL - COMMAND LINE INTERFACE
; ========================================

shell_main:
    mov esi, msg_prompt
    call print_string
    
    mov edi, cmd_buffer
    
    .input_loop:
        call getchar_wait
        
        ; handle enter
        cmp al, 13
        je .process_cmd
        
        ; handle backspace
        cmp al, 8
        je .handle_backspace
        
        ; buffer full?
        mov ecx, edi
        sub ecx, cmd_buffer
        cmp ecx, 63
        jge .input_loop
        
        ; echo and store
        call print_char
        stosb
        jmp .input_loop
        
    .handle_backspace:
        cmp edi, cmd_buffer
        je .input_loop
        
        dec edi
        mov al, 8
        call print_char
        mov al, ' '
        call print_char
        mov al, 8
        call print_char
        jmp .input_loop
        
    .process_cmd:
        mov al, 0
        stosb               ; null terminate
        mov al, 10
        call print_char
        
        ; empty command?
        cmp edi, cmd_buffer
        je shell_main
        
        call process_command
        jmp shell_main

process_command:
    pusha
    
    ; check commands
    mov esi, cmd_buffer
    mov edi, cmd_help
    call strcmp
    je .do_help
    
    mov esi, cmd_buffer
    mov edi, cmd_clear
    call strcmp
    je .do_clear
    
    mov esi, cmd_buffer
    mov edi, cmd_time
    call strcmp
    je .do_time
    
    mov esi, cmd_buffer
    mov edi, cmd_mem
    call strcmp
    je .do_mem
    
    mov esi, cmd_buffer
    mov edi, cmd_net
    call strcmp
    je .do_net
    
    mov esi, cmd_buffer
    mov edi, cmd_pci
    call strcmp
    je .do_pci
    
    mov esi, cmd_buffer
    mov edi, cmd_gui
    call strcmp
    je .do_gui
    
    mov esi, cmd_buffer
    mov edi, cmd_exit
    call strcmp
    je .do_exit
    
    ; unknown command
    mov esi, msg_unknown
    call print_string
    jmp .done
    
    .do_help:
        mov esi, msg_help
        call print_string
        jmp .done
        
    .do_clear:
        call clear_screen
        jmp .done
        
    .do_time:
        call rtc_print_time
        jmp .done
        
    .do_mem:
        mov esi, msg_mem_total
        call print_string
        mov eax, 1024 * 1024 * 128  ; fake 128MB
        call print_hex
        mov al, 10
        call print_char
        jmp .done
        
    .do_net:
        call init_rtl8139
        jmp .done
        
    .do_pci:
        call scan_pci
        jmp .done
        
    .do_gui:
        call gui_demo
        call clear_screen
        jmp .done
        
    .do_exit:
        mov esi, msg_shutdown
        call print_string
        cli
        hlt
        
    .done:
        popa
        ret


cmd_buffer: times 64 db 0
msg_prompt: db 'j3kOS> ', 0
cmd_help: db 'help', 0
cmd_clear: db 'clear', 0
cmd_time: db 'time', 0
cmd_mem: db 'mem', 0
cmd_net: db 'net', 0
cmd_pci: db 'pci', 0
cmd_gui: db 'gui', 0
cmd_exit: db 'exit', 0
msg_unknown: db 'Unknown command. Type "help" for list.', 10, 0
msg_help: db 'Available commands:', 10
          db '  help  - Show this help', 10
          db '  clear - Clear screen', 10
          db '  time  - Show current time', 10
          db '  mem   - Show memory info', 10
          db '  net   - Initialize network', 10
          db '  pci   - Scan PCI bus', 10
          db '  gui   - Start GUI demo', 10
          db '  exit  - Shutdown', 10, 0
msg_mem_total: db 'Total Memory: ', 0
msg_shutdown: db 'Shutting down...', 10, 0
