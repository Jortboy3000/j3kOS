; =====================================================
; REST API - REPRESENTATIONAL STATE TRANSFER
; HTTP endpoint routing, JSON request/response handling
; =====================================================

; API endpoint structure (32 bytes)
struc API_ENDPOINT
    .method:        resb 1      ; HTTP method (GET/POST/PUT/DELETE)
    .path:          resd 1      ; pointer to path string
    .handler:       resd 1      ; pointer to handler function
    .padding:       resb 23     ; pad to 32 bytes
endstruc

; API context passed to handlers
struc API_CONTEXT
    .request:       resd 1      ; pointer to HTTP_REQUEST
    .response:      resd 1      ; pointer to HTTP_RESPONSE
    .json_data:     resd 1      ; pointer to parsed JSON
    .params:        resd 1      ; pointer to URL parameters
endstruc

; API endpoint table (max 32 endpoints)
MAX_ENDPOINTS       equ 32
api_endpoints:      times (MAX_ENDPOINTS * 32) db 0
api_endpoint_count: dd 0

; API buffers
api_response_buffer:    times 1024 db 0
api_json_buffer:        times 512 db 0

; ========================================
; API SERVER
; ========================================

; Start REST API server on port
; CX = port number
; Returns: EAX = server socket ID or -1
api_start_server:
    pusha
    
    ; create listening socket
    call tcp_socket
    cmp eax, -1
    je .error
    mov [.server_socket], eax
    
    ; bind to port
    mov ebx, eax
    call tcp_bind
    cmp eax, -1
    je .error
    
    ; listen
    mov ebx, [.server_socket]
    mov cx, 5                   ; backlog
    call tcp_listen
    cmp eax, -1
    je .error
    
    mov esi, .msg_started
    call print_string
    
    popa
    mov eax, [.server_socket]
    ret
    
.error:
    popa
    mov eax, -1
    ret

.server_socket: dd 0
.msg_started:   db 'REST API server started', 10, 0

; Handle incoming API request
; EBX = server socket ID
; Returns: EAX = 0 on success
api_handle_request:
    pusha
    
    ; accept connection
    call tcp_accept
    cmp eax, -1
    je .no_connection
    
    mov [.client_socket], eax
    
    ; receive HTTP request
    mov edi, http_request_buffer
    mov ecx, 512
    mov ebx, eax
    call tcp_recv
    cmp eax, 0
    jle .close_client
    
    mov [.request_length], eax
    
    ; parse HTTP request
    mov esi, http_request_buffer
    call api_parse_request
    test eax, eax
    jz .send_error
    
    ; route request to handler
    call api_route_request
    test eax, eax
    jz .send_not_found
    
    ; handler should have built response
    jmp .send_response
    
.send_error:
    mov cx, HTTP_SERVER_ERROR
    call api_build_error_response
    jmp .send_response
    
.send_not_found:
    mov cx, HTTP_NOT_FOUND
    call api_build_error_response
    
.send_response:
    ; send response
    mov esi, api_response_buffer
    mov ecx, [.response_length]
    mov ebx, [.client_socket]
    call tcp_send
    
.close_client:
    mov ebx, [.client_socket]
    call tcp_close
    
.no_connection:
    popa
    xor eax, eax
    ret

.client_socket:     dd 0
.request_length:    dd 0
.response_length:   dd 0

; ========================================
; REQUEST PARSING & ROUTING
; ========================================

; Parse HTTP request
; ESI = request buffer
; Returns: EAX = pointer to request structure
api_parse_request:
    pusha
    
    ; parse method (GET/POST/PUT/DELETE)
    mov edi, .method_buffer
    xor ecx, ecx
.parse_method:
    lodsb
    cmp al, ' '
    je .method_done
    stosb
    inc ecx
    cmp ecx, 10
    jb .parse_method
    
.method_done:
    xor al, al
    stosb
    
    ; parse path
    mov edi, .path_buffer
    xor ecx, ecx
.parse_path:
    lodsb
    cmp al, ' '
    je .path_done
    cmp al, '?'                 ; query string
    je .parse_params
    stosb
    inc ecx
    cmp ecx, 64
    jb .parse_path
    
.parse_params:
    ; skip query params for now
