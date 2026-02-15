/*
 * Self-signed TLS certificate generator for DinoX Bot API
 * Uses GnuTLS library - works on Linux, Windows, Flatpak, AppImage
 */

#ifndef DINOX_CERT_GEN_H
#define DINOX_CERT_GEN_H

/**
 * Generate a self-signed TLS certificate and private key.
 * @param cert_path Path to write the PEM certificate file
 * @param key_path Path to write the PEM private key file
 * @param cn Common Name for the certificate (e.g. "DinoX API")
 * @return 0 on success, negative GnuTLS error code on failure
 */
int dinox_generate_self_signed_cert(const char* cert_path, const char* key_path, const char* cn);

/**
 * Check if a certificate file exists and is not expired.
 * @param cert_path Path to the PEM certificate file
 * @return 1 if valid, 0 if expired/missing/invalid
 */
int dinox_check_cert_valid(const char* cert_path);

/**
 * Delete certificate and key files.
 * @param cert_path Path to the certificate file
 * @param key_path Path to the key file
 * @return 0 on success
 */
int dinox_delete_cert(const char* cert_path, const char* key_path);

#endif /* DINOX_CERT_GEN_H */
