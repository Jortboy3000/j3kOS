; =====================================================
; TCP IMPLEMENTATION - TRANSMISSION CONTROL PROTOCOL
; reliable, ordered, connection-oriented networking
; =====================================================

; TCP header offsets
TCP_SRC_PORT    equ 0
TCP_DEST_PORT   equ 2
TCP_SEQ_NUM     equ 4
TCP_ACK_NUM     equ 8
TCP_DATA_OFF    equ 12      ; 4 bits offset, 4 bits reserved
TCP_FLAGS       equ 13
TCP_WINDOW      equ 14
TCP_CHECKSUM    equ 16
TCP_URGENT_PTR  equ 18
TCP_HEADER_SIZE equ 20

; TCP flags
TCP_FIN         equ 0x01
TCP_SYN         equ 0x02
TCP_RST         equ 0x04
TCP_PSH         equ 0x08
TCP_ACK         equ 0x10
TCP_URG         equ 0x20

; TCP states
TCP_STATE_CLOSED        equ 0
TCP_STATE_LISTEN        equ 1
TCP_STATE_SYN_SENT      equ 2
TCP_STATE_SYN_RECEIVED  equ 3
TCP_STATE_ESTABLISHED   equ 4
TCP_STATE_FIN_WAIT_1    equ 5
TCP_STATE_FIN_WAIT_2    equ 6
TCP_STATE_CLOSE_WAIT    equ 7
TCP_STATE_CLOSING       equ 8
TCP_STATE_LAST_ACK      equ 9
TCP_STATE_TIME_WAIT     equ 10

; Socket structure (64 bytes per socket)
SOCKET_SIZE     equ 64
MAX_SOCKETS     equ 8

struc SOCKET
    .state:         resb 1      ; TCP state
    .local_port:    resw 1      ; local port
    .remote_port:   resw 1      ; remote port
    .remote_ip:     resd 1      ; remote IP address
    .seq_num:       resd 1      ; sequence number
    .ack_num:       resd 1      ; acknowledgment number
    .window_size:   resw 1      ; receive window
    .rx_buffer:     resd 1      ; pointer to receive buffer
    .rx_length:     resw 1      ; bytes in rx buffer
    .tx_buffer:     resd 1      ; pointer to transmit buffer
    .tx_length:     resw 1      ; bytes in tx buffer
    .padding:       resb 36     ; pad to 64 bytes
endstruc

; Socket table
socket_table:   times (MAX_SOCKETS * SOCKET_SIZE) db 0
next_port:      dw 49152        ; ephemeral port range start

; ========================================
; SOCKET MANAGEMENT
; ========================================

; Create a new socket
; Returns: EAX = socket ID (0-7) or -1 on error
tcp_socket:
    push ebx
    push ecx
    xor ebx, ebx                ; socket index
.find_free:
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; check if socket is free
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    cmp byte [eax + SOCKET.state], TCP_STATE_CLOSED
    je .found
    
    inc ebx
    jmp .find_free
    
.found:
    ; initialize socket
    mov ecx, SOCKET_SIZE
    xor al, al
    push edi
    mov edi, eax
    rep stosb
    pop edi
    
    mov eax, ebx                ; return socket ID
    pop ecx
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop ecx
    pop ebx
    ret

; Bind socket to port
; EBX = socket ID, CX = port
; Returns: EAX = 0 on success, -1 on error
tcp_bind:
    push ebx
    push edi
    
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    mov edi, eax
    
    ; check if socket is closed
    cmp byte [edi + SOCKET.state], TCP_STATE_CLOSED
    jne .error
    
    ; bind port
    mov word [edi + SOCKET.local_port], cx
    
    xor eax, eax                ; success
    pop edi
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop edi
    pop ebx
    ret