.skip_to_space:
    lodsb
    cmp al, ' '
    jne .skip_to_space
    
.path_done:
    xor al, al
    stosb
    
    ; determine method type
    mov esi, .method_buffer
    cmp dword [esi], 'GET '
    je .method_get
    cmp dword [esi], 'POST'
    je .method_post
    cmp dword [esi], 'PUT '
    je .method_put
    cmp dword [esi], 'DELE'
    je .method_delete
    jmp .invalid
    
.method_get:
    mov byte [.request_method], HTTP_METHOD_GET
    jmp .valid
    
.method_post:
    mov byte [.request_method], HTTP_METHOD_POST
    jmp .valid
    
.method_put:
    mov byte [.request_method], HTTP_METHOD_PUT
    jmp .valid
    
.method_delete:
    mov byte [.request_method], HTTP_METHOD_DELETE
    
.valid:
    popa
    mov eax, .request_struct
    ret
    
.invalid:
    popa
    xor eax, eax
    ret

.method_buffer:     times 16 db 0
.path_buffer:       times 64 db 0
.request_method:    db 0
.request_struct:    dd .method_buffer, .path_buffer, 0

; Route request to handler
; Returns: EAX = 1 if handled, 0 if not found
api_route_request:
    push ebx
    push ecx
    push esi
    push edi
    
    mov ebx, api_endpoints
    xor ecx, ecx
    
.check_endpoint:
    cmp ecx, [api_endpoint_count]
    jae .not_found
    
    ; check method
    mov al, [api_parse_request.request_method]
    cmp al, [ebx + API_ENDPOINT.method]
    jne .next_endpoint
    
    ; check path
    mov esi, [ebx + API_ENDPOINT.path]
    mov edi, api_parse_request.path_buffer
    call api_strcmp
    test eax, eax
    jnz .next_endpoint
    
    ; found match - call handler
    mov eax, [ebx + API_ENDPOINT.handler]
    call eax
    
    mov eax, 1
    jmp .done
    
.next_endpoint:
    add ebx, 32
    inc ecx
    jmp .check_endpoint
    
.not_found:
    xor eax, eax
    
.done:
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; ========================================
; ENDPOINT REGISTRATION
; ========================================

; Register API endpoint
; AL = method, ESI = path, EDI = handler function
; Returns: EAX = 0 on success, -1 on error
api_register:
    push ebx
    push ecx
    
    mov ecx, [api_endpoint_count]
    cmp ecx, MAX_ENDPOINTS
    jae .error
    
    ; get endpoint slot
    imul ecx, 32
    add ecx, api_endpoints
    mov ebx, ecx
    
    ; fill endpoint
    mov [ebx + API_ENDPOINT.method], al
    mov [ebx + API_ENDPOINT.path], esi
    mov [ebx + API_ENDPOINT.handler], edi
    
    inc dword [api_endpoint_count]
    
    xor eax, eax
    pop ecx
    pop ebx
    ret
    
.error:
    mov eax, -1
    pop ecx
    pop ebx
    ret

; ========================================
; RESPONSE BUILDING
; ========================================

; Build JSON response
; ESI = JSON data, CX = status code
; Returns: EAX = response buffer, ECX = length
api_build_json_response:
    pusha
    
    mov edi, api_response_buffer
    
    ; status line
    mov eax, 'HTTP'
    stosd
    mov ax, '/1'
    stosw
    mov ax, '.1'
    stosw
    mov al, ' '
    stosb
    
    ; status code
    movzx eax, cx
    call http_int_to_string
    
    mov al, ' '
    stosb
    
    ; status text (simplified)
    cmp cx, 200
    je .ok
    cmp cx, 201
    je .created
    jmp .status_done
    
.ok:
    mov eax, 'OK'
    stosw
    jmp .status_done
    
.created:
    mov eax, 'Crea'
    stosd
    mov eax, 'ted'
    stosd
    
