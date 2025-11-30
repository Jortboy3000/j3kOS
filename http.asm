; =====================================================
; HTTP CLIENT - HYPERTEXT TRANSFER PROTOCOL
; GET and POST requests, header parsing, responses
; =====================================================

; HTTP methods
HTTP_METHOD_GET     equ 0
HTTP_METHOD_POST    equ 1
HTTP_METHOD_PUT     equ 2
HTTP_METHOD_DELETE  equ 3

; HTTP status codes
HTTP_OK             equ 200
HTTP_CREATED        equ 201
HTTP_BAD_REQUEST    equ 400
HTTP_NOT_FOUND      equ 404
HTTP_SERVER_ERROR   equ 500

; HTTP request structure
struc HTTP_REQUEST
    .method:        resb 1      ; GET/POST/etc
    .host:          resd 1      ; pointer to host string
    .port:          resw 1      ; port number
    .path:          resd 1      ; pointer to path string
    .headers:       resd 1      ; pointer to headers
    .body:          resd 1      ; pointer to body data
    .body_length:   resd 1      ; body length
endstruc

; HTTP response structure
struc HTTP_RESPONSE
    .status_code:   resw 1      ; HTTP status code
    .headers:       resd 1      ; pointer to headers
    .body:          resd 1      ; pointer to body
    .body_length:   resd 1      ; body length
endstruc

; HTTP buffers
http_request_buffer:    times 512 db 0
http_response_buffer:   times 2048 db 0
http_temp_buffer:       times 256 db 0

; ========================================
; HTTP REQUEST BUILDING
; ========================================

; Build HTTP GET request
; ESI = host, EDI = path, CX = port
; Returns: EAX = pointer to request buffer, ECX = length
http_build_get:
    pusha
    
    ; build request line: "GET /path HTTP/1.1\r\n"
    mov edi, http_request_buffer
    
    ; "GET "
    mov al, 'G'
    stosb
    mov al, 'E'
    stosb
    mov al, 'T'
    stosb
    mov al, ' '
    stosb
    
    ; path
    push esi
    mov esi, [esp + 36]         ; get path from stack
    call http_copy_string
    pop esi
    
    ; " HTTP/1.1\r\n"
    mov al, ' '
    stosb
    mov esi, .http_version
    call http_copy_string
    
    ; "Host: hostname\r\n"
    mov esi, .host_header
    call http_copy_string
    
    mov esi, [esp + 32]         ; get host from stack
    call http_copy_string
    
    mov ax, 0x0A0D              ; \r\n
    stosw
    
    ; "Connection: close\r\n"
    mov esi, .conn_header
    call http_copy_string
    
    ; "\r\n" (end of headers)
    mov ax, 0x0A0D
    stosw
    
    ; calculate length
    mov eax, edi
    sub eax, http_request_buffer
    mov [.length], eax
    
    popa
    mov eax, http_request_buffer
    mov ecx, [.length]
    ret

.http_version:  db ' HTTP/1.1', 13, 10, 0
.host_header:   db 'Host: ', 0
.conn_header:   db 'Connection: close', 13, 10, 0
.length:        dd 0

; Build HTTP POST request
; ESI = host, EDI = path, EBX = body, ECX = body_length
; Returns: EAX = pointer to request buffer, ECX = length
http_build_post:
    pusha
    
    ; build request line: "POST /path HTTP/1.1\r\n"
    mov edi, http_request_buffer
    
    ; "POST "
    mov esi, .post_method
    call http_copy_string
    
    ; path
    mov esi, [esp + 36]         ; get path from stack
    call http_copy_string
    
    ; " HTTP/1.1\r\n"
    mov esi, .http_version
    call http_copy_string
    
    ; "Host: hostname\r\n"
    mov esi, .host_header
    call http_copy_string
    
    mov esi, [esp + 32]         ; get host from stack
    call http_copy_string
    
    mov ax, 0x0A0D
    stosw
    
    ; "Content-Type: application/json\r\n"
    mov esi, .content_type
    call http_copy_string
    
    ; "Content-Length: XXX\r\n"
    mov esi, .content_length
    call http_copy_string
    
    mov eax, [esp + 24]         ; get body_length
    call http_int_to_string
    
    mov ax, 0x0A0D
    stosw
    
    ; "Connection: close\r\n"
    mov esi, .conn_header
    call http_copy_string
    
    ; "\r\n" (end of headers)
    mov ax, 0x0A0D
    stosw
    
    ; body
    mov esi, [esp + 28]         ; get body pointer
    mov ecx, [esp + 24]         ; get body_length
    rep movsb
    
    ; calculate total length
    mov eax, edi
    sub eax, http_request_buffer
    mov [.length], eax
    
    popa
    mov eax, http_request_buffer
    mov ecx, [.length]
    ret

.post_method:   db 'POST ', 0
.http_version:  db ' HTTP/1.1', 13, 10, 0
.host_header:   db 'Host: ', 0
.content_type:  db 'Content-Type: application/json', 13, 10, 0
.content_length: db 'Content-Length: ', 0
.conn_header:   db 'Connection: close', 13, 10, 0
.length:        dd 0

; ========================================
; HTTP RESPONSE PARSING
; ========================================

