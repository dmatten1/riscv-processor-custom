#!/usr/bin/env python3
import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

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
    "UNOPENED": 0,
    "ONE_RAISE": 1,
    "THREE_BET": 2,
    "BLINDS_ONLY": 3,
}

# One total raise frequency per row. If a raise happens, it always uses this size.
SIZE_CODE = {
    "NONE": 0,
    "2X": 1,
    "2.2X": 2,
    "2.5X": 3,
    "3X": 4,
    "4X": 5,
    "5X": 6,
    "JAM": 7,
}

SIZE_CODE_INV = {v: k for k, v in SIZE_CODE.items()}
SIZE_ALIASES = {
    "2": "2X",
    "2.0": "2X",
    "2.0X": "2X",
    "2X": "2X",
    "2.2": "2.2X",
    "2.2X": "2.2X",
    "2.5": "2.5X",
    "2.5X": "2.5X",
    "3": "3X",
    "3.0": "3X",
    "3.0X": "3X",
    "3X": "3X",
    "4": "4X",
    "4.0": "4X",
    "4.0X": "4X",
    "4X": "4X",
    "5": "5X",
    "5.0": "5X",
    "5.0X": "5X",
    "5X": "5X",
    "JAM": "JAM",
    "NONE": "NONE",
}

NUM_STACKS = 2
NUM_POSITIONS = 6
NUM_ACTIONS = 4
NUM_HANDS = 169
ROM_DEPTH = NUM_STACKS * NUM_POSITIONS * NUM_ACTIONS * NUM_HANDS


@dataclass
class ChartRow:
    stack_mode: str
    position: str
    facing_action: str
    hand_class: str
    fold_freq: int
    call_freq: int
    raise_freq: int
    raise_size: str
    valid: int


def build_hand_class_order() -> List[str]:
    order: List[str] = []
    for r in RANKS:
        order.append(r + r)
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            order.append(RANKS[i] + RANKS[j] + "s")
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            order.append(RANKS[i] + RANKS[j] + "o")
    if len(order) != 169:
        raise RuntimeError("Hand class order must contain 169 entries")
    return order


HAND_CLASS_ORDER = build_hand_class_order()
HAND_CLASS_TO_INDEX: Dict[str, int] = {
    hand_class: idx for idx, hand_class in enumerate(HAND_CLASS_ORDER)
}


def normalize_token(value: str) -> str:
    return value.strip().upper()


def normalize_size(value: str) -> str:
    key = normalize_token(value)
    if key not in SIZE_ALIASES:
        raise ValueError(
            f"Unknown raise size '{value}'. Use one of: 2, 2.2, 2.5, 3, 4, 5, JAM, NONE"
        )
    return SIZE_ALIASES[key]


def validate_card(card: str) -> None:
    if len(card) != 2:
        raise ValueError(f"Invalid card '{card}'. Use format like Ah or Td.")
    rank, suit = card[0].upper(), card[1].lower()
    if rank not in RANKS:
        raise ValueError(f"Invalid rank '{rank}' in '{card}'.")
    if suit not in SUITS:
        raise ValueError(f"Invalid suit '{suit}' in '{card}'.")


def normalize_card(card: str) -> str:
    validate_card(card)
    return card[0].upper() + card[1].lower()


def cards_to_hand_class(card1: str, card2: str) -> str:
    c1 = normalize_card(card1)
    c2 = normalize_card(card2)
    if c1 == c2:
        raise ValueError("The two cards are identical.")

    r1, s1 = c1[0], c1[1]
    r2, s2 = c2[0], c2[1]

    if r1 == r2:
        return r1 + r2

    i1 = RANKS.index(r1)
    i2 = RANKS.index(r2)
    if i1 < i2:
        high_rank, low_rank = r1, r2
    else:
        high_rank, low_rank = r2, r1

    suited_flag = "s" if s1 == s2 else "o"
    return high_rank + low_rank + suited_flag


def hand_class_to_index(hand_class: str) -> int:
    normalized = hand_class.strip()
    if normalized not in HAND_CLASS_TO_INDEX:
        raise ValueError(f"Unknown hand class '{hand_class}'.")
    return HAND_CLASS_TO_INDEX[normalized]


def compute_index(stack_mode: str, position: str, facing_action: str, hand_class: str) -> int:
    s = STACK_MODE[normalize_token(stack_mode)]
    p = POSITION[normalize_token(position)]
    a = FACING_ACTION[normalize_token(facing_action)]
    h = hand_class_to_index(hand_class)
    idx = (((s * NUM_POSITIONS) + p) * NUM_ACTIONS + a) * NUM_HANDS + h
    if not (0 <= idx < ROM_DEPTH):
        raise ValueError("Computed ROM index out of range.")
    return idx


