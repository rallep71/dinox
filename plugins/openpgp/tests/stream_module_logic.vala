/**
 * Security audit tests for OpenPGP stream_module helper functions.
 *
 * Tests the pure functions: extract_body_from_signcrypt, extract_pgp_data.
 *
 * These functions were originally private static. Changed to internal static
 * for testability.
 */

using Dino.Plugins.OpenPgp;

namespace OpenPgp.Test {

class StreamModuleLogicTest : Gee.TestCase {

    public StreamModuleLogicTest() {
        base("StreamModuleLogic");

        /* extract_body_from_signcrypt */
        add_test("XEP0374_extract_body_simple", test_extract_body_simple);
        add_test("XEP0374_extract_body_with_namespace", test_extract_body_with_ns);
        add_test("XEP0374_extract_body_no_body_returns_null", test_extract_body_no_body);
        add_test("XEP0374_extract_body_empty_body", test_extract_body_empty);
        add_test("XEP0374_extract_body_missing_close_tag", test_extract_body_missing_close);
        add_test("XEP0374_extract_body_bodyguard_no_false_match", test_extract_body_bodyguard);
        add_test("XEP0374_extract_body_with_attributes", test_extract_body_with_attrs);
        add_test("XEP0374_extract_body_xml_entities", test_extract_body_xml_entities);
        add_test("XEP0374_extract_body_nested_elements", test_extract_body_nested);
        add_test("XEP0374_extract_body_full_signcrypt", test_extract_body_full_signcrypt);

        /* extract_pgp_data */
        add_test("XEP0374_extract_pgp_data_normal_armor", test_pgp_data_normal);
        add_test("XEP0374_extract_pgp_data_crlf_headers", test_pgp_data_crlf);
        add_test("XEP0374_extract_pgp_data_no_headers_fallback", test_pgp_data_no_headers);
        add_test("XEP0374_extract_pgp_data_missing_footer", test_pgp_data_missing_footer);
        add_test("XEP0374_extract_pgp_data_empty", test_pgp_data_empty);
        add_test("XEP0374_extract_pgp_data_preserves_base64", test_pgp_data_preserves_b64);
    }

    /* ===== extract_body_from_signcrypt tests ===== */

    /**
     * XEP-0374 S3: Simple body extraction from signcrypt element.
     */
    private void test_extract_body_simple() {
        string xml = "<signcrypt><body>Hello World</body></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: body must be extracted");
        fail_if_not_eq_str(result, "Hello World",
            "XEP-0374: body text must be 'Hello World'");
    }