; Parse HTTP response
; ESI = response data, ECX = length
; Returns: EAX = pointer to HTTP_RESPONSE structure
http_parse_response:
    pusha
    
    ; parse status line: "HTTP/1.1 200 OK\r\n"
    call http_skip_to_space
    call http_skip_to_space
    
    ; parse status code
    call http_parse_number
    mov [http_response_buffer + HTTP_RESPONSE.status_code], ax
    
    ; skip to headers
    call http_skip_line
    
    ; find body (after \r\n\r\n)
    call http_find_body
    mov [http_response_buffer + HTTP_RESPONSE.body], eax
    
    ; calculate body length (simplified - rest of data)
    push esi
    add esi, ecx
    sub esi, eax
    mov [http_response_buffer + HTTP_RESPONSE.body_length], esi
    pop esi
    
    popa
    mov eax, http_response_buffer
    ret

; Skip to next space
http_skip_to_space:
    push eax
.loop:
    lodsb
    cmp al, ' '
    je .done
    cmp al, 0
    je .done
    jmp .loop
.done:
    pop eax
    ret

; Skip to next line
http_skip_line:
    push eax
.loop:
    lodsb
    cmp al, 10                  ; \n
    je .done
    cmp al, 0
    je .done
    jmp .loop
.done:
    pop eax
    ret

; Find HTTP body (after \r\n\r\n)
http_find_body:
    push ebx
    push ecx
    xor ebx, ebx
.loop:
    lodsb
    cmp al, 13                  ; \r
    je .check_sequence
    xor ebx, ebx
    jmp .loop
    
.check_sequence:
    inc ebx
    cmp ebx, 1
    je .loop
    
    lodsb
    cmp al, 10                  ; \n
    jne .reset
    
    inc ebx
    cmp ebx, 4                  ; found \r\n\r\n
    je .found
    jmp .loop
    
.reset:
    xor ebx, ebx
    jmp .loop
    
.found:
    mov eax, esi                ; body starts here
    pop ecx
    pop ebx
    ret

; Parse number from string
; ESI = string
; Returns: AX = number
http_parse_number:
    push ebx
    push ecx
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
.loop:
    mov cl, [esi]
    inc esi
    
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    jmp .loop
    
.done:
    pop ecx
    pop ebx
    ret

; ========================================
; HTTP CLIENT OPERATIONS
; ========================================

; Send HTTP GET request
; ESI = host, EDI = path, EBX = remote IP, CX = port
; Returns: EAX = response buffer, ECX = response length
http_get:
    pusha
    
    ; create socket
    call tcp_socket
    cmp eax, -1
    je .error
    mov [.socket_id], eax
    
    ; connect to server (simplified - assume port 80)
    ; in real implementation, would do TCP connect
    
    ; build GET request
    call http_build_get
    
    ; send request
    mov ebx, [.socket_id]
    mov esi, eax
    call tcp_send
    
    ; receive response (simplified polling)
    mov edi, http_response_buffer
    mov ecx, 2048
    mov ebx, [.socket_id]
    
.wait_response:
    call tcp_recv
    cmp eax, 0
    jg .got_data
    
    ; wait a bit (simplified)
    push ecx
    mov ecx, 100000
.delay:
    loop .delay
    pop ecx
    
    jmp .wait_response
    
.got_data:
    mov [.response_length], eax
    
    ; close socket
    mov ebx, [.socket_id]
    call tcp_close
    
    ; parse response
    mov esi, http_response_buffer
    mov ecx, [.response_length]
    call http_parse_response
    
    popa
    mov eax, http_response_buffer
    mov ecx, [.response_length]
    ret
    
.error:
    popa
    xor eax, eax
    xor ecx, ecx
    ret

.socket_id:         dd 0
.response_length:   dd 0

; Send HTTP POST request
; ESI = host, EDI = path, EBX = remote IP, ECX = body, EDX = body_length
; Returns: EAX = response buffer, ECX = response length
http_post:
    pusha
    
    ; create socket
    call tcp_socket
    cmp eax, -1
    je .error
    mov [.socket_id], eax
    
    ; save parameters
    mov [.body], ecx
    mov [.body_length], edx
    
    ; build POST request
    mov ebx, [.body]
    mov ecx, [.body_length]
    call http_build_post
    
    ; send request
    mov ebx, [.socket_id]
    mov esi, eax
    call tcp_send
    
    ; receive response (similar to GET)
    mov edi, http_response_buffer
    mov ecx, 2048
    mov ebx, [.socket_id]
    
.wait_response:
    call tcp_recv
    cmp eax, 0
    jg .got_data
    
    push ecx
    mov ecx, 100000
.delay:
    loop .delay
    pop ecx
    
    jmp .wait_response
    
.got_data:
    mov [.response_length], eax
    
    ; close socket
    mov ebx, [.socket_id]
    call tcp_close
    
    ; parse response
    mov esi, http_response_buffer
    mov ecx, [.response_length]
    call http_parse_response
    
    popa
    mov eax, http_response_buffer
    mov ecx, [.response_length]
    ret
    
.error:
    popa
    xor eax, eax
    xor ecx, ecx
    ret

.socket_id:         dd 0
.body:              dd 0
.body_length:       dd 0
.response_length:   dd 0

; ========================================
; HELPER FUNCTIONS
; ========================================

; Copy null-terminated string
; ESI = source, EDI = destination
http_copy_string:
    push eax
.loop:
    lodsb
    test al, al
    jz .done
    stosb
    jmp .loop
.done:
    pop eax
    ret

; Convert integer to string
; EAX = number, EDI = destination
http_int_to_string:
    push eax
    push ebx
    push ecx
    push edx
    
    mov ebx, 10
    xor ecx, ecx
    
.convert_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .convert_loop
    
.write_loop:
    pop eax
    add al, '0'
    stosb
    loop .write_loop
    
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret
