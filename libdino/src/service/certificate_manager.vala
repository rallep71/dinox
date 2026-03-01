/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino {

/**
 * Manages TLS certificate pinning for self-signed or untrusted certificates.
 * Implements Trust on First Use (TOFU) pattern similar to SSH known_hosts.
 */
public class CertificateManager : Object {

    private Database db;
    private StreamInteractor stream_interactor;

    /**
     * Signal emitted when an invalid certificate is encountered and requires user action.
     * The UI should present a dialog to the user to accept/reject the certificate.
     */
    public signal void certificate_validation_required(
        Account account,
        CertificateInfo cert_info,
        owned CertificateValidationCallback callback
    );

    public delegate void CertificateValidationCallback(bool accepted);

    public CertificateManager(Database db, StreamInteractor stream_interactor) {
        this.db = db;
        this.stream_interactor = stream_interactor;
    }

    /**
     * Check if a certificate is pinned for the given domain.
     */
    public bool is_certificate_pinned(string domain) {
        return db.pinned_certificate.get_pinned_fingerprint(domain) != null;
    }

    /**
     * Check if the certificate matches the pinned one for the domain.
     */
    public bool is_certificate_trusted(string domain, TlsCertificate cert) {
        string? pinned_fp = db.pinned_certificate.get_pinned_fingerprint(domain);
        if (pinned_fp == null) return false;
        
        string cert_fp = get_certificate_fingerprint(cert);
        return pinned_fp == cert_fp;
    }

    /**
     * Pin a certificate for the given domain (static DB operation, clone removal).
     */
    public static void pin_to_db(Database db, string domain, TlsCertificate cert, TlsCertificateFlags flags) {
        string fingerprint = get_certificate_fingerprint(cert);
        string? issuer = get_certificate_issuer(cert);
        DateTime? not_before = get_certificate_not_before(cert);
        DateTime? not_after = get_certificate_not_after(cert);

        db.pinned_certificate.upsert()
            .value(db.pinned_certificate.domain, domain, true)
            .value(db.pinned_certificate.fingerprint_sha256, fingerprint)
            .value(db.pinned_certificate.issuer, issuer)
            .value(db.pinned_certificate.not_valid_before, not_before != null ? (long) not_before.to_unix() : -1)
            .value(db.pinned_certificate.not_valid_after, not_after != null ? (long) not_after.to_unix() : -1)
            .value(db.pinned_certificate.pinned_at, (long) new DateTime.now_utc().to_unix())
            .value(db.pinned_certificate.tls_flags, (int) flags)
            .perform();

        debug("Certificate pinned for domain %s with fingerprint %s", domain, fingerprint);
    }

    /**
     * Pin a certificate for the given domain.
     */
    public void pin_certificate(string domain, TlsCertificate cert, TlsCertificateFlags flags) {
        pin_to_db(db, domain, cert, flags);
    }

    /**
     * Remove a pinned certificate for the given domain.
     */
    public void unpin_certificate(string domain) {
        db.pinned_certificate.delete()
            .with(db.pinned_certificate.domain, "=", domain)
            .perform();
        debug("Certificate unpinned for domain %s", domain);
    }

    /**
     * Get information about a pinned certificate (static DB operation, clone removal).
     */
    public static CertificateInfo? get_pinned_info_from_db(Database db, string domain) {
        var row_opt = db.pinned_certificate.select()
            .with(db.pinned_certificate.domain, "=", domain)
            .single()
            .row();

        if (!row_opt.is_present()) return null;

        return new CertificateInfo(
            domain,
            row_opt[db.pinned_certificate.fingerprint_sha256],
            row_opt[db.pinned_certificate.issuer],
            row_opt[db.pinned_certificate.not_valid_before] > 0 
                ? new DateTime.from_unix_utc(row_opt[db.pinned_certificate.not_valid_before]) : null,
            row_opt[db.pinned_certificate.not_valid_after] > 0 
                ? new DateTime.from_unix_utc(row_opt[db.pinned_certificate.not_valid_after]) : null,
            new DateTime.from_unix_utc(row_opt[db.pinned_certificate.pinned_at]),
            (TlsCertificateFlags) row_opt[db.pinned_certificate.tls_flags]
        );
    }

    /**
     * Get information about a pinned certificate.
     */
    public CertificateInfo? get_pinned_certificate_info(string domain) {
        return get_pinned_info_from_db(db, domain);
    }

    /**
     * Get all pinned certificates.
     */
    public Gee.List<CertificateInfo> get_all_pinned_certificates() {
        var list = new ArrayList<CertificateInfo>();
        
        foreach (var row in db.pinned_certificate.select()) {
            list.add(new CertificateInfo(
                row[db.pinned_certificate.domain],
                row[db.pinned_certificate.fingerprint_sha256],
                row[db.pinned_certificate.issuer],
                row[db.pinned_certificate.not_valid_before] > 0 
                    ? new DateTime.from_unix_utc(row[db.pinned_certificate.not_valid_before]) : null,
                row[db.pinned_certificate.not_valid_after] > 0 
                    ? new DateTime.from_unix_utc(row[db.pinned_certificate.not_valid_after]) : null,
                new DateTime.from_unix_utc(row[db.pinned_certificate.pinned_at]),
                (TlsCertificateFlags) row[db.pinned_certificate.tls_flags]
            ));
        }
        
        return list;
    }

    /**
     * Validate a certificate. Returns true if the certificate should be accepted.
     * For already pinned certificates matching the fingerprint, returns true.
     * For new or changed certificates, emits a signal for user interaction.
     */
    public bool validate_certificate(string domain, TlsCertificate cert, TlsCertificateFlags errors) {
        // .onion domains get special treatment - accept unknown CA
        if (domain.has_suffix(".onion") && errors == TlsCertificateFlags.UNKNOWN_CA) {
            debug("Accepting certificate from .onion domain %s with unknown CA", domain);
            return true;
        }

        // Check if certificate is already pinned
        string cert_fp = get_certificate_fingerprint(cert);
        string? pinned_fp = db.pinned_certificate.get_pinned_fingerprint(domain);

        if (pinned_fp != null) {
            if (pinned_fp == cert_fp) {
                // Certificate matches pinned fingerprint - accept it
                debug("Certificate for %s matches pinned fingerprint", domain);
                return true;
            } else {
                // Certificate changed! This could be MITM or legitimate update
                warning("Certificate for %s changed from pinned fingerprint! Old: %s, New: %s", 
                    domain, pinned_fp, cert_fp);
                // Fall through to user prompt
            }
        }

        // Certificate not pinned or fingerprint changed - need user decision
        return false;
    }

    /**
     * Create CertificateInfo from a TlsCertificate.
     */
    public CertificateInfo create_certificate_info(string domain, TlsCertificate cert, TlsCertificateFlags flags) {
        return new CertificateInfo(
            domain,
            get_certificate_fingerprint(cert),
            get_certificate_issuer(cert),
            get_certificate_not_before(cert),
            get_certificate_not_after(cert),
            null,  // not pinned yet
            flags
        );
    }

    /**
     * Calculate SHA-256 fingerprint of certificate.
     */
    public static string get_certificate_fingerprint(TlsCertificate cert) {
        var data = cert.certificate.data;
        var checksum = new Checksum(ChecksumType.SHA256);
        checksum.update(data, data.length);
        string hex = checksum.get_string();
        
        // Format as XX:XX:XX:XX... for readability
        var sb = new StringBuilder();
        for (int i = 0; i < hex.length; i += 2) {
            if (i > 0) sb.append(":");
            sb.append(hex.substring(i, 2).up());
        }
        return sb.str;
    }

    /**
     * Extract issuer from certificate (CN or O from issuer DN).
     */
    public static string? get_certificate_issuer(TlsCertificate cert) {
        // GLib.TlsCertificate doesn't expose issuer directly
        // We need to parse the certificate data
        // For now, return the issuer name from the certificate if available
        var issuer = cert.issuer_name;
        if (issuer != null && issuer.length > 0) {
            // Extract CN or O from the DN
            string[] parts = issuer.split(",");
            foreach (string part in parts) {
                string trimmed = part.strip();
                if (trimmed.has_prefix("CN=")) {
                    return trimmed.substring(3);
                }
            }
            foreach (string part in parts) {
                string trimmed = part.strip();
                if (trimmed.has_prefix("O=")) {
                    return trimmed.substring(2);
                }
            }
            return issuer;
        }
        return null;
    }

    /**
     * Get certificate validity start date.
     */
    public static DateTime? get_certificate_not_before(TlsCertificate cert) {
        return cert.not_valid_before;
    }

    /**
     * Get certificate validity end date.
     */
    public static DateTime? get_certificate_not_after(TlsCertificate cert) {
        return cert.not_valid_after;
    }

    /**
     * Get human-readable description of TLS certificate flags/errors.
     */
    public static string get_error_description(TlsCertificateFlags flags) {
        var errors = new ArrayList<string>();

        if (TlsCertificateFlags.UNKNOWN_CA in flags) {
            errors.add("Unknown certificate authority");
        }
        if (TlsCertificateFlags.BAD_IDENTITY in flags) {
            errors.add("Certificate does not match domain");
        }
        if (TlsCertificateFlags.NOT_ACTIVATED in flags) {
            errors.add("Certificate is not yet valid");
        }
        if (TlsCertificateFlags.EXPIRED in flags) {
            errors.add("Certificate has expired");
        }
        if (TlsCertificateFlags.REVOKED in flags) {
            errors.add("Certificate has been revoked");
        }
        if (TlsCertificateFlags.INSECURE in flags) {
            errors.add("Certificate uses insecure algorithm");
        }
        if (TlsCertificateFlags.GENERIC_ERROR in flags) {
            errors.add("Certificate validation error");
        }

        if (errors.size == 0) {
            return "Unknown certificate error";
        }

        return string.joinv("\n• ", errors.to_array());
    }
}

/**
 * Information about a TLS certificate.
 */
public class CertificateInfo : Object {
    public string domain { get; private set; }
    public string fingerprint_sha256 { get; private set; }
    public string? issuer { get; private set; }
    public DateTime? not_valid_before { get; private set; }
    public DateTime? not_valid_after { get; private set; }
    public DateTime? pinned_at { get; private set; }
    public TlsCertificateFlags tls_flags { get; private set; }

    public CertificateInfo(
        string domain,
        string fingerprint_sha256,
        string? issuer,
        DateTime? not_valid_before,
        DateTime? not_valid_after,
        DateTime? pinned_at,
        TlsCertificateFlags tls_flags
    ) {
        this.domain = domain;
        this.fingerprint_sha256 = fingerprint_sha256;
        this.issuer = issuer;
        this.not_valid_before = not_valid_before;
        this.not_valid_after = not_valid_after;
        this.pinned_at = pinned_at;
        this.tls_flags = tls_flags;
    }

    public bool is_expired {
        get {
            if (not_valid_after == null) return false;
            return not_valid_after.compare(new DateTime.now_utc()) < 0;
        }
    }

    public bool is_not_yet_valid {
        get {
            if (not_valid_before == null) return false;
            return not_valid_before.compare(new DateTime.now_utc()) > 0;
        }
    }

    public string get_validity_string() {
        if (not_valid_before == null && not_valid_after == null) {
            return "Unknown validity";
        }

        var sb = new StringBuilder();
        if (not_valid_before != null) {
            sb.append("From: " + not_valid_before.format("%Y-%m-%d"));
        }
        if (not_valid_after != null) {
            if (sb.len > 0) sb.append("\n");
            sb.append("Until: " + not_valid_after.format("%Y-%m-%d"));
            if (is_expired) {
                sb.append(" (expired)");
            }
        }
        return sb.str;
    }
}

}
