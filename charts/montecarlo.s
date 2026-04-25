########################################
# INITIALIZE VARIABLES & CARDS
########################################
addi $1, $0, 12   # Hole 1 (e.g., 5s)
addi $2, $0, 39   # Hole 2 (e.g., Jc)
addi $3, $0, 16   # Flop 1 (e.g., 6s)
addi $4, $0, 20   # Flop 2 (e.g., 7s)
addi $5, $0, 24   # Flop 3 (e.g., 8s)

# -1 = Flop Mode. Any other valid card (e.g., 37) = Turn Mode
addi $6, $0, -1   

########################################
# CONSTANTS & FLAGS
########################################
addi $23, $0, 52
addi $24, $0, -1

# Save original $6 to $21. This acts as our "Mode Flag"
addi $21, $6, 0   

########################################
# INIT LOOP & RESULTS
########################################
addi $22, $0, 0     # Global Counter (Total hands evaluated)

# Safely initialize your result registers
addi $10, $0, 0
addi $11, $0, 0
addi $12, $0, 0
addi $13, $0, 0
addi $14, $0, 0
addi $15, $0, 0
addi $16, $0, 0
addi $17, $0, 0
addi $18, $0, 0

addi $20, $0, 0     # Outer loop counter (Turn card iterator)

########################################
# OUTER LOOP (Only used in Flop Mode)
########################################
outer_loop_start:
    # MODE CHECK: If original $6 was NOT -1, skip to Inner Loop!
    bne $21, $24, inner_loop_init 
    nop

    # Exit outer loop if i == 52
    bne $20, $23, check_outer_r1
    nop
    j calc_probs
    nop

check_outer_r1:
    bne $20, $1, check_outer_r2
    nop
    j next_outer
    nop
check_outer_r2:
    bne $20, $2, check_outer_r3
    nop
    j next_outer
    nop
check_outer_r3:
    bne $20, $3, check_outer_r4
    nop
    j next_outer
    nop
check_outer_r4:
    bne $20, $4, check_outer_r5
    nop
    j next_outer
    nop
check_outer_r5:
    bne $20, $5, set_turn
    nop
    j next_outer
    nop

set_turn:
    # MAGIC HAPPENS HERE: Set $6 to the outer counter!
    addi $6, $20, 0
    nop

########################################
# INNER LOOP (Used by both modes!)
########################################
inner_loop_init:
    addi $19, $0, 0     # Inner loop counter (River card iterator)
    nop

inner_loop_start:
    # Exit inner loop if j == 52
    bne $19, $23, check_inner_r1
    nop
    j end_inner_loop
    nop

check_inner_r1:
    bne $19, $1, check_inner_r2
    nop
    j next_inner
    nop
check_inner_r2:
    bne $19, $2, check_inner_r3
    nop
    j next_inner
    nop
check_inner_r3:
    bne $19, $3, check_inner_r4
    nop
    j next_inner
    nop
check_inner_r4:
    bne $19, $4, check_inner_r5
    nop
    j next_inner
    nop
check_inner_r5:
    bne $19, $5, check_inner_r6
    nop
    j next_inner
    nop
check_inner_r6:
    bne $19, $6, use_card
    nop
    j next_inner
    nop

use_card:
    addi $7, $19, 0
    nop

    eval5 $zero
    eval7 $zero

    # Hazard Safety
    nop
    nop
    nop

    # Increment our global hand counter!
    addi $22, $22, 1
    nop

    # Array mapping logic
check_r10:
    addi $9, $0, 0
    nop
    nop
    bne $8, $9, check_r11
    nop
    addi $10, $10, 1
    j next_inner
    nop

check_r11:
    addi $9, $0, 1
    nop
    nop
    bne $8, $9, check_r12
    nop
    addi $11, $11, 1
    j next_inner
    nop

check_r12:
    addi $9, $0, 2
    nop
    nop
    bne $8, $9, check_r13
    nop
    addi $12, $12, 1
    j next_inner
    nop

check_r13:
    addi $9, $0, 3
    nop
    nop
    bne $8, $9, check_r14
    nop
    addi $13, $13, 1
    j next_inner
    nop

check_r14:
    addi $9, $0, 4
    nop
    nop
    bne $8, $9, check_r15
    nop
    addi $14, $14, 1
    j next_inner
    nop

check_r15:
    addi $9, $0, 5
    nop
    nop
    bne $8, $9, check_r16
    nop
    addi $15, $15, 1
    j next_inner
    nop

check_r16:
    addi $9, $0, 6
    nop
    nop
    bne $8, $9, check_r17
    nop
    addi $16, $16, 1
    j next_inner
    nop

check_r17:
    addi $9, $0, 7
    nop
    nop
    bne $8, $9, next_inner
    nop
    addi $17, $17, 1
    j next_inner
    nop

next_inner:
    addi $19, $19, 1
    nop
    nop
    nop
    j inner_loop_start
    nop

end_inner_loop:
    # MODE CHECK: If original $6 was NOT -1, we only needed one River loop. We're done!
    bne $21, $24, calc_probs
    nop

    # Otherwise, Flop mode continues to the next outer iteration.
    j next_outer
    nop

next_outer:
    addi $20, $20, 1
    nop
    nop
    nop
    j outer_loop_start
    nop
########################################
# PROBABILITY CALCULATION (WITH ROUNDING)
########################################
calc_probs:
    # Load 100 into a safe register
    addi $25, $0, 100
    nop
    
    # Hazard Safety: Prevent divide-by-zero using BNE
    bne $22, $0, safe_to_divide
    nop
    j done               # If $22 IS zero, fall through to here and exit
    nop

safe_to_divide:
    # Calculate (Total / 2) using Shift Right Logical
    # This takes 1 cycle and is perfectly safe
    sra $8, $22, 1       
    nop

    # --- Register 10 (High Card) ---
    mul $9, $10, $25     # Scratch = count * 100
    nop
    nop
    nop                  
    add $9, $9, $8       # Scratch = (count * 100) + (Total / 2)
    nop
    div $10, $9, $22     # Result = Scratch / Total
    nop
    nop
    nop                  

    # --- Register 11 (Pair) ---
    mul $9, $11, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $11, $9, $22
    nop
    nop
    nop                  

    # --- Register 12 (Two Pair) ---
    mul $9, $12, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $12, $9, $22
    nop
    nop
    nop                  

    # --- Register 13 (Trips) ---
    mul $9, $13, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $13, $9, $22
    nop
    nop
    nop                  

    # --- Register 14 (Straight) ---
    mul $9, $14, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $14, $9, $22
    nop
    nop
    nop                  

    # --- Register 15 (Flush) ---
    mul $9, $15, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $15, $9, $22
    nop
    nop
    nop                  

    # --- Register 16 (Full House) ---
    mul $9, $16, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $16, $9, $22
    nop
    nop
    nop                  

    # --- Register 17 (Quads) ---
    mul $9, $17, $25
    nop
    nop
    nop                  
    add $9, $9, $8
    nop
    div $17, $9, $22
    nop
    nop
    nop                           

########################################
# DONE
########################################
done:
    j done
    nop