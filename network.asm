; =====================================================
; NETWORK STACK - TCP/IP N SHIT
; let's get this thing online baby
; =====================================================

; Network configuration
LOCAL_IP:       dd 0x0A000202       ; 10.0.2.2 (QEMU default guest IP)
GATEWAY_IP:     dd 0x0A000201       ; 10.0.2.1 (QEMU gateway)
SUBNET_MASK:    dd 0xFFFFFF00       ; 255.255.255.0

; Constants
RTL8139_TX_BUFFER_SIZE equ 2048
RTL8139_RX_BUFFER_SIZE equ 8192 + 16   ; 8KB + 16 byte header

; Ethernet frame offsets
ETH_DEST_MAC    equ 0
ETH_SRC_MAC     equ 6
ETH_TYPE        equ 12
ETH_DATA        equ 14
ETH_HEADER_SIZE equ 14

; Ethernet types
ETHTYPE_ARP     equ 0x0806
ETHTYPE_IP      equ 0x0800

; ARP packet structure
ARP_HTYPE       equ 0           ; Hardware type
ARP_PTYPE       equ 2           ; Protocol type
ARP_HLEN        equ 4           ; Hardware address length
ARP_PLEN        equ 5           ; Protocol address length
ARP_OPER        equ 6           ; Operation
ARP_SHA         equ 8           ; Sender hardware address
ARP_SPA         equ 14          ; Sender protocol address
ARP_THA         equ 18          ; Target hardware address
ARP_TPA         equ 24          ; Target protocol address
ARP_PACKET_SIZE equ 28

; ARP operations
ARP_REQUEST     equ 1
ARP_REPLY       equ 2

; ARP cache (16 entries)
ARP_CACHE_SIZE  equ 16
arp_cache:      times (ARP_CACHE_SIZE * 10) db 0   ; IP (4) + MAC (6) per entry
arp_cache_count: dd 0

; IP header offsets
IP_VERSION_IHL  equ 0
IP_TOS          equ 1
IP_TOTAL_LEN    equ 2
IP_ID           equ 4
IP_FLAGS_FRAG   equ 6
IP_TTL          equ 8
IP_PROTOCOL     equ 9
IP_CHECKSUM     equ 10
IP_SRC          equ 12
IP_DEST         equ 16
IP_HEADER_SIZE  equ 20

; IP protocols
IP_PROTO_ICMP   equ 1
IP_PROTO_TCP    equ 6
IP_PROTO_UDP    equ 17

; ICMP header offsets
ICMP_TYPE       equ 0
ICMP_CODE       equ 1
ICMP_CHECKSUM   equ 2
ICMP_ID         equ 4
ICMP_SEQ        equ 6
ICMP_DATA       equ 8

; ICMP types
ICMP_ECHO_REPLY equ 0
ICMP_ECHO       equ 8

; UDP header offsets
UDP_SRC_PORT    equ 0
UDP_DEST_PORT   equ 2
UDP_LENGTH      equ 4
UDP_CHECKSUM    equ 6
UDP_DATA        equ 8
UDP_HEADER_SIZE equ 8

; network statistics
net_packets_sent: dd 0
net_packets_received: dd 0
net_arp_requests: dd 0
net_arp_replies: dd 0
net_icmp_echo: dd 0
net_icmp_reply: dd 0
ping_sequence: dw 0

; ========================================
; RTL8139 PACKET TRANSMISSION
; time to actually send some shit
; ========================================

