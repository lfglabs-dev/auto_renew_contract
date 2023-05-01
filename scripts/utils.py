import random

basicAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789-"
bigAlphabet = "这来"

def extract_stars(str):
    k = 0
    while str.endswith(bigAlphabet[-1]):
        str = str[:-1]
        k += 1
    return (str, k)

def decode(felt):
    decoded = ""
    while felt != 0:
        code = felt % (len(basicAlphabet) + 1)
        felt = felt // (len(basicAlphabet) + 1)
        if code == len(basicAlphabet):
            next_felt = felt // (len(bigAlphabet) + 1)
            if next_felt == 0:
                code2 = felt % (len(bigAlphabet) + 1)
                felt = next_felt
                decoded += basicAlphabet[0] if code2 == 0 else bigAlphabet[code2 - 1]
            else:
                decoded += bigAlphabet[felt % len(bigAlphabet)]
                felt = felt // len(bigAlphabet)
        else:
            decoded += basicAlphabet[code]

    decoded, k = extract_stars(decoded)
    if k:
        decoded += (
            ((bigAlphabet[-1] * (k // 2 - 1)) + bigAlphabet[0] + basicAlphabet[1])
            if k % 2 == 0
            else bigAlphabet[-1] * (k // 2 + 1)
        )

    return decoded


def encode(str):

    mul = 1
    output = 0

    if str.endswith(bigAlphabet[0] + basicAlphabet[1]):
        
        str, k = extract_stars(str[:-2])
        str += bigAlphabet[-1] * (2 * (k + 1))
    else:
        str, k = extract_stars(str)
        if k:
            str += bigAlphabet[-1] * (1 + 2 * (k - 1))

    str_size = len(str)

    for i in range(str_size):
        c = str[i]

        # if c is a 'a' at the end of the word
        if i == str_size - 1 and c == basicAlphabet[0]:
            output += len(basicAlphabet) * mul

        elif c in basicAlphabet:
            output += mul * basicAlphabet.index(c)
            mul *= len(basicAlphabet) + 1

        elif c in bigAlphabet:
            # adding escape char
            output += len(basicAlphabet) * mul
            mul *= len(basicAlphabet) + 1

            # adding char from big alphabet

            # otherwise (includes last char)
            output += mul * (bigAlphabet.index(c) + int(i == str_size - 1))
            mul *= len(bigAlphabet)

        else:
            raise RuntimeError("input string contains unsupported characters")

    return output