    /**
     * XEP-0374 S3: Body with xmlns attribute must be extracted correctly.
     */
    private void test_extract_body_with_ns() {
        string xml = "<signcrypt xmlns='urn:xmpp:openpgp:0'><to jid='alice@example.com'/><time stamp='2024-01-01'/><rpad>AAAA</rpad><payload><body xmlns='jabber:client'>Encrypted message</body></payload></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: body with xmlns must be extracted");
        fail_if_not_eq_str(result, "Encrypted message",
            "XEP-0374: body text must be extracted despite xmlns attribute");
    }

    /**
     * XEP-0374: Missing body element must return null.
     */
    private void test_extract_body_no_body() {
        string xml = "<signcrypt><payload><other>data</other></payload></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if(result != null,
            "XEP-0374: missing body must return null");
    }

    /**
     * XEP-0374: Empty body element must return empty string.
     */
    private void test_extract_body_empty() {
        string xml = "<signcrypt><body></body></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: empty body must not return null");
        fail_if_not_eq_str(result, "",
            "XEP-0374: empty body must return empty string");
    }

    /**
     * XEP-0374: Missing </body> close tag must return null.
     */
    private void test_extract_body_missing_close() {
        string xml = "<signcrypt><body>unclosed text</signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if(result != null,
            "XEP-0374: missing </body> close tag must return null");
    }

    /**
     * XEP-0374: <bodyguard> must NOT be confused with <body>.
     *
     * The parser uses index_of("<body") which would match ANY element
     * starting with "body". This test verifies the actual behavior.
     */
    private void test_extract_body_bodyguard() {
        string xml = "<signcrypt><bodyguard>evil</bodyguard><body>real</body></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        // BUG ANALYSIS: index_of("<body") matches <bodyguard> first.
        // content_start = index_of(">", bodyguard_pos) + 1 → after <bodyguard>
        // body_end = index_of("</body>") → matches </body> (NOT </bodyguard>)
        // Result: "evil</bodyguard><body>real" — WRONG!
        // The correct result should be "real".
        if (result != null && result == "real") {
            // Function correctly extracted the right body
        } else if (result != null && result != "real") {
            // Bug found: wrong text extracted due to naive parsing
            GLib.Test.message("BUG #17: extract_body_from_signcrypt matched <bodyguard> instead of <body>. Got: '%s', expected: 'real'", result);
            GLib.Test.fail();
        } else {
            GLib.Test.message("extract_body_from_signcrypt returned null for bodyguard + body XML");
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0374: Body with multiple attributes.
     */
    private void test_extract_body_with_attrs() {
        string xml = "<signcrypt><body xml:lang='en' xmlns='jabber:client'>Attributed</body></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: body with attributes must be extracted");
        fail_if_not_eq_str(result, "Attributed",
            "XEP-0374: body text must be extracted despite attributes");
    }

    /**
     * XEP-0374: XML entities in body must be preserved as-is.
     * The function does raw string extraction, NOT XML parsing.
     */
    private void test_extract_body_xml_entities() {
        string xml = "<signcrypt><body>a &amp; b &lt; c</body></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: body with entities must be extracted");
        // Raw extraction preserves XML entities as-is
        fail_if_not_eq_str(result, "a &amp; b &lt; c",
            "XEP-0374: XML entities must be preserved in raw extraction");
    }

    /**
     * XEP-0374: Body text between nested elements.
     */
    private void test_extract_body_nested() {
        string xml = "<signcrypt><payload><body>nested text</body></payload></signcrypt>";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: nested body must be extracted");
        fail_if_not_eq_str(result, "nested text",
            "XEP-0374: nested body text must match");
    }

    /**
     * XEP-0374 S3: Full signcrypt element from spec.
     */
    private void test_extract_body_full_signcrypt() {
        string xml = """<signcrypt xmlns='urn:xmpp:openpgp:0'>
  <to jid='juliet@example.org'/>
  <time stamp='2014-07-10T17:06:00+02:00'/>
  <rpad>randompadding</rpad>
  <payload>
    <body xmlns='jabber:client'>This is a secret message.</body>
  </payload>
</signcrypt>""";
        string? result = Dino.Plugins.OpenPgp.ReceivedPipelineDecryptListener.extract_body_from_signcrypt(xml);
        fail_if_null(result, "XEP-0374: full signcrypt body must be extracted");
        fail_if_not_eq_str(result, "This is a secret message.",
            "XEP-0374: full signcrypt body text must match spec example");
    }

    /* ===== extract_pgp_data tests ===== */

    /**
     * XEP-0374: Normal PGP ASCII armor extraction.
     */
    private void test_pgp_data_normal() {
        string armored = "-----BEGIN PGP MESSAGE-----\n\nABCDEFGH\n-----END PGP MESSAGE-----";
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data(armored);
        fail_if_not_eq_str(result, "ABCDEFGH",
            "XEP-0374: base64 data must be extracted from armor");
    }

    /**
     * XEP-0374: PGP armor with CRLF line endings (Windows style).
     */
    private void test_pgp_data_crlf() {
        string armored = "-----BEGIN PGP MESSAGE-----\r\n\r\nABCDEFGH\r\n-----END PGP MESSAGE-----";
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data(armored);
        // The function checks \n\n first. In \r\n\r\n, there is no \n\n substring
        // (it's \n\r\n not \n\n). So it falls through to \r\n\r\n check.
        // After start += 2, it includes 2 extra chars (\r\n) but .strip() removes them.
        fail_if_not_eq_str(result, "ABCDEFGH",
            "XEP-0374: CRLF armor must extract same base64 data");
    }

    /**
     * XEP-0374: Input without PGP headers triggers base64-encode fallback.
     * This double-encodes the data, which is a silent corruption path.
     */
    private void test_pgp_data_no_headers() {
        string raw = "not-armored-data";
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data(raw);
        // When no \n\n or \r\n\r\n is found, the function base64-encodes the input.
        // This is a SILENT CORRUPTION: the caller expects base64 PGP data,
        // but gets base64(ASCII) = double-encoded garbage.
        string expected = GLib.Base64.encode(raw.data);
        fail_if_not_eq_str(result, expected,
            "XEP-0374: no-header fallback must base64-encode (FINDING: silent double-encode)");
    }

    /**
     * XEP-0374: Armor without END footer.
     */
    private void test_pgp_data_missing_footer() {
        string armored = "-----BEGIN PGP MESSAGE-----\n\nABCDEFGH\nIJKL";
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data(armored);
        // When END is missing, function uses armored.length as end.
        // Result is everything after blank line, stripped.
        fail_if_not_eq_str(result, "ABCDEFGH\nIJKL",
            "XEP-0374: missing footer must extract remaining data");
    }

    /**
     * XEP-0374: Empty string input.
     */
    private void test_pgp_data_empty() {
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data("");
        // No \n\n found, so fallback: Base64.encode("".data) = ""
        string expected = GLib.Base64.encode("".data);
        fail_if_not_eq_str(result, expected,
            "XEP-0374: empty input produces base64 of empty (fallback path)");
    }

    /**
     * XEP-0374: Properly formatted armor preserves base64 data exactly.
     */
    private void test_pgp_data_preserves_b64() {
        string b64 = "hQIMAxwanFLE4e/4ARAAll3/kI5abH8dECPi+1dK";
        string armored = "-----BEGIN PGP MESSAGE-----\n\n" + b64 + "\n-----END PGP MESSAGE-----";
        string result = Dino.Plugins.OpenPgp.Module.extract_pgp_data(armored);
        fail_if_not_eq_str(result, b64,
            "XEP-0374: base64 data must be preserved exactly from armor");
    }
}

}
