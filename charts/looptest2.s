# Same as looptest, but pads 8 extra nops after each register update
# so $9's writeback is fully retired well before any read.
# Expected LEDs: 20.
#   - If LEDs show 20 -> tight read-after-write hazard on $9 in looptest.
#   - If still 0 -> bug is elsewhere.

addi $15, $0, 0
addi $22, $0, 20
addi $9,  $0, 0

loop:
    bne $9, $22, body
    nop
    nop
    nop
    nop
    j done
    nop

body:
    addi $15, $15, 1
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    addi $9, $9, 1
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    j loop
    nop

done:
    nop
    nop
    nop
    nop
    sw $15, 4411($0)
halt:
    j halt
    nop
