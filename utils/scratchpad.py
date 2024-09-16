if __name__ == "__main__":
    texts = [
        "Requis",
        "Garde",
        "Rang"
    ]
    t = ' '.join(texts)

    available = sorted({c for c in t})
    print(''.join(sorted(available)))
    print (len(available))
    mp_needed = [available.index(c) + 0xdd for c in "Requis"]
    # mp_needed[mp_needed.index(0xdd)]= 0xff

    garde_text = [available.index(c) + 0xdd for c in "Garde "]
    garde_text[garde_text.index(0xdd)]= 0xff

    passer_text = [available.index(c) + 0xdd for c in "Rang"]

    print(mp_needed)
    print(garde_text)
    print(passer_text)
