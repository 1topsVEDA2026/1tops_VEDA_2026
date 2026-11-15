typedef unsigned long long uint64_t;

static uint64_t udivmod64(uint64_t num, uint64_t den, uint64_t *rem_p) {
    uint64_t quot = 0, qbit = 1;
    if (den == 0) return 0;
    while ((den << 1) > den && (den << 1) <= num) {
        den <<= 1;
        qbit <<= 1;
    }
    while (qbit) {
        if (num >= den) {
            num -= den;
            quot |= qbit;
        }
        den >>= 1;
        qbit >>= 1;
    }
    if (rem_p) *rem_p = num;
    return quot;
}

uint64_t __udivdi3(uint64_t a, uint64_t b) {
    return udivmod64(a, b, 0);
}

uint64_t __umoddi3(uint64_t a, uint64_t b) {
    uint64_t rem = 0;
    udivmod64(a, b, &rem);
    return rem;
}
