.intel_syntax noprefix
.globl _start
.section .text
        _start:
                # SocketFD : r8
                # ClientFD : r9
                # Syscall Socket
                mov rax, 41             # Syscall Number
                mov rdi, 2              # AF_INET
                mov rsi, 1              # SOCK_STREAM
                mov rdx, 0              # IPPROTO_TCP
                syscall
                mov r8, rax             # Save Socket FD

                # Bind System Call
                mov rax, 49             # Syscall Number
                mov rdi, r8             # Socket FD
                lea rsi, sockaddr_in    # Socket Address Structure
                mov rdx, 16             # Size of Socket Address Structure
                syscall

                # Syscall Listen
                mov rax, 50             # Syscall Number
                mov rdi, r8             # Socket FD
                mov rsi, 0              # Backlog
                syscall

                start_accepting:
                        # Syscall Accept
                        mov rax, 43             # Syscall Number
                        mov rdi, r8             # Socket FD
                        mov rsi, 0              # Client Address
                        mov rdx, 0              # Client Address Length
                        syscall
                        mov r9, rax             # Save Client FD

                        # Fork Process
                        mov rax, 57             # Syscall Number
                        syscall
                        cmp rax, 0              # Check if Child
                        jne close_client        # If not child, close client and loop
                        jmp manage_request      # If child, loop

                close_client:
                        # Close Client FD
                        mov rax, 3           # Syscall Number
                        mov rdi, r9          # File FD
                        syscall
                        jmp start_accepting

                manage_request:
                        # Close Socket FD on Child
                        mov rax, 3           # Syscall Number
                        mov rdi, r8          # Socket FD
                        syscall

                        # Syscall Read from Client
                        mov rax, 0              # Syscall Number
                        mov rdi, r9             # Client FD
                        mov rsi, rsp            # Buffer
                        mov rdx, 512            # Buffer Size
                        syscall

                        # Check if first byte is 'G'
                        mov rax, [rsp]
                        cmp al, 0x47            # Compare to 'G'
                        je get
                        cmp al, 0x50            # Compare to 'P'
                        je post

        get:
               # r10 : FD of File
                mov r13, rsp    # Save Buffer Address

                get_parse_request:
                        mov al, [r13]       # Get next byte
                        cmp al, ' '         # Compare to ' '
                        je get_process_pointer  # If equal, jump to get_found_path
                        add r13, 1          # Increment Buffer Address
                        jmp get_parse_request       # Loop
                get_process_pointer:
                        add r13, 1          # Increment Buffer Address
                        mov rax, r13        # Save Buffer Address
                        jmp get_found_path
                get_found_path:
                        mov cl, [rax]       # Get next byte
                        cmp cl, ' '         # Compare to ' '
                        je get_process_request
                        add rax, 1          # Increment Buffer Address
                        jmp get_found_path
                get_process_request:
                        mov rcx, 0
                        add rax, -1          # Decrement Buffer Address
                        mov byte [rax], cl   # Null Terminate String

                        # Syscall Open File
                        mov rax, 2           # Syscall Number
                        mov rdi, r13         # File Path
                        mov rsi, 0           # Flags
                        mov rdx, 0           # Mode
                        syscall
                        mov r10, rax         # Save File FD

                        # Syscall Read from File
                        mov rax, 0           # Syscall Number
                        mov rdi, r10         # File FD
                        mov rsi, rsp         # Buffer
                        mov rdx, 2048        # Buffer Size
                        syscall
                        mov r15, rax         # Save File Size

                        # Close File FD
                        mov rax, 3           # Syscall Number
                        mov rdi, r10         # File FD
                        syscall

                        # Syscall write to client 200 OK
                        mov rax, 1              # Syscall Number
                        mov rdi, r9             # Client FD
                        lea rsi, http_ok        # Buffer
                        mov rdx, 19             # Buffer Size
                        syscall

                        # Syscall write to client file
                        mov rax, 1              # Syscall Number
                        mov rdi, r9             # Client FD
                        mov rsi, rsp            # Buffer
                        mov rdx, r15            # Buffer Size
                        syscall

                        # Close Client FD
                        mov rax, 3           # Syscall Number
                        mov rdi, r9          # File FD
                        syscall

                        # Exit
                        jmp exit
        post:
                # r14 : Request Size
                # r10 : FD of File
                # r11 : Buffer Address
                mov r13, rsp    # Save Buffer Address

                post_parse_request:
                        mov al, [r13]            # Get next byte
                        cmp al, ' '              # Compare to ' '
                        je post_process_pointer  # If equal, jump to post_found_path
                        add r13, 1               # Increment Buffer Address
                        jmp post_parse_request   # Loop
                post_process_pointer:
                        add r13, 1               # Increment Buffer Address
                        mov rax, r13             # Save Buffer Address
                        jmp post_found_path
                post_found_path:
                        mov cl, [rax]            # Get next byte
                        cmp cl, ' '              # Compare to ' '
                        je post_parse_content
                        add rax, 1               # Increment Buffer Address
                        jmp post_found_path
                post_parse_content:
                        mov r14, 0
                        mov r12, 0
                        mov r11, 0
                        mov rcx, 0
                        add rax, -1              # Decrement Buffer Address
                        mov byte [rax], cl       # Null Terminate String
                        lea r12, [rax+2]
                        jmp post_data_loop
                post_data_loop:
                        mov al, [r12]            # Get next byte
                        cmp al, 0x00            # Compare to 0x0D
                        je post_data_parse_loop
                        add r12, 1               # Increment Buffer Address
                        jmp post_data_loop       # Loop
                post_data_parse_loop:
                        mov al, [r12]            # Get next byte
                        cmp al, ':'             # Compare to 0x0D
                        je post_parse_length
                        sub r12, 1
                        jmp post_data_parse_loop
                post_parse_length:
                        add r12, 1
                        mov r11, 0
                        mov r11b, [r12]
                        cmp r11b, 0x0D
                        je post_parse_length2
                        add r14, 1
                        push r11
                        jmp post_parse_length
                post_parse_length2:
                        sub r14, 1
                        cmp r14, 2
                        je post_parse_length2digits
                        cmp r14, 3
                        je post_parse_length3digits
                        jmp post_process_request
                post_parse_length2digits:
                        # 999
                        mov rcx, 0
                        mov r14, 0
                        pop rcx
                        sub rcx, 48
                        pop r14
                        sub r14, 48
                        imul r14, 10
                        add r14, rcx
                        jmp post_process_request
                post_parse_length3digits:
                        mov rcx, 0
                        mov r14, 0
                        pop rcx
                        sub rcx, 48
                        pop r14
                        sub r14, 48
                        imul r14, 10
                        add r14, rcx
                        mov rcx, 0
                        pop rcx
                        sub rcx, 48
                        imul rcx, 100
                        add r14, rcx
                        jmp post_process_request
                post_process_request:
                        add r12, 3              # Increment Buffer Address to data


                        # Syscall Open File
                        push r14
                        mov rax, 2               # Syscall Number
                        mov rdi, r13             # File Path
                        mov rsi, 0x41            # Flags
                        mov rdx, 0x1FF           # Mode
                        syscall
                        mov r10, rax             # Save File FD

                        # Syscall write to file from buffer r11
                        pop r14
                        mov rax, 1              # Syscall Number
                        mov rdi, r10            # File FD
                        add r12, 1
                        mov rsi, r12            # Buffer
                        mov rdx, r14           # Buffer Size
                        syscall

                        # Close File FD
                        mov rax, 3           # Syscall Number
                        mov rdi, r10         # File FD
                        syscall

                        # Syscall write to client 200 OK
                        mov rax, 1              # Syscall Number
                        mov rdi, r9             # Client FD
                        lea rsi, http_ok        # Buffer
                        mov rdx, 19             # Buffer Size
                        syscall

                        # Exit
                        jmp exit
        exit:
                mov rax, 60             # Syscall Number
                mov rdi, 0              # Exit Code
                syscall
        test:
                #999
                # Syscall write to client 200 OK
                mov rax, 1              # Syscall Number
                mov rdi, r9             # Client FD
                lea rsi, http_okk        # Buffer
                mov rdx, 19             # Buffer Size
                syscall
                mov rax, 60             # Syscall Number
                mov rdi, 0              # Exit Code
                syscall
        testtwo:
                #888
                # Syscall write to client 200 OK
                mov rax, 1              # Syscall Number
                mov rdi, r9             # Client FD
                lea rsi, http_okf        # Buffer
                mov rdx, 19             # Buffer Size
                syscall
                mov rax, 60             # Syscall Number
                mov rdi, 0              # Exit Code
                syscall
.section .data
        sockaddr_in:
                # Socket Address Structure
                .short 2                # AF_INET
                .short 0x5000           # Port
                .long 0x00000000        # IP Address
                .zero 8                 # Padding
        http_ok:
                .ascii "HTTP/1.0 200 OK\r\n\r\n"
        http_okk:
                .ascii "HTTP/1.0 999 OK\r\n\r\n"
        http_okf:
                .ascii "HTTP/1.0 888 OK\r\n\r\n"