; Listen on socket
; EBX = socket ID, CX = backlog (ignored for now)
; Returns: EAX = 0 on success, -1 on error
tcp_listen:
    push ebx
    push edi
    
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    mov edi, eax
    
    ; check if socket is bound
    cmp word [edi + SOCKET.local_port], 0
    je .error
    
    ; set state to LISTEN
    mov byte [edi + SOCKET.state], TCP_STATE_LISTEN
    
    xor eax, eax                ; success
    pop edi
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop edi
    pop ebx
    ret

; Accept connection (non-blocking)
; EBX = socket ID
; Returns: EAX = new socket ID or -1 if no connection
tcp_accept:
    push ebx
    push ecx
    push edi
    
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    mov edi, eax
    
    ; check if socket is listening
    cmp byte [edi + SOCKET.state], TCP_STATE_LISTEN
    jne .error
    
    ; find established connection on same port
    xor ecx, ecx                ; socket index
.find_connection:
    cmp ecx, MAX_SOCKETS
    jae .no_connection
    
    cmp ecx, ebx                ; skip listening socket
    je .next
    
    mov eax, ecx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    
    ; check if established and same local port
    cmp byte [eax + SOCKET.state], TCP_STATE_ESTABLISHED
    jne .next
    
    mov dx, word [edi + SOCKET.local_port]
    cmp word [eax + SOCKET.local_port], dx
    jne .next
    
    ; found connection
    mov eax, ecx                ; return new socket ID
    pop edi
    pop ecx
    pop ebx
    ret
    
.next:
    inc ecx
    jmp .find_connection
    
.no_connection:
    mov eax, -1
    pop edi
    pop ecx
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop edi
    pop ecx
    pop ebx
    ret

; Send data
; EBX = socket ID, ESI = data, ECX = length
; Returns: EAX = bytes sent or -1 on error
tcp_send:
    push ebx
    push ecx
    push edi
    push esi
    
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    mov edi, eax
    
    ; check if established
    cmp byte [edi + SOCKET.state], TCP_STATE_ESTABLISHED
    jne .error
    
    ; for now, just send directly (simplified)
    ; in real implementation, would queue to tx_buffer
    
    ; build TCP packet
    call tcp_build_packet
    test eax, eax
    jz .error
    
    ; send via network (simplified - would use send_ethernet_frame)
    ; call send_ethernet_frame
    
    mov eax, ecx                ; return bytes sent
    pop esi
    pop edi
    pop ecx
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop esi
    pop edi
    pop ecx
    pop ebx
    ret

; Receive data
; EBX = socket ID, EDI = buffer, ECX = max length
; Returns: EAX = bytes received or -1 on error/no data
tcp_recv:
    push ebx
    push ecx
    push edi
    
    cmp ebx, MAX_SOCKETS
    jae .error
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    
    ; check if established
    cmp byte [eax + SOCKET.state], TCP_STATE_ESTABLISHED
    jne .error
    
    ; check if data available
    movzx edx, word [eax + SOCKET.rx_length]
    test edx, edx
    jz .no_data
    
    ; copy data to buffer
    push esi
    mov esi, [eax + SOCKET.rx_buffer]
    cmp edx, ecx
    jbe .copy_size
    mov edx, ecx                ; cap to max length
.copy_size:
    mov ecx, edx
    rep movsb
    pop esi
    
    ; clear rx buffer
    mov dword [eax + SOCKET.rx_buffer], 0
    mov word [eax + SOCKET.rx_length], 0
    
    mov eax, edx                ; return bytes received
    pop edi
    pop ecx
    pop ebx
    ret
    
.no_data:
    xor eax, eax                ; no data available
    pop edi
    pop ecx
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop edi
    pop ecx
    pop ebx
    ret

; Close socket
; EBX = socket ID
tcp_close:
    push ebx
    push edi
    
    cmp ebx, MAX_SOCKETS
    jae .done
    
    ; get socket pointer
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    mov edi, eax
    
    ; send FIN if established
    cmp byte [edi + SOCKET.state], TCP_STATE_ESTABLISHED
    jne .close_now
    
    ; send FIN packet
    mov byte [edi + SOCKET.state], TCP_STATE_FIN_WAIT_1
    call tcp_send_fin
    jmp .done
    
