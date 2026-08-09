unsigned memory_roundtrip(volatile unsigned *address, unsigned value) {
    *address = value;
    return *address;
}
