; chainload-target.asm - synthetic 512-byte BIOS boot sector (TEST FIXTURE)
;
; Used only to prove the stage2 chainload handoff in the lab VM. It is a
; plain real-mode BIOS sector, not a kernel and not part of WRK.
;
; nasm -f bin -o chainload-target.bin -l chainload-target.lst chainload-target.asm

bits 16
org 0x7c00

        jmp     0x0000:start        ; normalize CS to 0

start:
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0x7c00
        cld
        sti

        mov     ax, 0x0003          ; clear screen: text mode 03h
        int     0x10

        mov     si, msg
        call    puts
.hang:
        cli
        hlt
        jmp     .hang

puts:
        lodsb
        or      al, al
        jz      .done
        mov     ah, 0x0e
        mov     bx, 0x0007
        int     0x10
        jmp     puts
.done:
        ret

msg:    db 'CHAINLOAD TEST OK - synthetic disk, not WRK', 13, 10, 0

        times 510-($-$$) db 0
        dw 0xAA55
