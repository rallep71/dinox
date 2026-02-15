/*
 * Self-signed TLS certificate generator for DinoX Bot API
 * Uses GnuTLS library directly for cross-platform compatibility
 * (no dependency on openssl CLI - works in Flatpak, AppImage, Windows)
 */

#include <gnutls/gnutls.h>
#include <gnutls/x509.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/stat.h>
#include <fcntl.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#else
#include <unistd.h>
#endif
#include <errno.h>

#include "cert_gen.h"

/* Ensure directory exists (recursive) */
static int ensure_dir(const char* path) {
    char tmp[1024];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/' || tmp[len - 1] == '\\')
        tmp[len - 1] = 0;

    for (p = tmp + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            *p = 0;
#ifdef _WIN32
            _mkdir(tmp);
#else
            mkdir(tmp, 0700);
#endif
            *p = '/';
        }
    }
#ifdef _WIN32
    return _mkdir(tmp);
#else
    return mkdir(tmp, 0700);
#endif
}

static int ensure_parent_dir(const char* filepath) {
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s", filepath);

    /* Find last separator */
    char *last_sep = strrchr(dir, '/');
#ifdef _WIN32
    char *last_sep_win = strrchr(dir, '\\');
    if (last_sep_win > last_sep) last_sep = last_sep_win;
#endif

    if (last_sep) {
        *last_sep = 0;
        ensure_dir(dir);
    }
    return 0;
}

int dinox_generate_self_signed_cert(const char* cert_path, const char* key_path, const char* cn) {
    gnutls_x509_privkey_t privkey = NULL;
    gnutls_x509_crt_t cert = NULL;
    int ret = -1;
    FILE *f = NULL;

    gnutls_global_init();

    /* Ensure output directories exist */
    ensure_parent_dir(cert_path);
    ensure_parent_dir(key_path);

    /* Generate RSA 2048 private key */
    ret = gnutls_x509_privkey_init(&privkey);
    if (ret < 0) goto cleanup;

    ret = gnutls_x509_privkey_generate(privkey, GNUTLS_PK_RSA, 2048, 0);
    if (ret < 0) goto cleanup;

    /* Create X.509 certificate */
    ret = gnutls_x509_crt_init(&cert);
    if (ret < 0) goto cleanup;

    /* Version 3 (X.509v3) */
    ret = gnutls_x509_crt_set_version(cert, 3);
    if (ret < 0) goto cleanup;

    /* Set public key from generated private key */
    ret = gnutls_x509_crt_set_key(cert, privkey);
    if (ret < 0) goto cleanup;

    /* Set Distinguished Name: CN=<cn> */
    char dn[512];
    snprintf(dn, sizeof(dn), "CN=%s,O=DinoX", cn);
    ret = gnutls_x509_crt_set_dn(cert, dn, NULL);
    if (ret < 0) goto cleanup;

    /* Validity: now to 10 years from now */
    time_t now = time(NULL);
    gnutls_x509_crt_set_activation_time(cert, now);
    gnutls_x509_crt_set_expiration_time(cert, now + (time_t)(10 * 365 * 24 * 3600));

    /* Serial number based on current time */
    unsigned char serial[8];
    uint64_t serial_val = (uint64_t)now;
    for (int i = 7; i >= 0; i--) {
        serial[i] = (unsigned char)(serial_val & 0xFF);
        serial_val >>= 8;
    }
    gnutls_x509_crt_set_serial(cert, serial, sizeof(serial));

    /* Self-sign with SHA-256 */
    ret = gnutls_x509_crt_sign2(cert, cert, privkey, GNUTLS_DIG_SHA256, 0);
    if (ret < 0) goto cleanup;

    /* Export certificate to PEM */
    char cert_buf[8192];
    size_t cert_size = sizeof(cert_buf);
    ret = gnutls_x509_crt_export(cert, GNUTLS_X509_FMT_PEM, cert_buf, &cert_size);
    if (ret < 0) goto cleanup;

    /* Export private key to PEM */
    char key_buf[8192];
    size_t key_size = sizeof(key_buf);
    ret = gnutls_x509_privkey_export(privkey, GNUTLS_X509_FMT_PEM, key_buf, &key_size);
    if (ret < 0) goto cleanup;

    /* Write certificate file */
    f = fopen(cert_path, "w");
    if (!f) { ret = -1; goto cleanup; }
    fwrite(cert_buf, 1, cert_size, f);
    fclose(f);
    f = NULL;

    /* Set restrictive permissions on key file */
#ifndef _WIN32
    /* Create with 0600 permissions (owner read/write only) */
    int fd = open(key_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) { ret = -1; goto cleanup; }
    f = fdopen(fd, "w");
#else
    f = fopen(key_path, "w");
#endif
    if (!f) { ret = -1; goto cleanup; }
    fwrite(key_buf, 1, key_size, f);
    fclose(f);
    f = NULL;

    ret = 0;

cleanup:
    if (f) fclose(f);
    if (cert) gnutls_x509_crt_deinit(cert);
    if (privkey) gnutls_x509_privkey_deinit(privkey);
    return ret;
}

int dinox_check_cert_valid(const char* cert_path) {
    FILE *f = fopen(cert_path, "r");
    if (!f) return 0;

    char buf[8192];
    size_t len = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[len] = 0;

    gnutls_x509_crt_t cert;
    if (gnutls_x509_crt_init(&cert) < 0) return 0;

    gnutls_datum_t data;
    data.data = (unsigned char*)buf;
    data.size = (unsigned int)len;

    int ret = gnutls_x509_crt_import(cert, &data, GNUTLS_X509_FMT_PEM);
    if (ret < 0) {
        gnutls_x509_crt_deinit(cert);
        return 0;
    }

    time_t exp = gnutls_x509_crt_get_expiration_time(cert);
    time_t act = gnutls_x509_crt_get_activation_time(cert);
    gnutls_x509_crt_deinit(cert);

    time_t now = time(NULL);
    if (now < act || now > exp) return 0;

    return 1;
}

int dinox_delete_cert(const char* cert_path, const char* key_path) {
    if (cert_path) remove(cert_path);
    if (key_path) remove(key_path);
    return 0;
}