def validate_freqs(fold_freq: int, call_freq: int, raise_freq: int, valid: int, raise_size: str) -> None:
    for freq in (fold_freq, call_freq, raise_freq):
        if not (0 <= freq <= 100):
            raise ValueError("Frequencies must be between 0 and 100.")
    if valid not in (0, 1):
        raise ValueError("valid must be 0 or 1.")
    total = fold_freq + call_freq + raise_freq
    if valid == 1 and total != 100:
        raise ValueError(f"Valid row frequencies must sum to 100, got {total}.")
    if raise_freq == 0 and raise_size != "NONE":
        raise ValueError("raise_size must be NONE when raise_freq is 0.")
    if raise_freq > 0 and raise_size == "NONE":
        raise ValueError("raise_size cannot be NONE when raise_freq is greater than 0.")


# 32-bit packed word
# bits [6:0]   fold_freq
# bits [13:7]  call_freq
# bits [20:14] raise_freq
# bits [23:21] raise_size
# bits [30:24] reserved
# bit  [31]    valid

def pack_entry(
    fold_freq: int,
    call_freq: int,
    raise_freq: int,
    raise_size: str,
    valid: int,
) -> int:
    size_name = normalize_size(raise_size)
    validate_freqs(fold_freq, call_freq, raise_freq, valid, size_name)
    sc = SIZE_CODE[size_name]

    word = 0
    word |= (fold_freq & 0x7F)
    word |= (call_freq & 0x7F) << 7
    word |= (raise_freq & 0x7F) << 14
    word |= (sc & 0x7) << 21
    word |= (valid & 0x1) << 31
    return word


def unpack_entry(word: int) -> Dict[str, int]:
    return {
        "fold_freq": (word >> 0) & 0x7F,
        "call_freq": (word >> 7) & 0x7F,
        "raise_freq": (word >> 14) & 0x7F,
        "size_code": (word >> 21) & 0x7,
        "valid": (word >> 31) & 0x1,
    }


def pretty_print_word(word: int) -> str:
    decoded = unpack_entry(word)
    if decoded["valid"] == 0:
        return "UNSUPPORTED"

    parts = []
    if decoded["fold_freq"] > 0:
        parts.append(f"FOLD {decoded['fold_freq']}%")
    if decoded["call_freq"] > 0:
        parts.append(f"CALL {decoded['call_freq']}%")
    if decoded["raise_freq"] > 0:
        raise_part = f"RAISE {decoded['raise_freq']}%"
        size_name = SIZE_CODE_INV[decoded["size_code"]]
        if size_name != "NONE":
            raise_part += f" ({size_name})"
        parts.append(raise_part)
    return ", ".join(parts) if parts else "UNSUPPORTED"


def build_empty_rom() -> List[int]:
    return [0] * ROM_DEPTH


def parse_csv_row(raw: Dict[str, str], row_number: int) -> ChartRow:
    try:
        return ChartRow(
            stack_mode=normalize_token(raw["stack_mode"]),
            position=normalize_token(raw["position"]),
            facing_action=normalize_token(raw["facing_action"]),
            hand_class=raw["hand_class"].strip(),
            fold_freq=int(raw["fold_freq"]),
            call_freq=int(raw["call_freq"]),
            raise_freq=int(raw["raise_freq"]),
            raise_size=normalize_size(raw["raise_size"]),
            valid=int(raw["valid"]),
        )
    except KeyError as exc:
        raise ValueError(f"CSV row {row_number}: missing column {exc}") from exc
    except Exception as exc:
        raise ValueError(f"CSV row {row_number}: {exc}") from exc


def load_chart_rows(csv_path: Path) -> List[ChartRow]:
    rows: List[ChartRow] = []
    with csv_path.open("r", newline="") as f:
        reader = csv.DictReader(f)
        for row_number, raw in enumerate(reader, start=2):
            row = parse_csv_row(raw, row_number)
            if row.stack_mode not in STACK_MODE:
                raise ValueError(f"CSV row {row_number}: invalid stack_mode '{row.stack_mode}'")
            if row.position not in POSITION:
                raise ValueError(f"CSV row {row_number}: invalid position '{row.position}'")
            if row.facing_action not in FACING_ACTION:
                raise ValueError(f"CSV row {row_number}: invalid facing_action '{row.facing_action}'")
            hand_class_to_index(row.hand_class)
            validate_freqs(row.fold_freq, row.call_freq, row.raise_freq, row.valid, row.raise_size)
            rows.append(row)
    return rows


def build_rom_from_rows(rows: List[ChartRow]) -> List[int]:
    rom = build_empty_rom()
    seen_indices = set()
    for row in rows:
        idx = compute_index(row.stack_mode, row.position, row.facing_action, row.hand_class)
        if idx in seen_indices:
            raise ValueError(
                f"Duplicate chart entry for {row.stack_mode}/{row.position}/{row.facing_action}/{row.hand_class}"
            )
        seen_indices.add(idx)
        rom[idx] = pack_entry(
            fold_freq=row.fold_freq,
            call_freq=row.call_freq,
            raise_freq=row.raise_freq,
            raise_size=row.raise_size,
            valid=row.valid,
        )
    return rom