.status_done:
    mov ax, 0x0A0D
    stosw
    
    ; headers
    push esi
    mov esi, .content_type_header
    call http_copy_string
    pop esi
    
    ; content length (calculate from JSON)
    push esi
    push edi
    mov edi, .temp_json_buffer
    call http_copy_string
    mov ecx, edi
    sub ecx, .temp_json_buffer
    dec ecx                     ; don't count null
    pop edi
    pop esi
    
    push esi
    mov esi, .content_length_header
    call http_copy_string
    pop esi
    
    mov eax, ecx
    call http_int_to_string
    
    mov ax, 0x0A0D
    stosw
    
    ; end headers
    mov ax, 0x0A0D
    stosw
    
    ; body (JSON)
    call http_copy_string
    
    ; calculate total length
    mov ecx, edi
    sub ecx, api_response_buffer
    mov [.total_length], ecx
    
    popa
    mov eax, api_response_buffer
    mov ecx, [.total_length]
    ret

.content_type_header:   db 'Content-Type: application/json', 13, 10, 0
.content_length_header: db 'Content-Length: ', 0
.temp_json_buffer:      times 256 db 0
.total_length:          dd 0

; Build error response
; CX = status code
; Returns: EAX = response buffer, ECX = length
api_build_error_response:
    pusha
    
    mov edi, api_json_buffer
    
    ; build JSON error object
    mov eax, '{"er'
    stosd
    mov eax, 'ror"'
    stosd
    mov ax, ':'
    stosw
    mov al, '"'
    stosb
    
    cmp cx, 404
    je .not_found
    
    ; generic error
    mov esi, .error_generic
    jmp .copy_message
    
.not_found:
    mov esi, .error_not_found
    
.copy_message:
    call http_copy_string
    
    mov ax, '"}'
    stosw
    xor al, al
    stosb
    
    ; build response
    mov esi, api_json_buffer
    call api_build_json_response
    
    popa
    mov eax, api_response_buffer
    mov ecx, [api_build_json_response.total_length]
    ret

.error_generic:     db 'Internal server error', 0
.error_not_found:   db 'Endpoint not found', 0

; ========================================
; EXAMPLE HANDLERS
; ========================================

; Example: GET /api/status
api_handler_status:
    pusha
    
    ; build JSON response
    mov esi, .json_status
    mov cx, HTTP_OK
    call api_build_json_response
    
    mov [api_handle_request.response_length], ecx
    
    popa
    ret

.json_status:   db '{"status":"online","version":"1.0"}', 0

; Example: GET /api/info
api_handler_info:
    pusha
    
    mov esi, .json_info
    mov cx, HTTP_OK
    call api_build_json_response
    
    mov [api_handle_request.response_length], ecx
    
    popa
    ret

.json_info:     db '{"os":"j3kOS","arch":"x86","mode":"32-bit"}', 0

; Example: POST /api/echo
api_handler_echo:
    pusha
    
    ; parse request body as JSON
    mov esi, http_request_buffer
    call http_find_body
    call json_parse
    
    ; rebuild JSON (echo back)
    mov edi, api_json_buffer
    call json_build
    
    mov esi, api_json_buffer
    mov cx, HTTP_OK
    call api_build_json_response
    
    mov [api_handle_request.response_length], ecx
    
    popa
    ret

; ========================================
; HELPERS
; ========================================

; String compare
; ESI = string1, EDI = string2
; Returns: EAX = 0 if equal, non-zero if different
api_strcmp:
    push esi
    push edi
    
.loop:
    mov al, [esi]
    mov ah, [edi]
    
    cmp al, ah
    jne .not_equal
    
    test al, al
    jz .equal
    
    inc esi
    inc edi
    jmp .loop
    
.equal:
    xor eax, eax
    pop edi
    pop esi
    ret
    
.not_equal:
    mov eax, 1
    pop edi
    pop esi
    ret

; Initialize example API endpoints
api_init_endpoints:
    pusha
    
    ; register GET /api/status
    mov al, HTTP_METHOD_GET
    mov esi, .path_status
    mov edi, api_handler_status
    call api_register
    
    ; register GET /api/info
    mov al, HTTP_METHOD_GET
    mov esi, .path_info
    mov edi, api_handler_info
    call api_register
    
    ; register POST /api/echo
    mov al, HTTP_METHOD_POST
    mov esi, .path_echo
    mov edi, api_handler_echo
    call api_register
    
    popa
    ret

.path_status:   db '/api/status', 0
.path_info:     db '/api/info', 0
.path_echo:     db '/api/echo', 0
