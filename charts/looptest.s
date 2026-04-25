# Test A: loop + branches, no eval, no mul/div.
# Increments $15 twenty times, then stores.
# Expected: LEDs show 20 (LED[4]+LED[2]); VGA shows "20".

addi $15, $0, 0
addi $22, $0, 20
addi $9,  $0, 0

loop:
    bne $9, $22, body
    nop
    j done
    nop

body:
    addi $15, $15, 1
    nop
    nop
    nop
    addi $9, $9, 1
    nop
    nop
    nop
    j loop
    nop

done:
    nop
    nop
    nop
    sw $15, 4411($0)
halt:
    j halt
    nop
