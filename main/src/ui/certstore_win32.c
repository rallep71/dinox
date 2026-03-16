/*
 * certstore_win32.c — Export Windows Root CA certificates to PEM file
 *
 * Reads the Windows "ROOT" certificate store via CertOpenSystemStore /
 * CertEnumCertificatesInStore, base64-encodes each DER certificate,
 * and writes a concatenated PEM file.
 *
 * This solves the problem where GnuTLS on MinGW does not have access
 * to the Windows system trust anchors, causing Let's Encrypt (and
 * other publicly-trusted) certificates to be rejected.
 */

#ifdef _WIN32

#include <windows.h>
#include <wincrypt.h>
#include <stdio.h>
#include <glib.h>
#include "certstore_win32.h"

gboolean
certstore_win32_export_pem(const gchar *output_path)
{
    HCERTSTORE hStore;
    PCCERT_CONTEXT pCert = NULL;
    FILE *fp = NULL;
    int count = 0;

    if (output_path == NULL)
        return FALSE;

    /* Ensure parent directory exists */
    gchar *dir = g_path_get_dirname(output_path);
    if (dir != NULL) {
        g_mkdir_with_parents(dir, 0700);
        g_free(dir);
    }

    hStore = CertOpenSystemStoreW(0, L"ROOT");
    if (hStore == NULL) {
        g_warning("certstore_win32: CertOpenSystemStore(ROOT) failed: %lu",
                  GetLastError());
        return FALSE;
    }

    fp = fopen(output_path, "wb");
    if (fp == NULL) {
        g_warning("certstore_win32: cannot create %s", output_path);
        CertCloseStore(hStore, 0);
        return FALSE;
    }

    while ((pCert = CertEnumCertificatesInStore(hStore, pCert)) != NULL) {
        DWORD b64_len = 0;

        /* First call: determine required buffer size */
        if (!CryptBinaryToStringA(pCert->pbCertEncoded,
                                   pCert->cbCertEncoded,
                                   CRYPT_STRING_BASE64HEADER,
                                   NULL, &b64_len)) {
            continue;
        }

        char *b64_buf = (char *)g_malloc(b64_len + 1);
        if (CryptBinaryToStringA(pCert->pbCertEncoded,
                                  pCert->cbCertEncoded,
                                  CRYPT_STRING_BASE64HEADER,
                                  b64_buf, &b64_len)) {
            fwrite(b64_buf, 1, b64_len, fp);
            count++;
        }
        g_free(b64_buf);
    }

    fclose(fp);
    CertCloseStore(hStore, 0);

    if (count > 0) {
        g_info("certstore_win32: exported %d root certificates to %s",
               count, output_path);
        return TRUE;
    } else {
        g_warning("certstore_win32: no certificates found in ROOT store");
        /* Remove empty file */
        g_unlink(output_path);
        return FALSE;
    }
}

#else

/* Linux stub — file is not compiled on Linux, but included for safety */
gboolean
certstore_win32_export_pem(const gchar *output_path) {
    (void)output_path;
    return FALSE;
}

#endif
