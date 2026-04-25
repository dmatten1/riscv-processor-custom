# Removed BLINDS_ONLY
# Model: (position, villain_position, facing_action, hand_class)

RANKS = "AKQJT98765432"

POSITION = {
    "UTG": 0,
    "HJ": 1,
    "CO": 2,
    "BTN": 3,
    "SB": 4,
    "BB": 5,
}

VILLAIN_POSITION = POSITION.copy()

FACING_ACTION = {
    "UNOPENED": 0,
    "ONE_RAISE": 1,
    "THREE_BET": 2,
}

RAISE_SIZE = {
    "NONE": 0,
    "2": 1,
    "2.2": 2,
    "2.5": 3,
    "3": 4,
    "4": 5,
    "5": 6,
    "JAM": 7,
}

NUM_POSITIONS = 6
NUM_ACTIONS = 3
NUM_HANDS = 169


# -------------------------
# Hand class generation
# -------------------------

def build_hand_classes():
    hands = []

    # pairs
    for r in RANKS:
        hands.append(r + r)

    # suited
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            hands.append(RANKS[i] + RANKS[j] + "s")

    # offsuit
    for i in range(len(RANKS)):
        for j in range(i + 1, len(RANKS)):
            hands.append(RANKS[i] + RANKS[j] + "o")

    return hands


HAND_CLASSES = build_hand_classes()
HAND_INDEX = {h: i for i, h in enumerate(HAND_CLASSES)}


# -------------------------
# Indexing
# -------------------------

def compute_index(position, villain_position, facing_action, hand_class):
    p = POSITION[position]
    v = VILLAIN_POSITION[villain_position]
    a = FACING_ACTION[facing_action]
    h = HAND_INDEX[hand_class]

    return (((p * NUM_POSITIONS) + v) * NUM_ACTIONS + a) * NUM_HANDS + h


# -------------------------
# Packing
# -------------------------

def pack_entry(fold, call, raise_f, size, valid):
    if valid == 1 and (fold + call + raise_f != 100):
        raise ValueError("Frequencies must sum to 100")

    if raise_f == 0 and size != "NONE":
        raise ValueError("Raise size must be NONE if raise_freq is 0")

    if raise_f > 0 and size == "NONE":
        raise ValueError("Raise size cannot be NONE if raise_freq > 0")

    word = 0
    word |= (fold & 0x7F)
    word |= (call & 0x7F) << 7
    word |= (raise_f & 0x7F) << 14
    word |= (RAISE_SIZE[size] & 0x7) << 21
    word |= (valid & 0x1) << 31

    return word


# -------------------------
# Unpacking (for debugging)
# -------------------------

def unpack_entry(word):
    fold = (word >> 0) & 0x7F
    call = (word >> 7) & 0x7F
    raise_f = (word >> 14) & 0x7F
    size_code = (word >> 21) & 0x7
    valid = (word >> 31) & 0x1

    size_lookup = {v: k for k, v in RAISE_SIZE.items()}
    size = size_lookup[size_code]

    return {
        "fold": fold,
        "call": call,
        "raise": raise_f,
        "size": size,
        "valid": valid,
    }