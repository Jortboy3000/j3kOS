; =====================================================
; NETWORK EXTENSIONS MODULE
; TCP/HTTP/JSON/REST API - Loadable Module
; Combined from tcp.asm, http.asm, json.asm, rest_api.asm
; =====================================================

[BITS 32]
[ORG 0x50000]  ; Load at 320KB

module_start:
    ; Module signature
    db 'J3KMOD', 0
    dd module_end - module_start
    
    ; Jump table for exported functions
    jmp tcp_socket
    jmp tcp_bind
    jmp tcp_listen
    jmp tcp_accept
    jmp tcp_send
    jmp tcp_recv
    jmp tcp_close
    jmp http_build_get
    jmp http_build_post
    jmp http_get
    jmp http_post
    jmp json_parse
    jmp json_build
    jmp api_start_server
    jmp api_register
    jmp api_init_endpoints

; Include the full implementations
%include "tcp.asm"
%include "http.asm"
%include "json.asm"
%include "rest_api.asm"

module_end:
