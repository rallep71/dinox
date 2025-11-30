/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Dino.Entities;

namespace Dino.Ui {

/**
 * Dialog for showing TLS certificate warnings and allowing users to pin certificates.
 * This is shown when connecting to a server with a self-signed or otherwise untrusted certificate.
 */
public class CertificateWarningDialog : Object {

    private Adw.AlertDialog dialog;
    private Account account;
    private TlsCertificate certificate;
    private TlsCertificateFlags tls_flags;
    private string domain;
    private StreamInteractor stream_interactor;

    public CertificateWarningDialog(
        Account account,
        TlsCertificate certificate,
        TlsCertificateFlags tls_flags,
        string domain,
        StreamInteractor stream_interactor
    ) {
        this.account = account;
        this.certificate = certificate;
        this.tls_flags = tls_flags;
        this.domain = domain;
        this.stream_interactor = stream_interactor;
    }

    public void present(Window parent) {
        string fingerprint = CertificateManager.get_certificate_fingerprint(certificate);
        string? issuer = CertificateManager.get_certificate_issuer(certificate);
        DateTime? not_before = CertificateManager.get_certificate_not_before(certificate);
        DateTime? not_after = CertificateManager.get_certificate_not_after(certificate);
        string error_description = CertificateManager.get_error_description(tls_flags);

        // Build the dialog content
        var content_box = new Box(Orientation.VERTICAL, 12);
        content_box.margin_start = 12;
        content_box.margin_end = 12;

        // Warning icon and message
        var warning_label = new Label(null);
        warning_label.set_markup("<b>" + _("The server could not prove that it is %s.").printf(domain) + "</b>");
        warning_label.wrap = true;
        warning_label.xalign = 0;
        content_box.append(warning_label);

        // Error reasons
        var error_label = new Label(null);
        error_label.set_markup("• " + error_description.replace("\n• ", "\n• "));
        error_label.wrap = true;
        error_label.xalign = 0;
        error_label.add_css_class("dim-label");
        content_box.append(error_label);

        // Certificate details frame
        var details_frame = new Frame(null);
        details_frame.add_css_class("view");
        var details_box = new Box(Orientation.VERTICAL, 6);
        details_box.margin_start = 12;
        details_box.margin_end = 12;
        details_box.margin_top = 12;
        details_box.margin_bottom = 12;

        // Certificate issuer
        if (issuer != null) {
            var issuer_box = create_detail_row(_("Issued by:"), issuer);
            details_box.append(issuer_box);
        }

        // Validity period
        if (not_before != null || not_after != null) {
            string validity = "";
            if (not_before != null) {
                validity += _("From: ") + not_before.format("%Y-%m-%d");
            }
            if (not_after != null) {
                if (validity.length > 0) validity += "\n";
                validity += _("Until: ") + not_after.format("%Y-%m-%d");
                
                // Check if expired
                if (not_after.compare(new DateTime.now_utc()) < 0) {
                    validity += " <span foreground='red'>(" + _("expired") + ")</span>";
                }
            }
            var validity_box = create_detail_row(_("Valid:"), validity, true);
            details_box.append(validity_box);
        }

        // Fingerprint (SHA-256)
        var fp_box = create_detail_row(_("SHA-256 Fingerprint:"), "");
        details_box.append(fp_box);

        // Fingerprint in a monospace, selectable text view
        var fp_label = new Label(fingerprint);
        fp_label.add_css_class("monospace");
        fp_label.wrap = true;
        fp_label.wrap_mode = Pango.WrapMode.CHAR;
        fp_label.xalign = 0;
        fp_label.selectable = true;
        fp_label.add_css_class("dim-label");
        details_box.append(fp_label);

        details_frame.child = details_box;
        content_box.append(details_frame);

        // Warning about security
        var security_warning = new Label(null);
        security_warning.set_markup("<small>" + _("If you trust this server, you can add the certificate to your trusted list. This is similar to SSH's known_hosts.") + "</small>");
        security_warning.wrap = true;
        security_warning.xalign = 0;
        security_warning.add_css_class("dim-label");
        content_box.append(security_warning);

        // Create the dialog
        dialog = new Adw.AlertDialog(
            _("Certificate Warning"),
            null
        );
        dialog.extra_child = content_box;
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("trust", _("Trust This Certificate"));
        dialog.set_response_appearance("trust", Adw.ResponseAppearance.SUGGESTED);
        dialog.default_response = "cancel";
        dialog.close_response = "cancel";

        dialog.response.connect(on_response);
        dialog.present(parent);
    }

    private Box create_detail_row(string label_text, string value_text, bool use_markup = false) {
        var box = new Box(Orientation.HORIZONTAL, 6);
        
        var label = new Label(label_text);
        label.xalign = 0;
        label.add_css_class("dim-label");
        box.append(label);

        var value = new Label(null);
        if (use_markup) {
            value.set_markup(value_text);
        } else {
            value.label = value_text;
        }
        value.xalign = 0;
        value.hexpand = true;
        value.wrap = true;
        box.append(value);

        return box;
    }

    private void on_response(string response) {
        if (response == "trust") {
            // Pin the certificate
            stream_interactor.connection_manager.pin_certificate(domain, certificate, tls_flags);
            
            // Reconnect the account
            stream_interactor.connect_account(account);
        }
        dialog.close();
    }
}

}
