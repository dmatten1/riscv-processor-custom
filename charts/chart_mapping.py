import pandas as pd
import numpy as np

df = pd.read_csv("full_template_chart.csv")


raise_size_map = {
    "NONE": 0,   # no raise
    "2.2": 1,
    "2.5": 2,
    "3": 3,
    "4": 4,
    "5": 5
}

pos_map = {
    "UTG": 0,
    "HJ": 1,
    "CO": 2,
    "BTN": 3,
    "SB": 4,
    "BB": 5
}

action_map = {
    "UNOPENED": 0,
    "ONE_RAISE": 1,
    "THREE_BET": 2
}

hands = sorted(df["hand_class"].unique())

hand_map = {hand: i for i, hand in enumerate(hands)}


def encode_row(row):
    if int(row["valid"]) == 0:
        return None

    pos = pos_map[row["position"]]
    villain = pos_map[row["villain_position"]]
    action = action_map[row["facing_action"]]
    hand = hand_map[row["hand_class"]]

    address = (pos << 13) | (villain << 10) | (action << 8) | hand

    fold = int(int(row["fold_freq"]) * 255 / 100)
    call = int(int(row["call_freq"]) * 255 / 100)
    raise_ = int(int(row["raise_freq"]) * 255 / 100)

    if raise_ == 0:
        raise_size = 0
    else:
        raise_size = raise_size_map[row["raise_size"]]

    data = (fold << 24) | (call << 16) | (raise_ << 8) | raise_size

    return address, data