.close_now:
    ; immediately close
    mov byte [edi + SOCKET.state], TCP_STATE_CLOSED
    
.done:
    pop edi
    pop ebx
    ret

; ========================================
; TCP PACKET PROCESSING
; ========================================

; Process incoming TCP packet
; ESI = IP packet start
tcp_process_packet:
    pusha
    
    ; get IP header length
    mov al, [esi + IP_VERSION_IHL]
    and al, 0x0F
    shl al, 2                   ; multiply by 4
    movzx eax, al
    
    ; TCP header is after IP header
    add esi, eax
    
    ; extract fields
    mov ax, [esi + TCP_SRC_PORT]
    xchg al, ah                 ; convert to little endian
    mov [.remote_port], ax
    
    mov ax, [esi + TCP_DEST_PORT]
    xchg al, ah
    mov [.local_port], ax
    
    mov al, [esi + TCP_FLAGS]
    mov [.flags], al
    
    ; find matching socket
    call tcp_find_socket
    cmp eax, -1
    je .no_socket
    
    ; process based on state
    mov ebx, eax                ; socket ID
    imul eax, SOCKET_SIZE
    add eax, socket_table
    
    mov cl, [eax + SOCKET.state]
    cmp cl, TCP_STATE_LISTEN
    je .handle_syn
    cmp cl, TCP_STATE_ESTABLISHED
    je .handle_established
    jmp .done
    
.handle_syn:
    ; check for SYN flag
    test byte [.flags], TCP_SYN
    jz .done
    
    ; create new socket for connection
    call tcp_socket
    cmp eax, -1
    je .done
    
    ; setup connection
    mov ebx, eax
    imul ebx, SOCKET_SIZE
    add ebx, socket_table
    
    mov ax, [.local_port]
    mov [ebx + SOCKET.local_port], ax
    mov ax, [.remote_port]
    mov [ebx + SOCKET.remote_port], ax
    
    ; send SYN-ACK
    mov byte [ebx + SOCKET.state], TCP_STATE_SYN_RECEIVED
    call tcp_send_synack
    
    ; immediately establish (simplified 3-way handshake)
    mov byte [ebx + SOCKET.state], TCP_STATE_ESTABLISHED
    jmp .done
    
.handle_established:
    ; check for data
    mov al, [esi + TCP_DATA_OFF]
    shr al, 4
    shl al, 2                   ; TCP header length
    movzx ecx, al
    
    ; data starts after TCP header
    push esi
    add esi, ecx
    
    ; calculate data length (simplified)
    mov ecx, 256                ; assume some data
    
    ; store in rx_buffer (simplified)
    mov [eax + SOCKET.rx_buffer], esi
    mov word [eax + SOCKET.rx_length], cx
    
    pop esi
    
    ; send ACK
    call tcp_send_ack
    
.done:
.no_socket:
    popa
    ret

.remote_port:   dw 0
.local_port:    dw 0
.flags:         db 0

; Find socket matching packet
; Returns: EAX = socket ID or -1
tcp_find_socket:
    push ebx
    push ecx
    
    xor ebx, ebx
.check_socket:
    cmp ebx, MAX_SOCKETS
    jae .not_found
    
    mov eax, ebx
    imul eax, SOCKET_SIZE
    add eax, socket_table
    
    ; check local port
    mov cx, [tcp_process_packet.local_port]
    cmp word [eax + SOCKET.local_port], cx
    jne .next
    
    ; found match
    mov eax, ebx
    pop ecx
    pop ebx
    ret
    
.next:
    inc ebx
    jmp .check_socket
    
.not_found:
    mov eax, -1
    pop ecx
    pop ebx
    ret

; Stub functions for packet building
tcp_build_packet:
    mov eax, 1
    ret

tcp_send_fin:
    ret

tcp_send_synack:
    ret

tcp_send_ack:
    ret
