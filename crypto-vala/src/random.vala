namespace Crypto {
public static void randomize(uint8[] buffer) {
    // gcrypt must be initialized (via gcry_check_version) before calling
    // Random.randomize. The OMEMO plugin does this in setup_signal_vala_crypto_provider().
    GCrypt.Random.randomize(buffer);
}
}