def write_hex_file(filename: Path, rom: List[int]) -> None:
    with filename.open("w") as f:
        for word in rom:
            f.write(f"{word:08x}\n")


def lookup_word(rom: List[int], stack_mode: str, position: str, facing_action: str, hand_class: str) -> int:
    idx = compute_index(stack_mode, position, facing_action, hand_class)
    return rom[idx]


def print_lookup_result(stack_mode: str, position: str, facing_action: str, hand_class: str, word: int) -> None:
    idx = compute_index(stack_mode, position, facing_action, hand_class)
    print(f"ROM index : {idx}")
    print(f"Raw word  : 0x{word:08x}")
    print(f"Spot      : {normalize_token(stack_mode)} / {normalize_token(position)} / {normalize_token(facing_action)} / {hand_class}")
    print(f"Strategy  : {pretty_print_word(word)}")


def cmd_build(args: argparse.Namespace) -> int:
    rows = load_chart_rows(Path(args.csv))
    rom = build_rom_from_rows(rows)
    write_hex_file(Path(args.output), rom)
    print(f"Loaded {len(rows)} chart rows from {args.csv}")
    print(f"Wrote {len(rom)} ROM words to {args.output}")
    return 0


def resolve_hand_class(args: argparse.Namespace) -> str:
    if args.hand_class:
        return args.hand_class.strip()
    if args.card1 and args.card2:
        return cards_to_hand_class(args.card1, args.card2)
    raise ValueError("Provide either --hand-class or both --card1 and --card2.")


def cmd_lookup(args: argparse.Namespace) -> int:
    rows = load_chart_rows(Path(args.csv))
    rom = build_rom_from_rows(rows)
    hand_class = resolve_hand_class(args)
    word = lookup_word(rom, args.stack_mode, args.position, args.facing_action, hand_class)
    print_lookup_result(args.stack_mode, args.position, args.facing_action, hand_class, word)
    return 0


def cmd_interactive(args: argparse.Namespace) -> int:
    rows = load_chart_rows(Path(args.csv))
    rom = build_rom_from_rows(rows)
    print("Interactive preflop chart lookup. Type 'q' to quit.")
    while True:
        try:
            stack_mode = input("Stack mode (20BB/100BB): ").strip()
            if stack_mode.lower() == "q":
                break
            position = input("Position (UTG/HJ/CO/BTN/SB/BB): ").strip()
            if position.lower() == "q":
                break
            facing_action = input("Facing action (UNOPENED/ONE_RAISE/THREE_BET/BLINDS_ONLY): ").strip()
            if facing_action.lower() == "q":
                break
            mode = input("Enter hand by class or cards? (class/cards): ").strip().lower()
            if mode == "q":
                break
            if mode == "class":
                hand_class = input("Hand class (e.g. AJo, K9s, 77): ").strip()
            elif mode == "cards":
                card1 = input("Card 1 (e.g. Ah): ").strip()
                card2 = input("Card 2 (e.g. Jd): ").strip()
                hand_class = cards_to_hand_class(card1, card2)
                print(f"Derived hand class: {hand_class}")
            else:
                print("Choose 'class' or 'cards'.")
                continue
            word = lookup_word(rom, stack_mode, position, facing_action, hand_class)
            print_lookup_result(stack_mode, position, facing_action, hand_class, word)
            print()
        except KeyboardInterrupt:
            print()
            break
        except Exception as exc:
            print(f"Error: {exc}")
            print()
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="CSV-driven preflop chart builder and tester")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_build = subparsers.add_parser("build", help="Build ROM hex file from CSV")
    p_build.add_argument("--csv", required=True, help="Input chart CSV")
    p_build.add_argument("--output", required=True, help="Output hex file")
    p_build.set_defaults(func=cmd_build)

    p_lookup = subparsers.add_parser("lookup", help="Lookup one chart entry")
    p_lookup.add_argument("--csv", required=True, help="Input chart CSV")
    p_lookup.add_argument("--stack-mode", required=True, choices=["20BB", "100BB"])
    p_lookup.add_argument("--position", required=True, choices=["UTG", "HJ", "CO", "BTN", "SB", "BB"])
    p_lookup.add_argument(
        "--facing-action",
        required=True,
        choices=["UNOPENED", "ONE_RAISE", "THREE_BET", "BLINDS_ONLY"],
    )
    p_lookup.add_argument("--hand-class", help="Hand class such as AJo, K9s, 77")
    p_lookup.add_argument("--card1", help="First card like Ah")
    p_lookup.add_argument("--card2", help="Second card like Jd")
    p_lookup.set_defaults(func=cmd_lookup)

    p_interactive = subparsers.add_parser("interactive", help="Interactive lookup mode")
    p_interactive.add_argument("--csv", required=True, help="Input chart CSV")
    p_interactive.set_defaults(func=cmd_interactive)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