; setup RTL8139 so we can yeet packets
init_rtl8139_network:
    pusha
    
    ; tell it where to dump received packets
    mov eax, rtl8139_rx_buffer_data
    mov edx, [rtl8139_io_base]
    add edx, 0x30           ; RBSTART register
    out dx, eax
    
    ; setup 4 TX buffers (we got options baby)
    mov edx, [rtl8139_io_base]
    add edx, 0x20           ; TSAD0
    mov eax, rtl8139_tx_buffer_data
    out dx, eax
    
    add edx, 4              ; TSAD1
    add eax, 2048
    out dx, eax
    
    add edx, 4              ; TSAD2
    add eax, 2048
    out dx, eax
    
    add edx, 4              ; TSAD3
    add eax, 2048
    out dx, eax
    
    ; turn that shit on
    mov edx, [rtl8139_io_base]
    add edx, 0x37           ; CMD register
    mov al, 0x0C            ; RX enable | TX enable
    out dx, al
    
    ; accept all the packets (we're not picky)
    mov edx, [rtl8139_io_base]
    add edx, 0x44           ; RCR register
    mov eax, 0x0000000F     ; Accept all packet types
    out dx, eax
    
    ; reset RX pointer
    mov dword [rtl8139_rx_ptr], 0
    
    popa
    ret

; yeet a packet out the NIC
; ESI = packet data
; ECX = packet length
rtl8139_send_packet:
    pusha
    
    ; make sure it's not too big
    cmp ecx, RTL8139_TX_BUFFER_SIZE
    jg .too_large
    
    ; grab next TX slot
    mov ebx, [rtl8139_tx_current]
    and ebx, 3              ; 0-3 (round robin baby)
    
    ; copy packet to TX buffer
    mov edi, rtl8139_tx_buffer_data
    mov eax, ebx
    shl eax, 11             ; * 2048
    add edi, eax
    
    push ecx
    rep movsb
    pop ecx
    
    ; ethernet min size is 60 bytes
    cmp ecx, 60
    jge .size_ok
    mov ecx, 60
    
    .size_ok:
    ; tell the card to send it
    mov edx, [rtl8139_io_base]
    add edx, 0x10           ; TSD0
    mov eax, ebx
    shl eax, 2
    add edx, eax
    
    mov eax, ecx            ; packet size
    out dx, eax
    
    ; next TX slot
    mov eax, [rtl8139_tx_current]
    inc eax
    and eax, 3
    mov [rtl8139_tx_current], eax
    
    ; stats++
    inc dword [net_packets_sent]
    
    .too_large:
    popa
    ret

; ========================================
; ETHERNET LAYER
; wrap shit in ethernet frames
; ========================================

; build and send ethernet frame
; EDI = dest MAC (6 bytes)
; EBX = ethertype (2 bytes)
; ESI = payload
; ECX = payload length
send_ethernet_frame:
    push eax
    push ecx
    push edi
    
    ; build frame
    mov edi, rtl8139_tx_buffer_data
    
    ; dest MAC
    pop esi                 ; Get dest MAC pointer
    push esi
    movsb
    movsb
    movsb
    movsb
    movsb
    movsb
    
    ; src MAC (us)
    mov esi, rtl8139_mac
    movsb
    movsb
    movsb
    movsb
    movsb
    movsb
    
    ; ethertype
    mov ax, bx
    xchg al, ah             ; big endian
    stosw
    
    ; payload
    pop esi
    push esi
    pop ecx
    push ecx
    rep movsb
    
    ; total length
    pop ecx
    add ecx, ETH_HEADER_SIZE
    
    ; send it
    mov esi, rtl8139_tx_buffer_data
    call rtl8139_send_packet
    
    pop edi
    pop ecx
    pop eax
    ret

; ========================================
; ARP PROTOCOL
; who has this IP?
; ========================================

; ask the network for someone's MAC
; EAX = target IP
send_arp_request:
    pusha
    
    mov [.target_ip], eax
    
    ; build ARP request
    mov edi, rtl8139_tx_buffer_data + ETH_HEADER_SIZE
    
    ; hardware type (ethernet)
    mov ax, 0x0100          ; network byte order
    stosw
    
    ; protocol type (IP)
    mov ax, 0x0008
    stosw
    
    ; MAC length
    mov al, 6
    stosb
    
    ; IP length
    mov al, 4
    stosb
    
    ; operation (request)
    mov ax, 0x0100
    stosw
    
    ; our MAC
    mov esi, rtl8139_mac
    movsb
    movsb
    movsb
    movsb
    movsb
    movsb
    
    ; our IP
    mov eax, [LOCAL_IP]
    stosd
    
    ; target MAC (unknown, all zeros)
    xor eax, eax
    stosw
    stosd
    
    ; target IP
    mov eax, [.target_ip]
    stosd
    
    ; broadcast to everyone
    mov edi, .broadcast_mac
    mov ebx, ETHTYPE_ARP
    mov esi, rtl8139_tx_buffer_data + ETH_HEADER_SIZE
    mov ecx, ARP_PACKET_SIZE
    call send_ethernet_frame
    
    inc dword [net_arp_requests]
    
    popa
    ret
    
    .target_ip: dd 0
    .broadcast_mac: db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

; got an ARP packet, deal with it
; ESI = ARP packet data
handle_arp_packet:
    pusha
    
    ; what kind of ARP?
    mov ax, [esi + ARP_OPER]
    xchg al, ah             ; big endian
    
    cmp ax, ARP_REQUEST
    je .handle_request
    cmp ax, ARP_REPLY
    je .handle_reply
    jmp .done
    
    .handle_request:
        ; asking for us?
        mov eax, [esi + ARP_TPA]
        cmp eax, [LOCAL_IP]
        jne .done
        
        ; TODO: send reply
        inc dword [net_arp_requests]
        jmp .done
    
    .handle_reply:
        ; cache it
        inc dword [net_arp_replies]
        call add_to_arp_cache
        jmp .done
    
    .done:
    popa
    ret

; remember this IP->MAC mapping
; ESI = ARP packet
add_to_arp_cache:
    pusha
    
    ; who sent it?
    mov eax, [esi + ARP_SPA]
    mov [.sender_ip], eax
    
    ; got room in cache?
    mov ecx, [arp_cache_count]
    cmp ecx, ARP_CACHE_SIZE
    jge .done               ; full, fuck it
    
    ; add to cache
    mov edi, arp_cache
    mov eax, ecx
    imul eax, 10            ; 10 bytes per entry
    add edi, eax
    
    ; store IP
    mov eax, [.sender_ip]
    stosd
    
    ; store MAC
    lea esi, [esi + ARP_SHA]
    movsb
    movsb
    movsb
    movsb
    movsb
    movsb
    
    inc dword [arp_cache_count]
    
    .done:
    popa
    ret
    
    .sender_ip: dd 0

; find MAC for this IP
; EAX = IP address
; Returns: EDI = MAC address (or NULL if we don't know)
arp_lookup:
    push ebx
    push ecx
    push esi
    
    mov ecx, [arp_cache_count]
    test ecx, ecx
    jz .not_found
    
    mov esi, arp_cache
    
    .search_loop:
        cmp eax, [esi]
        je .found
        add esi, 10
        loop .search_loop
    
    .not_found:
        xor edi, edi        ; nope
        jmp .done
    
    .found:
        lea edi, [esi + 4]  ; got it
    
    .done:
    pop esi
    pop ecx
    pop ebx
    ret

; ========================================
; IP LAYER
; internet protocol baby
; ========================================

; calculate IP checksum (ones complement)
; ESI = IP header
; ECX = header length
; Returns: AX = checksum
ip_checksum:
    push ebx
    push ecx
    push edx
    push esi
    
    xor eax, eax
    xor ebx, ebx
    shr ecx, 1              ; bytes to words
    
    .sum_loop:
        lodsw
        add ebx, eax
        loop .sum_loop
    
    ; fold carries
    mov eax, ebx
    shr eax, 16
    and ebx, 0xFFFF
    add eax, ebx
    
    ; flip it
    not ax
    
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; send an IP packet
; EAX = dest IP
; BL = protocol
; ESI = payload
; ECX = payload length
send_ip_packet:
    pusha
    
    mov [.dest_ip], eax
    mov [.protocol], bl
    mov [.payload], esi
    mov [.payload_len], ecx
    
    ; find dest MAC
    call arp_lookup
    test edi, edi
    jz .no_mac              ; gotta ARP first
    
    mov [.dest_mac], edi
    
    ; build IP header
    mov edi, rtl8139_tx_buffer_data + ETH_HEADER_SIZE
    
    ; version 4, header len 5 (20 bytes)
    mov al, 0x45
    stosb
    
    ; type of service (meh)
    xor al, al
    stosb
    
    ; total length
    mov ax, [.payload_len]
    add ax, IP_HEADER_SIZE
    xchg al, ah
    stosw
    
    ; packet ID
    mov ax, 0x1234
    stosw
    
    ; flags/fragment offset
    xor ax, ax
    stosw
    
    ; TTL (hop limit)
    mov al, 64
    stosb
    
    ; protocol
    mov al, [.protocol]
    stosb
    
    ; checksum (calculate later)
    xor ax, ax
    stosw
    
    ; source IP (us)
    mov eax, [LOCAL_IP]
    stosd
    
    ; dest IP
    mov eax, [.dest_ip]
    stosd
    
    ; now calculate checksum
    mov esi, rtl8139_tx_buffer_data + ETH_HEADER_SIZE
    mov ecx, IP_HEADER_SIZE
    call ip_checksum
    mov [esi + IP_CHECKSUM], ax
    
    ; add payload
    mov esi, [.payload]
    mov ecx, [.payload_len]
    rep movsb
    
    ; yeet it
    mov edi, [.dest_mac]
    mov ebx, ETHTYPE_IP
    mov esi, rtl8139_tx_buffer_data + ETH_HEADER_SIZE
    mov ecx, [.payload_len]
    add ecx, IP_HEADER_SIZE
    call send_ethernet_frame
    
    jmp .done
    
    .no_mac:
        ; send ARP first
        mov eax, [.dest_ip]
        call send_arp_request
    
    .done:
    popa
    ret
    
    .dest_ip: dd 0
    .protocol: db 0
    .payload: dd 0
    .payload_len: dd 0
    .dest_mac: dd 0

; ========================================
; ICMP (PING!)
; can we reach this fucker?
; ========================================

; send a ping
; EAX = dest IP
send_ping:
    pusha
    
    mov [.dest_ip], eax
    
    ; build ICMP echo request
    mov edi, .icmp_packet
    
    ; type = echo request
    mov al, ICMP_ECHO
    stosb
    
    ; code
    xor al, al
    stosb
    
    ; checksum (later)
    xor ax, ax
    stosw
    
    ; ID
    mov ax, 0x1234
    stosw
    
    ; sequence number
    mov ax, [ping_sequence]
    inc word [ping_sequence]
    xchg al, ah
    stosw
    
    ; data (just some bullshit)
    mov ecx, 32
    mov al, 0x42
    rep stosb
    
    ; calculate checksum
    mov esi, .icmp_packet
    mov ecx, 40             ; 8 header + 32 data
    call ip_checksum
    mov [.icmp_packet + ICMP_CHECKSUM], ax
    
    ; Send as IP packet
    mov eax, [.dest_ip]
    mov bl, IP_PROTO_ICMP
    mov esi, .icmp_packet
    mov ecx, 40
    call send_ip_packet
    
    inc dword [net_icmp_echo]
    
    popa
    ret
    
    .dest_ip: dd 0
    .icmp_packet: times 40 db 0

; got an ICMP packet
; ESI = ICMP packet
; EDI = source IP
handle_icmp_packet:
    pusha
    
    ; what kind?
    mov al, [esi + ICMP_TYPE]
    
    cmp al, ICMP_ECHO
    je .handle_echo_request
    cmp al, ICMP_ECHO_REPLY
    je .handle_echo_reply
    jmp .done
    
    .handle_echo_request:
        ; TODO: send reply
        jmp .done
    
    .handle_echo_reply:
        ; fuck yeah, got a reply!
        inc dword [net_icmp_reply]
        
        ; tell the user
        push esi
        mov esi, msg_ping_reply
        call print_string
        
        ; show IP
        mov eax, edi
        call print_ip_address
        
        mov al, 10
        call print_char
        pop esi
        jmp .done
    
    .done:
    popa
    ret

; print IP in dotted format (1.2.3.4)
; EAX = IP (little endian)
print_ip_address:
    pusha
    
    ; first byte
    movzx ebx, al
    push eax
    mov eax, ebx
    call print_decimal
    mov al, '.'
    call print_char
    pop eax
    
    ; second byte
    shr eax, 8
    movzx ebx, al
    push eax
    mov eax, ebx
    call print_decimal
    mov al, '.'
    call print_char
    pop eax
    
    ; third byte
    shr eax, 8
    movzx ebx, al
    push eax
    mov eax, ebx
    call print_decimal
    mov al, '.'
    call print_char
    pop eax
    
    ; last byte
    shr eax, 8
    movzx ebx, al
    mov eax, ebx
    call print_decimal
    
    popa
    ret

; ========================================
; PACKET RECEPTION
; handle incoming shit
; ========================================

; got a packet, process it
rtl8139_handle_rx:
    pusha
    
    ; check RX buffer
    mov edx, [rtl8139_io_base]
    add edx, 0x3E           ; CAPR
    in ax, dx
    
    ; grab packet
    mov esi, rtl8139_rx_buffer_data
    add esi, [rtl8139_rx_ptr]
    
    ; read header
    lodsd                   ; status + length
    mov ebx, eax
    shr ebx, 16             ; just the length
    
    ; count it
    inc dword [net_packets_received]
    
    ; what kind of packet?
    mov ax, [esi + ETH_TYPE]
    xchg al, ah
    
    cmp ax, ETHTYPE_ARP
    je .handle_arp
    cmp ax, ETHTYPE_IP
    je .handle_ip
    jmp .done
    
    .handle_arp:
        add esi, ETH_HEADER_SIZE
        call handle_arp_packet
        jmp .done
    
    .handle_ip:
        add esi, ETH_HEADER_SIZE
        ; what protocol?
        mov al, [esi + IP_PROTOCOL]
        cmp al, IP_PROTO_ICMP
        je .handle_icmp
        jmp .done
        
        .handle_icmp:
            ; grab source IP
            mov edi, [esi + IP_SRC]
            add esi, IP_HEADER_SIZE
            call handle_icmp_packet
            jmp .done
    
    .done:
    ; update RX pointer (4-byte aligned)
    mov eax, ebx
    add eax, 4              ; header
    add eax, 3
    and eax, 0xFFFFFFFC     ; align
    add [rtl8139_rx_ptr], eax
    
    ; wrap around if needed
    mov eax, [rtl8139_rx_ptr]
    cmp eax, RTL8139_RX_BUFFER_SIZE
    jl .no_wrap
    sub eax, RTL8139_RX_BUFFER_SIZE
    mov [rtl8139_rx_ptr], eax
    
    .no_wrap:
    popa
    ret

; ========================================
; NETWORK COMMANDS
; show stats n shit
; ========================================

; show network info
show_network_stats:
    pusha
    
    mov esi, msg_net_stats
    call print_string
    
    ; our IP
    mov esi, msg_net_ip
    call print_string
    mov eax, [LOCAL_IP]
    call print_ip_address
    mov al, 10
    call print_char
    
    ; our MAC
    mov esi, msg_net_mac
    call print_string
    movzx eax, byte [rtl8139_mac]
    call print_hex_byte
    mov al, ':'
    call print_char
    movzx eax, byte [rtl8139_mac + 1]
    call print_hex_byte
    mov al, ':'
    call print_char
    movzx eax, byte [rtl8139_mac + 2]
    call print_hex_byte
    mov al, ':'
    call print_char
    movzx eax, byte [rtl8139_mac + 3]
    call print_hex_byte
    mov al, ':'
    call print_char
    movzx eax, byte [rtl8139_mac + 4]
    call print_hex_byte
    mov al, ':'
    call print_char
    movzx eax, byte [rtl8139_mac + 5]
    call print_hex_byte
    mov al, 10
    call print_char
    
    ; packets sent
    mov esi, msg_net_tx
    call print_string
    mov eax, [net_packets_sent]
    call print_decimal
    mov al, 10
    call print_char
    
    mov esi, msg_net_rx
    call print_string
    mov eax, [net_packets_received]
    call print_decimal
    mov al, 10
    call print_char
    
    ; ARP cache size
    mov esi, msg_arp_cache
    call print_string
    mov eax, [arp_cache_count]
    call print_decimal
    mov esi, msg_entries
    call print_string
    
    popa
    ret

; Messages
msg_ping_reply:     db 'Ping reply from ', 0
msg_net_stats:      db 'Network Statistics:', 10, 0
msg_net_ip:         db '  IP Address: ', 0
msg_net_mac:        db '  MAC Address: ', 0
msg_net_tx:         db '  Packets sent: ', 0
msg_net_rx:         db '  Packets received: ', 0
msg_arp_cache:      db '  ARP cache: ', 0
msg_entries:        db ' entries', 10, 0
