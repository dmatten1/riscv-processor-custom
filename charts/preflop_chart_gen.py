# preflop_chart_gen.py

from dataclasses import dataclass
from typing import Dict, List

RANKS = "AKQJT98765432"
SUITS = "shdc"

STACK_MODE = {
    "20BB": 0,
    "100BB": 1,
}

POSITION = {
    "UTG": 0,
    "HJ": 1,
    "CO": 2,
    "BTN": 3,
    "SB": 4,
    "BB": 5,
}

FACING_ACTION = {
    "UNOPENED_OR_LIMP": 0,
    "ONE_RAISE": 1,
    "THREE_BET": 2,
    "BLINDS_ONLY": 3,
}

ACTION = {
    "FOLD": 0,
    "CALL": 1,
    "RAISE": 2,
    "ALLIN": 3,
}

SIZE_CODE = {
    "NONE": 0,
    "2.0X": 1,
    "2.2X": 2,
    "2.5X": 3,
    "3.0X": 4,
    "3BET_SMALL": 5,
    "3BET_LARGE": 6,
    "JAM": 7,
}

NUM_STACKS = 2
NUM_POSITIONS = 6
NUM_ACTIONS = 4
NUM_HANDS = 169
ROM_DEPTH = NUM_STACKS * NUM_POSITIONS * NUM_ACTIONS * NUM_HANDS  # 8112


def build_hand_class_order() -> List[str]:
    order = []

    # Pairs: AA down to 22
    for r in RANKS:
        order.append(r + r)

    # Suited non-pairs: AKs, AQs, ..., 32s
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            high = RANKS[i]
            low = RANKS[j]
            order.append(high + low + "s")

    # Offsuit non-pairs: AKo, AQo, ..., 32o
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            high = RANKS[i]
            low = RANKS[j]
            order.append(high + low + "o")

    assert len(order) == 169
    return order


HAND_CLASS_ORDER = build_hand_class_order()
HAND_CLASS_TO_INDEX: Dict[str, int] = {
    hand_class: idx for idx, hand_class in enumerate(HAND_CLASS_ORDER)
}


def validate_card(card: str) -> None:
    if len(card) != 2:
        raise ValueError(f"Invalid card '{card}': must be 2 characters like 'Ah'")
    rank, suit = card[0], card[1]
    if rank not in RANKS:
        raise ValueError(f"Invalid rank '{rank}' in '{card}'")
    if suit not in SUITS:
        raise ValueError(f"Invalid suit '{suit}' in '{card}'")


def cards_to_hand_class(card1: str, card2: str) -> str:
    validate_card(card1)
    validate_card(card2)

    r1, s1 = card1[0], card1[1]
    r2, s2 = card2[0], card2[1]

    if card1 == card2:
        raise ValueError("Duplicate exact same card given")

    i1 = RANKS.index(r1)
    i2 = RANKS.index(r2)

    # Pair
    if r1 == r2:
        return r1 + r2

    # Ensure higher rank first
    if i1 < i2:
        high_rank, low_rank = r1, r2
    else:
        high_rank, low_rank = r2, r1

    suited_flag = "s" if s1 == s2 else "o"
    return high_rank + low_rank + suited_flag


def hand_class_to_index(hand_class: str) -> int:
    if hand_class not in HAND_CLASS_TO_INDEX:
        raise ValueError(f"Unknown hand class '{hand_class}'")
    return HAND_CLASS_TO_INDEX[hand_class]


def compute_index(stack_mode: str, position: str, facing_action: str, hand_class: str) -> int:
    s = STACK_MODE[stack_mode]
    p = POSITION[position]
    a = FACING_ACTION[facing_action]
    h = hand_class_to_index(hand_class)
    idx = (((s * NUM_POSITIONS) + p) * NUM_ACTIONS + a) * NUM_HANDS + h
    assert 0 <= idx < ROM_DEPTH
    return idx


def pack_entry(
    action_a: str,
    freq_a: int,
    action_b: str,
    freq_b: int,
    action_c: str = "FOLD",
    freq_c: int = 0,
    size_code: str = "NONE",
    valid: int = 1,
) -> int:
    if not (0 <= freq_a <= 100 and 0 <= freq_b <= 100 and 0 <= freq_c <= 100):
        raise ValueError("Frequencies must be between 0 and 100")
    if valid not in (0, 1):
        raise ValueError("Valid must be 0 or 1")

    aa = ACTION[action_a]
    ab = ACTION[action_b]
    ac = ACTION[action_c]
    sc = SIZE_CODE[size_code]

    word = 0
    word |= (aa & 0x3)
    word |= (ab & 0x3) << 2
    word |= (ac & 0x3) << 4
    word |= (freq_a & 0x7F) << 6
    word |= (freq_b & 0x7F) << 13
    word |= (freq_c & 0x7F) << 20
    word |= (sc & 0xF) << 27
    word |= (valid & 0x1) << 31
    return word


