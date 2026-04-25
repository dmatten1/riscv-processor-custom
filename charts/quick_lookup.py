# quick_lookup.py

from preflop_chart_gen import (
    build_empty_rom, apply_chart_rows, ChartRow,
    compute_index, pretty_print_word
)

rom = build_empty_rom()
rows = [
    ChartRow("20BB", "BTN", "UNOPENED_OR_LIMP", "AJo", "RAISE", 70, "FOLD", 30, size_code="2.2X"),
    ChartRow("20BB", "BB",  "ONE_RAISE",        "K9s", "CALL", 35, "RAISE", 10, "FOLD", 55, "3BET_SMALL"),
]
apply_chart_rows(rom, rows)

stack_mode = input("Stack mode (20BB/100BB): ").strip()
position = input("Position (UTG/HJ/CO/BTN/SB/BB): ").strip()
facing_action = input("Facing action (UNOPENED_OR_LIMP/ONE_RAISE/THREE_BET/BLINDS_ONLY): ").strip()
hand_class = input("Hand class (e.g. AJo, K9s, 77): ").strip()

idx = compute_index(stack_mode, position, facing_action, hand_class)
word = rom[idx]
print(f"ROM index: {idx}")
print(f"Raw word:  0x{word:08x}")
print(f"Decoded:   {pretty_print_word(word)}")