def unpack_entry(word: int) -> Dict[str, int]:
    return {
        "action_a": (word >> 0) & 0x3,
        "action_b": (word >> 2) & 0x3,
        "action_c": (word >> 4) & 0x3,
        "freq_a": (word >> 6) & 0x7F,
        "freq_b": (word >> 13) & 0x7F,
        "freq_c": (word >> 20) & 0x7F,
        "size_code": (word >> 27) & 0xF,
        "valid": (word >> 31) & 0x1,
    }


ACTION_INV = {v: k for k, v in ACTION.items()}
SIZE_CODE_INV = {v: k for k, v in SIZE_CODE.items()}


def pretty_print_word(word: int) -> str:
    d = unpack_entry(word)
    if d["valid"] == 0:
        return "INVALID"

    return (
        f"{ACTION_INV[d['action_a']]} {d['freq_a']}%, "
        f"{ACTION_INV[d['action_b']]} {d['freq_b']}%, "
        f"{ACTION_INV[d['action_c']]} {d['freq_c']}%, "
        f"size={SIZE_CODE_INV[d['size_code']]}"
    )


@dataclass
class ChartRow:
    stack_mode: str
    position: str
    facing_action: str
    hand_class: str
    action_a: str
    freq_a: int
    action_b: str
    freq_b: int
    action_c: str = "FOLD"
    freq_c: int = 0
    size_code: str = "NONE"
    valid: int = 1


def build_empty_rom() -> List[int]:
    return [0] * ROM_DEPTH


def apply_chart_rows(rom: List[int], rows: List[ChartRow]) -> None:
    for row in rows:
        idx = compute_index(
            row.stack_mode,
            row.position,
            row.facing_action,
            row.hand_class,
        )
        rom[idx] = pack_entry(
            action_a=row.action_a,
            freq_a=row.freq_a,
            action_b=row.action_b,
            freq_b=row.freq_b,
            action_c=row.action_c,
            freq_c=row.freq_c,
            size_code=row.size_code,
            valid=row.valid,
        )


def write_hex_file(filename: str, rom: List[int]) -> None:
    with open(filename, "w") as f:
        for word in rom:
            f.write(f"{word:08x}\n")


def demo() -> None:
    print("=== Hand-class tests ===")
    test_cards = [
        ("Ah", "Jd"),
        ("As", "Ks"),
        ("7c", "7d"),
        ("2h", "3h"),
        ("Kd", "Ac"),
    ]

    for c1, c2 in test_cards:
        hc = cards_to_hand_class(c1, c2)
        hi = hand_class_to_index(hc)
        print(f"{c1} {c2} -> {hc} -> hand_index {hi}")

    print("\n=== Index test ===")
    hc = cards_to_hand_class("Ah", "Jd")   # AJo
    idx = compute_index("20BB", "BTN", "UNOPENED_OR_LIMP", hc)
    print(f"(20BB, BTN, UNOPENED_OR_LIMP, {hc}) -> ROM index {idx}")

    print("\n=== Build sample ROM ===")
    rom = build_empty_rom()

    sample_rows = [
        ChartRow("20BB", "BTN", "UNOPENED_OR_LIMP", "AJo", "RAISE", 70, "FOLD", 30, size_code="2.2X"),
        ChartRow("20BB", "BB",  "ONE_RAISE",        "K9s", "CALL", 35, "RAISE", 10, "FOLD", 55, "3BET_SMALL"),
        ChartRow("100BB", "CO", "UNOPENED_OR_LIMP", "77",  "RAISE", 100, "FOLD", 0, size_code="2.5X"),
        ChartRow("100BB", "SB", "BLINDS_ONLY",      "Q8o", "RAISE", 40, "CALL", 20, "FOLD", 40, "2.5X"),
    ]

    apply_chart_rows(rom, sample_rows)
    write_hex_file("preflop_chart.hex", rom)

    for row in sample_rows:
        idx = compute_index(row.stack_mode, row.position, row.facing_action, row.hand_class)
        print(f"index {idx:4d}: {row.stack_mode:5s} {row.position:3s} {row.facing_action:17s} {row.hand_class:3s} -> {pretty_print_word(rom[idx])}")

    print("\nWrote preflop_chart.hex")


if __name__ == "__main__":
    demo()