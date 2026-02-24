# DinoX -- Testing Guide

Complete inventory of all automated tests in the DinoX project.
Every test references its authoritative specification or contract.

**Status: v1.7.0.0 -- 556 Meson tests + 136 standalone tests = 692 automated tests, 0 failures**

---

## Quick Start

```bash
# All tests at once (recommended)
./scripts/run_all_tests.sh

# Only Meson-registered tests (7 suites, 556 tests)
./scripts/run_all_tests.sh --meson

# Only DB maintenance tests (136 standalone)
./scripts/run_all_tests.sh --db
```

---

## Developer Quick Reference -- All Scripts & Test Tools

This section lists **every** test-related script, binary, and tool in the project.
Use it as a cheat sheet when working on DinoX.

### Complete Script Inventory

| Script | Language | Tests | What it does |
|--------|----------|-------|--------------|
| `scripts/run_all_tests.sh` | Bash | 678 | **Master runner** -- builds, runs all Meson suites + DB tests, prints color-coded summary |
| `scripts/test_db_maintenance.sh` | Bash | 71 | SQLCipher CLI tests: rekey, reset, WAL checkpoint, backup |
| `scripts/run_db_integration_tests.sh` | Bash+Vala | 65 | Compiles + runs Vala integration tests against `libqlite.so` |
| `check_translations.py` | Python | -- | Checks `.po` files for missing/fuzzy translations via `msgfmt` |
| `scripts/scan_unicode.py` | Python | -- | Scans source for hidden/dangerous Unicode (zero-width, BiDi overrides) |
| `scripts/analyze_translations.py` | Python | -- | Analyzes specific translation keys across all `.po` files |
| `scripts/translate_all.py` | Python | -- | Batch translation helper for `.po` files |

### Compiled Test Binaries (Meson)

After `ninja -C build`, these binaries are ready:

| Binary | Suite | Tests | Component |
|--------|-------|-------|-----------|
| `build/xmpp-vala/xmpp-vala-test` | xmpp-vala | 245 | XMPP protocol, XML, JID, XEP parsers, SOCKS5 |
| `build/plugins/omemo/omemo-test` | omemo | 102 | OMEMO encryption, Signal Protocol, key exchange |
| `build/main/main-test` | main | 62 | UI view models, helper functions |
| `build/plugins/openpgp/openpgp-test` | openpgp | 48 | OpenPGP stream module, GPG keylist, armor parser |
| `build/libdino/libdino-test` | libdino | 50 | Crypto, key derivation, file transfer, SRTP, data structures |
| `build/plugins/http-files/http-files-test` | http-files | 25 | URL regex, filename extraction, log sanitization |
| `build/plugins/bot-features/bot-features-test` | bot-features | 24 | Rate limiter, crypto hashes, JSON escaping |

**Important:** Before running binaries directly, set the library path:

```bash
export LD_LIBRARY_PATH=build/libdino:build/xmpp-vala:build/qlite:build/crypto-vala
```

### Standalone Test Files (not in Meson)

| File | Language | Purpose |
|------|----------|---------|
| `tests/security_audit_tests.vala` | Vala | Original security audit findings (732 lines) -- documents bugs found |
| `tests/test_db_maintenance_integration.vala` | Vala | Qlite integration tests (compiled by `run_db_integration_tests.sh`) |
| `test_omemo_deser.c` | C | OMEMO deserialization test with real Kaidan kex bytes |
| `test_cb.vala` | Vala | TLS channel binding type check (minimal) |
| `test_socks.py` | Python | Manual SOCKS5 proxy connectivity test |

### Typical Developer Workflows

#### Before every commit

```bash
# Fast: only the Meson tests (< 15 seconds)
./scripts/run_all_tests.sh --meson
```

#### Full regression check

```bash
# All 692 tests -- Meson + DB
./scripts/run_all_tests.sh
```

#### Working on a specific component

```bash
export LD_LIBRARY_PATH=build/libdino:build/xmpp-vala:build/qlite:build/crypto-vala
ninja -C build

# Run only the suite you changed:
build/xmpp-vala/xmpp-vala-test          # XMPP/XML changes
build/plugins/omemo/omemo-test           # OMEMO changes
build/main/main-test                     # UI logic changes
build/libdino/libdino-test               # Core library changes
build/plugins/openpgp/openpgp-test       # OpenPGP changes
build/plugins/bot-features/bot-features-test  # Bot plugin changes
build/plugins/http-files/http-files-test      # HTTP file upload changes
```

#### Run a single test by path

```bash
# Pattern: binary -p /SuiteName/test_name
build/xmpp-vala/xmpp-vala-test -p /Jid/RFC7622_valid_bare
build/libdino/libdino-test -p /Security/SP800_38D_tag_is_128_bits
build/main/main-test -p /UiHelperAudit/RFC3986_url_regex_matches_https
```

#### List all test names (without running)

```bash
build/xmpp-vala/xmpp-vala-test -l
build/libdino/libdino-test -l
build/main/main-test -l
build/plugins/omemo/omemo-test -l
build/plugins/openpgp/openpgp-test -l
build/plugins/bot-features/bot-features-test -l
build/plugins/http-files/http-files-test -l
```

#### Verbose / debug output

```bash
# Via Meson (all suites):
meson test -C build -v --print-errorlogs

# Single binary:
build/xmpp-vala/xmpp-vala-test --verbose
```

#### DB maintenance tests only

```bash
# CLI tests (requires sqlcipher in PATH)
./scripts/test_db_maintenance.sh

# Vala integration tests (compiles on the fly)
./scripts/run_db_integration_tests.sh
```

#### Code quality checks

```bash
# Translation completeness
python3 check_translations.py

# Hidden Unicode scan (zero-width chars, BiDi overrides)
python3 scripts/scan_unicode.py
python3 scripts/scan_unicode.py --verbose   # show details
```

### Reading Test Output

#### run_all_tests.sh output

```
==========================================
 DinoX -- Complete Test Run
==========================================
  Date:    2026-02-23 14:30:00
  Branch:  main
  Commit:  0e0b766a

============================================
 Meson Tests (7 suites, 556 tests)
============================================
>>> main-test (62 UI ViewModel + helper tests)
    OK
>>> xmpp-vala-test (245 XMPP protocol tests)
    OK
...
==========================================
 Summary
==========================================
  PASS  main-test (62 UI ViewModel + helper tests)
  PASS  xmpp-vala-test (245 XMPP protocol tests)
  PASS  libdino-test (50 crypto + data structure tests)
  PASS  omemo-test (102 Signal Protocol + OMEMO tests)
  PASS  openpgp-test (48 OpenPGP stream + armor tests)
  PASS  bot-features-test (24 rate limiter + crypto tests)
  PASS  http-files-test (25 URL regex + sanitize tests)
  PASS  DB CLI tests (71 bash tests)
  PASS  DB Integration tests (65 Vala tests)

  Pass: 9  Fail: 0  Skip: 0

ALL TESTS PASSED
```

Exit code **0** = all pass. Exit code **1** = at least one failure.

#### Meson TAP output (single binary)

```
TAP version 13
1..16
ok 1 /PreferencesRow/GObject_Text_title_roundtrip
ok 2 /PreferencesRow/GObject_Text_text_roundtrip
not ok 3 /PreferencesRow/GObject_Text_media_type_nullable   <-- FAILURE
# GLib.Test message: media_type should default to null
```

| Marker | Meaning |
|--------|---------|
| `ok N` | Test passed |
| `not ok N` | Test **FAILED** -- read `#` lines below for details |
| `1..N` | Total test count |

#### When a test fails

1. The test name tells you the spec: `RFC7622_` = JID, `SP800_38D_` = AES-GCM, `XEP0384_` = OMEMO, etc.
2. The `#` comment lines show the assertion message with the spec violation
3. Fix the **code**, not the test (tests encode spec requirements)
4. Re-run: `ninja -C build && meson test -C build --print-errorlogs`
5. Full logs: `build/meson-logs/testlog.txt`

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | At least one test failed |
| 77 | Test was skipped |
| 99 | Hard error (segfault, build failure) |

---

## How to Run Tests -- Step-by-Step

### Prerequisites

| Requirement | Purpose | Check |
|-------------|---------|-------|
| `meson` + `ninja` | Build system | `meson --version` |
| `valac` >= 0.56 | Vala compiler | `valac --version` |
| GTK4, libadwaita, GLib, Gee | Runtime deps | `pkg-config --modversion gtk4` |
| `sqlcipher` | DB CLI tests (optional) | `which sqlcipher` |
| Build directory exists | Compiled tests | `ls build/build.ninja` |

### Build

```bash
# First time setup
meson setup build

# Rebuild (incremental)
ninja -C build
```

### Running individual suites

```bash
# Set library path (needed when running directly)
export LD_LIBRARY_PATH=build/libdino:build/xmpp-vala:build/qlite:build/crypto-vala

# Run one suite
build/xmpp-vala/xmpp-vala-test     # 245 tests
build/libdino/libdino-test          # 50 tests
build/main/main-test                # 62 tests
build/plugins/omemo/omemo-test      # 102 tests
build/plugins/openpgp/openpgp-test  # 48 tests
build/plugins/bot-features/bot-features-test  # 24 tests
build/plugins/http-files/http-files-test      # 25 tests
```

### Running a single test by name

```bash
export LD_LIBRARY_PATH=build/libdino:build/xmpp-vala:build/qlite:build/crypto-vala
build/xmpp-vala/xmpp-vala-test -p /Jid/RFC7622_valid_bare
build/libdino/libdino-test -p /Security/SP800_38D_tag_is_128_bits
```

### List all test names (without running)

```bash
build/xmpp-vala/xmpp-vala-test -l
build/libdino/libdino-test -l
build/main/main-test -l
build/plugins/omemo/omemo-test -l
build/plugins/openpgp/openpgp-test -l
build/plugins/bot-features/bot-features-test -l
build/plugins/http-files/http-files-test -l
```

### Verbose output

```bash
meson test -C build -v --print-errorlogs
# or for a single binary:
build/xmpp-vala/xmpp-vala-test --verbose
```

### DB maintenance tests

```bash
# CLI tests (requires sqlcipher)
./scripts/test_db_maintenance.sh        # 71 tests

# Vala integration tests
./scripts/run_db_integration_tests.sh   # 65 tests
```

---

## 1. Meson-Registered Tests (556 Tests)

Compiled and executed via `ninja -C build test`.
Framework: GLib.Test + `Gee.TestCase` with `add_async_test()` for async XML parsing.

### 1.1 xmpp-vala (245 Tests)

**Target:** `xmpp-vala-test` -- `xmpp-vala/meson.build`

#### Stanza (4 Tests) -- RFC 6120

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 1 | `RFC6120_xml_roundtrip_preserves_namespaces` | RFC 6120 S4.8 | XML namespace preservation across serialize-parse-reserialize |
| 2 | `RFC6120_parse_stream_and_message` | RFC 6120 S4.7.1 | Parse complete XMPP stream: `<stream:stream>`, `<message>`, body text |
| 3 | `RFC6120_parse_stream_features_with_namespaces` | RFC 6120 S4.3.2 | `<stream:features>` with multiple namespace prefixes (ack:, bind:) |
| 4 | `RFC6120_attribute_int_parsing_edge_cases` | RFC 6120 S13.9 | Int parsing: valid decimal, negative, missing, hex string "0x42", non-numeric |

#### util (5 Tests) -- Hex Parsing Contract

| # | Test | Verifies |
|---|------|----------|
| 5-9 | `XSD_hexBinary_from_hex("")`, etc. | xs:hexBinary parsing: empty->0, full hex, "0x" prefix->0, non-hex terminate |

#### Jid (28 Tests) -- RFC 7622

| # | Tests | Spec | Verifies |
|---|-------|------|----------|
| 10-13 | `RFC7622_valid_*` | RFC 7622 S3.1 | Valid JIDs: domain-only, bare, domain+resource, full |
| 14-17 | `RFC7622_valid_emoji_*` | RFC 7622 + Unicode | Emoji in local/domain/resource part |
| 18-21 | `RFC7622_invalid_*` | RFC 7622 S3.5 | Invalid JIDs: bidi characters, overlong IDN |
| 22-29 | `RFC7622_equal_*` | RFC 7622 S3.6 | Equality: case-folding, normalization, punycode, resource case-sensitive |
| 30-37 | `RFC7622_to_string_*` | RFC 7622 S3.1 | String representation after normalization |

#### Color (3 Tests) -- XEP-0392

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 38 | `XEP0392_angle_test_vectors` | XEP-0392 S5 | Official angle test vectors: Romeo->327.25deg, juliet@capulet.lit->209.41deg |
| 39 | `XEP0392_rgbf_test_vectors` | XEP-0392 S5 | Official RGB test vectors |
| 40 | `XEP0392_rgb_angle_range_0_360` | XEP-0392 S3 | All angles in [0,360), RGB in [0,1] for 22 diverse inputs |

#### VCard4 (2 Tests) -- RFC 6350/6351

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 41 | `RFC6351_serialization_structure` | RFC 6351 S3 | xCard serialization: `<vcard>` root, FN mandatory (S6.2.1), EMAIL |
| 42 | `RFC6351_parse_xcard_xml` | RFC 6350 S6 | Real XML parsing: FN, NICKNAME, EMAIL, TEL, TITLE, ORG, URL=null |

#### Xep0448 (2 Tests) -- XEP-0448

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 43 | `XEP0448_encryption_element_structure` | XEP-0448 S3 | `<encrypted>` contains `<key>` + `<iv>` + inner `<sources>` |
| 44 | `XEP0448_key_iv_base64_preserved` | XEP-0448 S3 | Base64 values survive serialization exactly |

#### StreamManagement (12 Tests) -- XEP-0198

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 45 | `XEP0198_enable_must_have_xmlns_sm3` | XEP-0198 S3 | `<enable xmlns='urn:xmpp:sm:3'>` |
| 46 | `XEP0198_enable_resume_attribute` | XEP-0198 S3 | Resume attribute is set |
| 47 | `XEP0198_parse_enabled_from_xml` | XEP-0198 S4 | **Async**: parse real XML `<enabled>` via StanzaReader |
| 48 | `XEP0198_r_element_is_empty` | XEP-0198 S5 | `<r/>` has no children |
| 49 | `XEP0198_a_element_has_h` | XEP-0198 S5 | `<a h='5'>` has h attribute |
| 50 | `XEP0198_h_counter_is_uint32` | XEP-0198 S5 | h=2^31 (2147483648) works (no signed overflow) |
| 51 | `XEP0198_h_wraps_at_2_32` | XEP-0198 S5 | uint32.MAX+1 = 0 (wrap-around) |
| 52 | `XEP0198_h_max_value_4294967295` | XEP-0198 S5 | h can reach 4294967295 |
| 53 | `XEP0198_parse_resumed_from_xml` | XEP-0198 S6 | **Async**: parse `<resumed>` XML |
| 54 | `XEP0198_parse_failed_with_h` | XEP-0198 S6 | **Async**: `<failed>` with h value and error child |
| 55 | `XEP0198_feature_in_stream_features` | XEP-0198 S3 | **Async**: detect SM in `<stream:features>` |
| 56 | `XEP0198_only_stanzas_increment_h` | XEP-0198 S5 | Only stanzas (message/iq/presence) count, not nonzas |

#### MAM (8 Tests) -- XEP-0313

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 57 | `XEP0313_query_namespace_is_mam2` | XEP-0313 S3 | Query element MUST be `urn:xmpp:mam:2` |
| 58 | `XEP0313_query_must_carry_queryid` | XEP-0313 S3 | queryid attribute survives |
| 59 | `XEP0313_fin_complete_true` | XEP-0313 S5.3 | `<fin complete='true'>` + RSM first/last |
| 60 | `XEP0313_fin_absent_complete_means_incomplete` | XEP-0313 S5.3 | Missing complete -> false (more results available) |
| 61 | `XEP0313_fin_rsm_first_last` | XEP-0059 S2.6 | Empty `<set/>` -> first=null, last=null |
| 62 | `XEP0313_fin_missing_rsm_is_null` | XEP-0313 | `<fin>` without `<set>` -> rsm=null |
| 63 | `XEP0313_parse_result_from_xml` | XEP-0313 S4 | **Async**: real XML parsing: result->forwarded->delay->message |
| 64 | `XEP0313_message_flag_fields` | XEP-0313 S4 | MessageFlag: sender_jid, mam_id, query_id, server_time |

#### Audit XEP-0198 (3 Tests) -- Security Audit

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 65 | `h_counter_must_be_uint32` | XEP-0198 S5 | Declared type is `uint32` |
| 66 | `h_counter_overflow_produces_negative` | NIST | Integer overflow detection |
| 67 | `h_to_string_must_not_be_negative` | XEP-0198 S5 | String representation must never be negative |

#### OmemoAudit (39 Tests) -- XEP-0384 v0.3 + v0.8

OMEMO v1 (legacy, `eu.siacs.conversations.axolotl`) and OMEMO 2 (`urn:xmpp:omemo:2`) stanza structure,
namespace constants, key/tag layout, parsing, and encrypt-state accumulation.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 68 | `XEP0384v03_ns_uri_is_siacs_axolotl` | XEP-0384 v0.3 | Legacy namespace constant |
| 69 | `XEP0384v03_node_devicelist_suffix` | XEP-0384 v0.3 | Devicelist PubSub node suffix |
| 70 | `XEP0384v03_node_bundles_suffix` | XEP-0384 v0.3 | Bundles PubSub node suffix |
| 71 | `XEP0384v03_encrypted_node_has_header_with_sid` | XEP-0384 v0.3 S4 | `<encrypted>` → `<header sid='...'>` |
| 72 | `XEP0384v03_encrypted_node_has_iv_in_header` | XEP-0384 v0.3 S4 | IV element in header (required for AES-GCM) |
| 73 | `XEP0384v03_encrypted_node_has_payload` | XEP-0384 v0.3 S4 | `<payload>` with base64 ciphertext |
| 74 | `XEP0384v03_key_node_has_rid_and_prekey` | XEP-0384 v0.3 S4 | `<key rid='...' prekey='true'>` attributes |
| 75 | `XEP0384v03_key_node_contains_base64_key` | XEP-0384 v0.3 S4 | Key element value is base64 |
| 76 | `XEP0384v03_multiple_keys_in_header` | XEP-0384 v0.3 S4 | Multiple recipients → multiple `<key>` nodes |
| 77 | `XEP0384v03_no_payload_for_keyexchange_only` | XEP-0384 v0.3 S4 | Empty payload → no `<payload>` element |
| 78 | `SP800_38D_keytag_32_bytes_is_key16_tag16` | NIST SP 800-38D | AES-GCM key\|\|tag = 16+16 = 32 bytes |
| 79 | `XEP0384v03_parse_extracts_sid` | XEP-0384 v0.3 S4 | Parser extracts sender device ID from header |
| 80 | `XEP0384v03_parse_extracts_iv` | XEP-0384 v0.3 S4 | Parser extracts IV from header |
| 81 | `XEP0384v03_parse_extracts_payload` | XEP-0384 v0.3 S4 | Parser extracts payload ciphertext |
| 82 | `XEP0384v03_parse_missing_header_returns_null` | XEP-0384 v0.3 | Missing header → null (not crash) |
| 83 | `XEP0384v03_parse_missing_iv_returns_null` | XEP-0384 v0.3 | Missing IV → null (not crash) |
| 84 | `XEP0384v03_parse_finds_our_key_by_rid` | XEP-0384 v0.3 S4 | Correct key selected by recipient device ID |
| 85 | `XEP0384v03_parse_prekey_attribute` | XEP-0384 v0.3 S4 | PreKey flag correctly parsed |
| 86 | `XEP0384v08_ns_uri_is_omemo_2` | XEP-0384 v0.8 | OMEMO 2 namespace `urn:xmpp:omemo:2` |
| 87 | `XEP0384v08_node_devicelist_suffix` | XEP-0384 v0.8 | OMEMO 2 devicelist node suffix |
| 88 | `XEP0384v08_node_bundles_suffix` | XEP-0384 v0.8 | OMEMO 2 bundles node suffix |
| 89 | `XEP0384v08_encrypted_node_uses_v2_namespace` | XEP-0384 v0.8 S4 | `<encrypted xmlns='urn:xmpp:omemo:2'>` |
| 90 | `XEP0384v08_keys_grouped_by_jid` | XEP-0384 v0.8 S4 | Keys grouped in `<keys jid='...'>` elements |
| 91 | `XEP0384v08_kex_attribute_not_prekey` | XEP-0384 v0.8 S4 | OMEMO 2 uses `kex` attribute (not `prekey`) |
| 92 | `XEP0384v08_no_iv_in_header` | XEP-0384 v0.8 S4 | No IV element in v2 header (derived via HKDF) |
| 93 | `XEP0384v08_payload_contains_ciphertext` | XEP-0384 v0.8 S4 | `<payload>` base64 ciphertext present |
| 94 | `XEP0384v08_header_has_sid` | XEP-0384 v0.8 S4 | Header carries sender device ID |
| 95 | `XEP0384v08_multiple_jids_multiple_keys` | XEP-0384 v0.8 S4 | Multiple JIDs with multiple keys each |
| 96 | `XEP0384v08_empty_payload_no_element` | XEP-0384 v0.8 S4 | Empty payload → no `<payload>` element |
| 97 | `XEP0384v08_parse_extracts_sid` | XEP-0384 v0.8 S4 | Parser extracts sender device ID |
| 98 | `XEP0384v08_parse_extracts_payload` | XEP-0384 v0.8 S4 | Parser extracts payload ciphertext |
| 99 | `XEP0384v08_parse_finds_keys_by_jid` | XEP-0384 v0.8 S4 | Keys matched by recipient JID |
| 100 | `XEP0384v08_parse_kex_attribute` | XEP-0384 v0.8 S4 | KEX flag correctly parsed |
| 101 | `XEP0384v08_parse_missing_header_returns_null` | XEP-0384 v0.8 | Missing header → null (not crash) |
| 102 | `XEP0384v08_parse_missing_sid_returns_null` | XEP-0384 v0.8 | Missing SID → null (not crash) |
| 103 | `XEP0384v08_parse_ignores_other_jid_keys` | XEP-0384 v0.8 S4 | Keys for other JIDs not included |
| 104 | `XEP0384v08_mk_with_tag_must_be_48_bytes` | XEP-0384 v0.8 | mk\|\|auth_tag = 32+16 = 48 bytes |
| 105 | `XEP0384_encrypt_state_add_result_own` | XEP-0384 | EncryptState accumulates own-device results |
| 106 | `XEP0384_encrypt_state_add_result_other` | XEP-0384 | EncryptState accumulates other-device results |

#### OpenPgpAudit (36 Tests) -- XEP-0373 + XEP-0374

OpenPGP for XMPP stanza structure (signcrypt/sign/crypt/openpgp elements),
namespace constants, data classes, roundtrip serialization, random padding, modulo bias, CSPRNG, and cross-element rejection.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 107 | `XEP0373_ns_uri_is_openpgp_0` | XEP-0373 S2 | Namespace `urn:xmpp:openpgp:0` |
| 108 | `XEP0373_ns_pubkeys_suffix` | XEP-0373 S4 | Public-keys namespace suffix |
| 109 | `XEP0373_public_key_meta_stores_fingerprint` | XEP-0373 S4 | PublicKeyMeta.fingerprint stored |
| 110 | `XEP0373_public_key_meta_stores_date` | XEP-0373 S4 | PublicKeyMeta.date stored |
| 111 | `XEP0373_public_key_data_has_armored_key` | XEP-0373 S4 | PublicKeyData.armored_key stored |
| 112 | `XEP0373_public_key_data_date_optional` | XEP-0373 S4 | PublicKeyData.date nullable |
| 113 | `XEP0374_ns_uri_is_openpgp_0` | XEP-0374 S2 | Matches XEP-0373 NS_URI |
| 114 | `XEP0374_ns_uri_im_service_discovery` | XEP-0374 S6 | IM namespace `urn:xmpp:openpgp:im:0` |
| 115 | `XEP0374_signcrypt_with_body_roundtrip` | XEP-0374 S3 | create → serialize → parse → get_body_text |
| 116 | `XEP0374_signcrypt_has_to_jid` | XEP-0374 S3 | `<to jid='...'>` element |
| 117 | `XEP0374_signcrypt_has_time_stamp` | XEP-0374 S3 | `<time stamp='...'>` element |
| 118 | `XEP0374_signcrypt_has_rpad` | XEP-0374 S3 | `<rpad>` random padding element |
| 119 | `XEP0374_signcrypt_has_payload_with_body` | XEP-0374 S3 | `<payload>` wrapping `<body>` |
| 120 | `XEP0374_signcrypt_get_body_text` | XEP-0374 S3 | Body text extraction |
| 121 | `XEP0374_signcrypt_stanza_element_name` | XEP-0374 S3 | Root element name is `signcrypt` |
| 122 | `XEP0374_signcrypt_invalid_root_returns_null` | XEP-0374 | Invalid root → null (not crash) |
| 123 | `XEP0374_signcrypt_wrong_ns_returns_null` | XEP-0374 | Wrong namespace → null (not crash) |
| 124 | `XEP0374_sign_element_structure` | XEP-0374 S4 | `<sign>` element with time+rpad+payload |
| 125 | `XEP0374_sign_roundtrip` | XEP-0374 S4 | Sign create → serialize → parse |
| 126 | `XEP0374_sign_invalid_root_returns_null` | XEP-0374 S4 | Invalid sign root → null |
| 127 | `XEP0374_crypt_element_structure` | XEP-0374 S5 | `<crypt>` element with to+time+rpad+payload |
| 128 | `XEP0374_crypt_roundtrip` | XEP-0374 S5 | Crypt create → serialize → parse |
| 129 | `XEP0374_crypt_invalid_root_returns_null` | XEP-0374 S5 | Invalid crypt root → null |
| 130 | `XEP0374_openpgp_element_wraps_base64` | XEP-0374 S6 | `<openpgp>` wraps base64 content |
| 131 | `XEP0374_openpgp_element_roundtrip` | XEP-0374 S6 | OpenpgpElement serialize → parse |
| 132 | `XEP0374_openpgp_invalid_root_returns_null` | XEP-0374 S6 | Invalid openpgp root → null |
| 133 | `XEP0374_openpgp_null_content_returns_null` | XEP-0374 S6 | Null content → null |
| 134 | `XEP0374_signcrypt_rpad_is_nonempty` | XEP-0374 S3 | Random padding never empty |
| 135 | `XEP0374_signcrypt_rpad_is_base64` | XEP-0374 S3 | Padding is valid base64 |
| 136 | `XEP0374_rpad_modulo_bias_256_mod_49` | XEP-0374 S3 | **Bug #16 FIXED**: rejection sampling (245%49=0) eliminates modulo bias |
| 137 | `XEP0374_rpad_length_varies_between_instances` | XEP-0374 S3 | Two SigncryptElements have different rpad (CSPRNG sanity) |
| 138 | `XEP0374_rpad_decode_length_in_16_to_64` | XEP-0374 S3 | 20 samples all decode to [16,64] bytes |
| 139 | `SP800_90A_rpad_uses_dev_urandom_on_linux` | NIST SP 800-90A | /dev/urandom exists on Linux (CSPRNG path) |
| 140 | `XEP0374_signcrypt_rejects_sign_element` | XEP-0374 | Cross-element rejection: signcrypt ≠ sign |
| 141 | `XEP0374_sign_rejects_crypt_element` | XEP-0374 | Cross-element rejection: sign ≠ crypt |
| 142 | `XEP0374_crypt_rejects_signcrypt_element` | XEP-0374 | Cross-element rejection: crypt ≠ signcrypt |

#### StanzaEntryAudit (21 Tests) -- XML Entity Decode + Attribute Parsing

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 143 | `XEP0115_5_1_amp_entity_decoded` | XEP-0115 S5.1 | `&amp;` decodes to `&` |
| 144 | `XEP0115_5_1_lt_entity_decoded` | XEP-0115 S5.1 | `&lt;` decodes to `<` |
| 145 | `XEP0115_5_1_gt_entity_decoded` | XEP-0115 S5.1 | `&gt;` decodes to `>` |
| 146 | `XEP0115_5_1_apos_entity_decoded` | XEP-0115 S5.1 | `&apos;` decodes to `'` |
| 147 | `XEP0115_5_1_quot_entity_decoded` | XEP-0115 S5.1 | `&quot;` decodes to `"` |
| 148 | `XML_all_named_entities_combined` | XML 1.0 S4.6 | All 5 named entities in one string |
| 149 | `XML_hex_char_ref_basic` | XML 1.0 S4.1 | `&#x41;` → `A` (Bug #20 fixed) |
| 150 | `XML_decimal_char_ref_basic` | XML 1.0 S4.1 | `&#65;` → `A` (Bug #20 fixed) |
| 151 | `XML_hex_char_ref_unicode` | XML 1.0 S4.1 | `&#x263A;` → `☺` (Bug #20 fixed) |
| 152 | `XML_numeric_ref_with_trailing_text` | XML 1.0 S4.1 | `&#x48;ello` → `Hello` (Bug #20 fixed) |
| 153 | `XML_multiple_numeric_refs` | XML 1.0 S4.1 | Multiple hex refs in sequence (Bug #20 fixed) |
| 154 | `XML_unclosed_numeric_ref_no_crash` | XML 1.0 S4.1 | Unclosed `&#x41` does not crash |
| 155 | `XML_empty_numeric_ref_no_crash` | XML 1.0 S4.1 | `&#;` does not crash |
| 156 | `XML_hash_without_semicolon_no_crash` | XML 1.0 S4.1 | Trailing `&#` does not crash |
| 157 | `XML_entity_encode_decode_roundtrip` | XML 1.0 S4 | encode→decode roundtrip preserves all chars |
| 158 | `RFC6120_bool_true_string` | RFC 6120 | `"true"` parses as boolean true |
| 159 | `RFC6120_bool_one_is_true` | RFC 6120 | `"1"` parses as boolean true |
| 160 | `RFC6120_bool_false_string` | RFC 6120 | `"false"` parses as boolean false |
| 161 | `RFC6120_bool_zero_is_false` | RFC 6120 | `"0"` parses as boolean false |
| 162 | `RFC6120_bool_missing_returns_default` | RFC 6120 | Missing attribute returns default |
| 163 | `RFC6120_bool_garbage_is_false` | RFC 6120 | Unrecognized value treated as false |

#### CryptoHashAudit (15 Tests) -- XEP-0300 Cryptographic Hashes

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 164 | `XEP0300_sha1_type_to_string` | XEP-0300 | SHA1 → `"sha-1"` |
| 165 | `XEP0300_sha256_type_to_string` | XEP-0300 | SHA256 → `"sha-256"` |
| 166 | `XEP0300_sha384_type_to_string` | XEP-0300 | SHA384 → `"sha-384"` |
| 167 | `XEP0300_sha512_type_to_string` | XEP-0300 | SHA512 → `"sha-512"` |
| 168 | `XEP0300_md5_type_to_string` | XEP-0300 | MD5 → `"md5"` |
| 169 | `XEP0300_sha1_string_to_type` | XEP-0300 | `"sha-1"` → SHA1 |
| 170 | `XEP0300_sha256_string_to_type` | XEP-0300 | `"sha-256"` → SHA256 |
| 171 | `XEP0300_sha384_string_to_type` | XEP-0300 | `"sha-384"` → SHA384 |
| 172 | `XEP0300_sha512_string_to_type` | XEP-0300 | `"sha-512"` → SHA512 |
| 173 | `XEP0300_md5_string_to_type` | XEP-0300 | `"md5"` → MD5 (Bug #21 fixed) |
| 174 | `XEP0300_unknown_string_returns_null` | XEP-0300 | Unknown hash name → null |
| 175 | `XEP0300_sha256_roundtrip` | XEP-0300 | type→string→type roundtrip |
| 176 | `XEP0300_sha256_compute_empty` | NIST FIPS 180-4 | SHA-256 of empty = known vector |
| 177 | `XEP0300_sha256_compute_abc` | NIST FIPS 180-4 | SHA-256 of "abc" = NIST vector |
| 178 | `XEP0300_sha1_compute_abc` | NIST FIPS 180-4 | SHA-1 of "abc" = known vector |

#### EntityCapsAudit (5 Tests) -- XEP-0115 Entity Capabilities

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 179 | `XEP0115_5_4_example1_exodus` | XEP-0115 S5.4 | Example 1 hash = `QgayPKawpkPSDYmwT/WM94uAlu0=` |
| 180 | `XEP0115_empty_identity_set` | XEP-0115 S5.1 | Empty identities → valid hash |
| 181 | `XEP0115_multiple_identities_sorted` | XEP-0115 S5.2 | Deterministic hash with multiple identities |
| 182 | `XEP0115_features_sorted` | XEP-0115 S5.3 | Feature order does not affect hash |
| 183 | `XEP0115_identity_with_lt_sanitized` | XEP-0115 S5.1 | `<` in identity sanitized as `&lt;` |

#### ProtocolParserAudit (27 Tests) -- Jingle/SOCKS5/ICE/Markup/DateTime

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 184 | `XEP0166_senders_parse_initiator` | XEP-0166 | `"initiator"` → INITIATOR |
| 185 | `XEP0166_senders_parse_responder` | XEP-0166 | `"responder"` → RESPONDER |
| 186 | `XEP0166_senders_parse_both` | XEP-0166 | `"both"` → BOTH |
| 187 | `XEP0166_senders_parse_null_defaults_both` | XEP-0166 | null → BOTH (default) |
| 188 | `XEP0166_senders_parse_invalid_throws` | XEP-0166 | Invalid string → IqError |
| 189 | `XEP0166_senders_parse_none_throws` | XEP-0166 | `"none"` → IqError (not in parse) |
| 190 | `XEP0166_role_parse_initiator` | XEP-0166 | `"initiator"` → INITIATOR |
| 191 | `XEP0166_role_parse_responder` | XEP-0166 | `"responder"` → RESPONDER |
| 192 | `XEP0166_role_parse_invalid_throws` | XEP-0166 | Invalid role → IqError |
| 193 | `XEP0260_candidate_parse_assisted` | XEP-0260 | `"assisted"` → ASSISTED |
| 194 | `XEP0260_candidate_parse_direct` | XEP-0260 | `"direct"` → DIRECT |
| 195 | `XEP0260_candidate_parse_proxy` | XEP-0260 | `"proxy"` → PROXY |
| 196 | `XEP0260_candidate_parse_tunnel` | XEP-0260 | `"tunnel"` → TUNNEL |
| 197 | `XEP0260_candidate_parse_invalid_throws` | XEP-0260 | Unknown type → IqError |
| 198 | `XEP0260_type_preference_ordering` | XEP-0260 | direct > assisted > tunnel > proxy |
| 199 | `XEP0176_ice_type_host` | XEP-0176 | `"host"` → HOST |
| 200 | `XEP0176_ice_type_srflx` | XEP-0176 | `"srflx"` → SRFLX |
| 201 | `XEP0176_ice_type_relay` | XEP-0176 | `"relay"` → RELAY |
| 202 | `XEP0176_ice_type_prflx` | XEP-0176 | `"prflx"` → PRFLX |
| 203 | `XEP0176_ice_type_invalid_throws` | XEP-0176 | Unknown type → IqError |
| 204 | `XEP0394_span_emphasis_roundtrip` | XEP-0394 | EMPHASIS ↔ `"emphasis"` |
| 205 | `XEP0394_span_strong_roundtrip` | XEP-0394 | STRONG ↔ `"strong"` |
| 206 | `XEP0394_span_deleted_roundtrip` | XEP-0394 | DELETED ↔ `"deleted"` |
| 207 | `XEP0394_span_unknown_defaults_emphasis` | XEP-0394 | Unknown → EMPHASIS (silent default) |
| 208 | `XEP0082_parse_valid_iso8601` | XEP-0082 | Valid ISO 8601 → DateTime |
| 209 | `XEP0082_parse_invalid_returns_null` | XEP-0082 | Invalid string → null |
| 210 | `XEP0082_roundtrip` | XEP-0082 | format→parse roundtrip |

#### UtilAudit (9 Tests) -- UUID + Data URI

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 211 | `RFC4122_uuid_format_8_4_4_4_12` | RFC 4122 | Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| 212 | `RFC4122_uuid_version_nibble_is_4` | RFC 4122 S4.4 | Version nibble = `4` (20 samples) |
| 213 | `RFC4122_uuid_variant_bits` | RFC 4122 S4.1.1 | Variant nibble ∈ {8,9,a,b} (20 samples) |
| 214 | `RFC4122_uuid_uniqueness` | RFC 4122 | 100 UUIDs have no collisions |
| 215 | `RFC4122_uuid_lowercase_hex` | RFC 4122 | Lowercase hex characters |
| 216 | `DataURI_png_base64_parses` | RFC 2397 | `data:image/png;base64,...` → Bytes |
| 217 | `DataURI_unknown_scheme_returns_null` | RFC 2397 | Unknown scheme → null |
| 218 | `DataURI_jpeg_not_supported` | RFC 2397 | JPEG data URI → null (not implemented) |
| 219 | `DataURI_empty_data_returns_bytes` | RFC 2397 | Empty PNG data → empty Bytes |

#### XepRoundtripAudit (12 Tests) -- XEP Stanza Roundtrips

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 220 | `XEP0424_retract_v1_roundtrip` | XEP-0424 | set→get retract ID (v1) |
| 221 | `XEP0424_retract_direct_v1` | XEP-0424 | Direct `<retract>` v1 child |
| 222 | `XEP0424_retract_direct_v0` | XEP-0424 | Direct `<retract>` v0 child |
| 223 | `XEP0424_retract_no_retraction` | XEP-0424 | No retraction → null |
| 224 | `XEP0424_retract_missing_id` | XEP-0424 | Missing id attribute → null |
| 225 | `XEP0380_encryption_tag_roundtrip` | XEP-0380 | set→get encryption namespace |
| 226 | `XEP0380_encryption_tag_with_name` | XEP-0380 | Encryption with name attribute |
| 227 | `XEP0380_encryption_tag_missing` | XEP-0380 | No encryption → null |
| 228 | `XEP0359_origin_id_roundtrip` | XEP-0359 | set→get origin ID |
| 229 | `XEP0359_origin_id_missing` | XEP-0359 | No origin-id → null |
| 230 | `XEP0359_stanza_id_roundtrip` | XEP-0359 | stanza-id with matching `by` |
| 231 | `XEP0359_stanza_id_wrong_by` | XEP-0359 | stanza-id with wrong `by` → null |

#### Socks5Audit (14 Tests) -- XEP-0260 / RFC 1928 SOCKS5 Protocol Logic

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 232 | `XEP0260_dstaddr_sha1_deterministic` | XEP-0260 §4 | Same inputs → same SHA1 hash |
| 233 | `XEP0260_dstaddr_order_matters` | XEP-0260 §4 | Swapped JIDs → different hash |
| 234 | `XEP0260_dstaddr_is_sha1_hex_lowercase` | XEP-0260 §4 | Output is 40 lowercase hex chars |
| 235 | `XEP0260_dstaddr_different_sid_different_hash` | XEP-0260 §4 | Different SID → different hash |
| 236 | `RFC1928_bytes_equal_same` | RFC 1928 | Identical arrays → true |
| 237 | `RFC1928_bytes_equal_different_content` | RFC 1928 | Different content → false |
| 238 | `RFC1928_bytes_equal_different_length` | RFC 1928 | Different length → false |
| 239 | `RFC1928_bytes_equal_empty` | RFC 1928 | Two empty arrays → true |
| 240 | `XEP0260_candidate_type_roundtrip_all` | XEP-0260 | All 4 CandidateTypes roundtrip to_string/parse |
| 241 | `XEP0260_candidate_parse_xml_roundtrip` | XEP-0260 | XML → Candidate → to_xml preserves all attrs |
| 242 | `XEP0260_candidate_parse_missing_cid_throws` | XEP-0260 | Missing cid → IqError.BAD_REQUEST |
| 243 | `XEP0260_candidate_parse_default_type_direct` | XEP-0260 | Missing type → DIRECT |
| 244 | `XEP0260_candidate_parse_default_port_1080` | XEP-0260 | Missing port → 1080 |
| 245 | `XEP0260_candidate_priority_includes_type` | XEP-0260 | DIRECT priority > PROXY priority |

### 1.2 libdino (50 Tests)

**Target:** `libdino-test` -- `libdino/meson.build`

#### WeakMap (5 Tests) -- Data Structure Contract

| # | Test | Contract | Verifies |
|---|------|----------|----------|
| 1 | `CONTRACT1_set_and_get` | C-1 | map[k]=v -> has_key(k)==true, map[k]==v, size==1 |
| 2 | `CONTRACT2_set_replaces_value` | C-2 | Same key -> value replaced, size stays 1 |
| 3 | `CONTRACT5_mixed_live_dead_refs` | C-5 | Weak refs going out of scope -> automatically removed |
| 4 | `CONTRACT4_unset_removes_key` | C-4 | unset(k) -> size=0, is_empty=true, has_key=false |
| 5 | `CONTRACT3_auto_remove_on_scope_exit` | C-3 | Last strong ref gone -> has_key=false |

#### Jid (3 Tests) -- RFC 7622

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 6 | `RFC7622_parse_full_jid` | RFC 7622 S3.1 | "user@example.com/res" -> localpart, domainpart, resourcepart |
| 7 | `RFC7622_components_constructor` | RFC 7622 S3.1 | Component constructor = string parsing |
| 8 | `RFC7622_with_resource` | RFC 7622 S3.4 | Bare JID + resource -> full JID |

#### FileManager (1 Test) -- GIO Contract

| # | Test | Verifies |
|---|------|----------|
| 9 | `GIO_stream_close_lifecycle` | MemoryInputStream: !is_closed() -> close() -> is_closed() (regression #1764) |

#### Security (20 Tests) -- NIST/RFC Crypto

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 10 | `SP800_38D_ciphertext_length_equals_plaintext` | NIST SP 800-38D | Output = plaintext + 44 (SALT+IV+TAG) for multiple sizes |
| 11 | `SP800_38D_authentication_rejects_wrong_key` | NIST SP 800-38D | Wrong password -> exception |
| 12 | `SP800_38D_tag_is_128_bits` | NIST SP 800-38D | Bit-flip in tag -> rejection |
| 13 | `SP800_38D_iv_is_96_bits` | NIST SP 800-38D | IVs differ between encryptions |
| 14 | `SP800_38D_empty_plaintext_produces_only_overhead` | NIST SP 800-38D | Empty plaintext -> exactly 44 bytes |
| 15 | `RFC5116_ind_cpa_different_nonces` | RFC 5116 | IND-CPA: same plaintext -> different ciphertext |
| 16 | `RFC5116_ciphertext_not_plaintext` | RFC 5116 | Ciphertext does not contain plaintext as substring |
| 17 | `SP800_132_same_password_cross_instance_decrypt` | NIST SP 800-132 | Same password decrypts across instances |
| 18 | `SP800_132_unicode_password_roundtrip` | NIST SP 800-132 | Unicode passwords (emoji, CJK) work |
| 19 | `SP800_38D_reject_truncated_ciphertext` | NIST SP 800-38D | Truncated ciphertext -> exception |
| 20 | `SP800_38D_reject_corrupted_tag` | NIST SP 800-38D | Corrupted tag -> exception |
| 21 | `SP800_38D_large_plaintext_64KB_roundtrip` | NIST SP 800-38D | 65536-byte roundtrip |
| 22 | `SP800_38D_stream_encrypt_decrypt_roundtrip` | NIST SP 800-38D | Stream encrypt + decrypt roundtrip with tag holdback |
| 23 | `SP800_38D_stream_large_64KB_roundtrip` | NIST SP 800-38D | 64KB stream roundtrip (multi-block, multi-chunk) |
| 24 | `SP800_38D_stream_wrong_password_rejects` | NIST SP 800-38D | Stream decrypt with wrong password -> tag mismatch |

#### Audit (8 Tests) -- Security Audit

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 25 | `NIST_iterated_kdf_not_single_hash` | NIST SP 800-132 S5.2 | KDF uses iteration >= 10ms per derivation |
| 26 | `NIST_random_salt_per_encryption` | NIST SP 800-132 S5.1 | Each encryption gets its own 128-bit salt |
| 27 | `NIST_min_iterations_10000` | NIST SP 800-132 S5.2 | At least 10,000 PBKDF2 iterations |
| 28 | `SP800_90A_csprng_not_predictable_by_seed` | NIST SP 800-90A | Crypto.randomize() uses OS CSPRNG, not GLib.Random |
| 29 | `RFC4231_hmac_sha256_differs_from_plain_sha256` | RFC 4231 | HMAC(key,msg) != SHA256(msg) |
| 30 | `RFC8259_backslash_not_escaped_in_send_error` | RFC 8259 S7 | Backslash in error JSON properly escaped |
| 31 | `RFC8259_newline_not_escaped_in_send_error` | RFC 8259 S7 | Newline in JSON string escaped |
| 32 | `RFC8259_tab_not_escaped_in_send_error` | RFC 8259 S7 | Tab in JSON string escaped |

#### FileTransferAudit (8 Tests) -- Path Traversal

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 33 | `PathTraversal_dotdot_stripped` | CWE-22 | `../../etc/passwd` → `passwd` |
| 34 | `PathTraversal_absolute_path_stripped` | CWE-22 | `/etc/shadow` → `shadow` |
| 35 | `HiddenFile_dot_prefix_guarded` | CWE-22 | `.bashrc` → `_.bashrc` |
| 36 | `HiddenFile_dotdot_special` | CWE-22 | `..` not kept as-is |
| 37 | `Separator_only_becomes_unknown` | CWE-22 | `/` → `unknown filename` |
| 38 | `Dot_only_becomes_unknown` | CWE-22 | `.` → `unknown filename` |
| 39 | `Normal_filename_preserved` | Contract | `photo.jpg` preserved |
| 40 | `Filename_with_spaces_preserved` | Contract | `my photo.jpg` preserved |

#### SrtpAudit (10 Tests) -- RFC 3711 SRTP/SRTCP

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 41 | `RFC3711_session_initial_state` | RFC 3711 | New session: has_encrypt=false, has_decrypt=false |
| 42 | `RFC3711_session_has_encrypt_after_key` | RFC 3711 | set_encryption_key → has_encrypt=true |
| 43 | `RFC3711_session_has_decrypt_after_key` | RFC 3711 | set_decryption_key → has_decrypt=true |
| 44 | `RFC3711_rtp_encrypt_decrypt_roundtrip` | RFC 3711 S3.3 | Same key: encrypt_rtp → decrypt_rtp = original |
| 45 | `RFC3711_rtp_ciphertext_differs_from_plaintext` | RFC 3711 S3.3 | Payload must differ (IND-CPA) |
| 46 | `RFC3711_rtp_ciphertext_longer_than_plaintext` | RFC 3711 S3.3 | +10 bytes HMAC-SHA1-80 auth tag |
| 47 | `RFC3711_rtp_wrong_key_rejects` | RFC 3711 S3.3 | Wrong key → AUTHENTICATION_FAILED |
| 48 | `RFC3711_rtcp_encrypt_decrypt_roundtrip` | RFC 3711 S3.4 | SRTCP roundtrip with same key |
| 49 | `RFC3711_rtcp_wrong_key_rejects` | RFC 3711 S3.4 | SRTCP wrong key → AUTHENTICATION_FAILED |
| 50 | `RFC3711_force_reset_preserves_key` | RFC 3711 | force_reset_encrypt_stream re-applies key, roundtrip works |

### 1.3 OMEMO (102 Tests)

**Target:** `omemo-test` -- `plugins/omemo/meson.build`

#### Curve25519 (4 Tests) -- RFC 7748

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 1 | `RFC7748_agreement` | RFC 7748 | Curve25519 key agreement (DH) |
| 2 | `RFC7748_generate_public` | RFC 7748 | Public key generation from private |
| 3 | `RFC7748_random_agreements` | RFC 7748 | Random key agreements |
| 4 | `RFC7748_signature` | RFC 7748 | Signature verification |

#### SessionBuilder (5 Tests) -- Signal Protocol / XEP-0384

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 5 | `SignalProtocol_basic_pre_key_v2` | Signal Protocol | PreKey bundle V2 session |
| 6 | `SignalProtocol_basic_pre_key_v3` | Signal Protocol | PreKey bundle V3 session + double ratchet |
| 7 | `XEP0384_basic_pre_key_omemo` | XEP-0384 | OMEMO-specific PreKey session |
| 8 | `SignalProtocol_bad_signed_pre_key_signature` | Signal Protocol | Invalid signature -> rejection |
| 9 | `SignalProtocol_repeat_bundle_message_v2` | Signal Protocol | Repeated bundle -> correct session |

#### HKDF (1 Test) -- RFC 5869

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 10 | `RFC5869_vector_v3` | RFC 5869 | HKDF test vector |

#### FileDecryptor (20 Tests) -- RFC 4648 / XEP-0454 Security Audit

Security audit tests for OMEMO file decryptor helper functions.
Required `private` → `internal static` to enable testing via `--internal-vapi` + `-include omemo-internal.h`.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 11 | `RFC_is_hex_valid_lowercase` | Hex Contract | `0-9a-f` accepted |
| 12 | `RFC_is_hex_valid_uppercase` | Hex Contract | `A-F` accepted |
| 13 | `RFC_is_hex_valid_mixed` | Hex Contract | Mixed case accepted |
| 14 | `RFC_is_hex_empty_is_false` | Hex Contract | Empty string -> false |
| 15 | `RFC_is_hex_non_hex_char_false` | Hex Contract | Non-hex chars rejected |
| 16 | `RFC_is_hex_space_is_false` | Hex Contract | Spaces rejected |
| 17 | `RFC_is_hex_url_safe_base64_is_false` | Hex Contract | `-_` (URL-safe b64) rejected |
| 18 | `RFC_hex_to_bin_known_vector` | Hex Contract | `AABBCCDD` -> {0xAA,0xBB,0xCC,0xDD} |
| 19 | `RFC_hex_to_bin_empty` | Hex Contract | Empty -> empty array |
| 20 | `RFC_hex_to_bin_all_ff` | Hex Contract | `FFFF` -> {0xFF,0xFF} |
| 21 | `RFC_hex_to_bin_all_00` | Hex Contract | `0000` -> {0x00,0x00} |
| 22 | `RFC4648_normalize_base64_rem_0_unchanged` | RFC 4648 S4 | len%4==0 unchanged |
| 23 | `RFC4648_normalize_base64_rem_2_adds_double_pad` | RFC 4648 S4 | len%4==2 appends `==` |
| 24 | `RFC4648_normalize_base64_rem_3_adds_single_pad` | RFC 4648 S4 | len%4==3 appends `=` |
| 25 | `RFC4648_normalize_base64_rem_1_is_invalid` | RFC 4648 S3.5 | **Bug #15 FIXED**: len%4==1 returns `""` (was: returned malformed input) |
| 26 | `RFC4648_normalize_base64_url_safe_to_standard` | RFC 4648 S5 | `-`->`+`, `_`->`/` |
| 27 | `RFC4648_normalize_base64_empty_string` | RFC 4648 S4 | Empty -> empty |
| 28 | `XEP0454_aesgcm_to_https_strips_fragment` | XEP-0454 | `aesgcm://...#secret` -> `https://...` |
| 29 | `XEP0454_aesgcm_to_https_preserves_path` | XEP-0454 | Path + query preserved |
| 30 | `XEP0454_aesgcm_to_https_non_aesgcm_unchanged` | XEP-0454 | Non-aesgcm URL unchanged |

#### DecryptLogic (15 Tests) -- CWE-208 / Contract Security Audit

Security audit tests for OMEMO decrypt helper functions.
Required `private` → `internal static` to enable testing via `--internal-vapi` + `-include omemo-internal.h`.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 31 | `CWE208_equal_arrays_returns_true` | CWE-208 | Identical arrays → true |
| 32 | `CWE208_unequal_arrays_returns_false` | CWE-208 | Different arrays → false |
| 33 | `CWE208_different_length_returns_false` | CWE-208 | Length mismatch → false (early) |
| 34 | `CWE208_empty_arrays_returns_true` | CWE-208 | Empty arrays → true |
| 35 | `CWE208_single_byte_match` | CWE-208 | Single identical byte → true |
| 36 | `CWE208_single_byte_mismatch` | CWE-208 | Single different byte → false |
| 37 | `CWE208_all_zero_arrays_equal` | CWE-208 | All-zero arrays → true |
| 38 | `CWE208_one_bit_difference` | CWE-208 | 1-bit diff detected |
| 39 | `CWE208_first_byte_differs` | CWE-208 | First byte difference detected |
| 40 | `CWE208_last_byte_differs` | CWE-208 | Last byte difference detected |
| 41 | `CONTRACT_arr_to_str_ascii` | Contract | ASCII bytes → string |
| 42 | `CONTRACT_arr_to_str_empty` | Contract | Empty array → empty string |
| 43 | `CONTRACT_arr_to_str_embedded_nul` | Contract | Embedded NUL → truncation (C behavior) |
| 44 | `CONTRACT_arr_to_str_utf8_multibyte` | Contract | UTF-8 ä survives conversion |
| 45 | `CONTRACT_arr_to_str_single_byte` | Contract | Single byte → single char |

#### BundleParser (16 Tests) -- XEP-0384 v0.3 + v0.8 Security Audit

Bundle XML parser tests against untrusted input: null nodes, missing elements,
non-numeric IDs, missing keys/signatures.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 46 | `XEP0384v03_bundle_null_node_spk_id_minus1` | XEP-0384 v0.3 | Null node → spk_id -1 |
| 47 | `XEP0384v03_bundle_missing_spk_node` | XEP-0384 v0.3 | Missing signedPreKeyPublic → -1 |
| 48 | `XEP0384v03_bundle_valid_spk_id` | XEP-0384 v0.3 | signedPreKeyId=42 parsed correctly |
| 49 | `XEP0384v03_bundle_non_numeric_spk_id` | XEP-0384 v0.3 | int.parse("garbage") → 0 (FINDING: ambiguous with id=0) |
| 50 | `XEP0384v03_bundle_empty_prekeys` | XEP-0384 v0.3 | Missing prekeys → empty list |
| 51 | `XEP0384v03_bundle_prekey_id_parsed` | XEP-0384 v0.3 | PreKey id=7 parsed |
| 52 | `XEP0384v03_bundle_prekey_missing_id_skipped` | XEP-0384 v0.3 | Missing preKeyId → filtered out |
| 53 | `XEP0384v08_bundle_null_node_spk_id_minus1` | XEP-0384 v0.8 | Null node → spk_id -1 |
| 54 | `XEP0384v08_bundle_missing_spk_node` | XEP-0384 v0.8 | Missing spk → -1 |
| 55 | `XEP0384v08_bundle_valid_spk_id` | XEP-0384 v0.8 | spk id=99 parsed correctly |
| 56 | `XEP0384v08_bundle_non_numeric_spk_id` | XEP-0384 v0.8 | int.parse("not-a-number") → 0 |
| 57 | `XEP0384v08_bundle_empty_prekeys` | XEP-0384 v0.8 | Missing prekeys → empty list |
| 58 | `XEP0384v08_bundle_prekey_id_parsed` | XEP-0384 v0.8 | pk id=5 parsed |
| 59 | `XEP0384v08_bundle_prekey_no_id_skipped` | XEP-0384 v0.8 | pk without id → filtered out |
| 60 | `XEP0384v08_bundle_missing_sig_null` | XEP-0384 v0.8 | Missing spks → null signature |
| 61 | `XEP0384v08_bundle_missing_ik_null` | XEP-0384 v0.8 | Missing ik → null identity key |

#### Omemo2Crypto (12 Tests) -- XEP-0384 v0.8 Encrypt/Decrypt Pipeline

Security audit tests for the HKDF→AES-256-CBC→HMAC-SHA-256 pipeline.
Required extracting `omemo2_encrypt_payload()` and `omemo2_decrypt_payload()` as `internal static`.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 62 | `XEP0384v08_encrypt_decrypt_roundtrip` | XEP-0384 v0.8 S4 | Encrypt then decrypt recovers plaintext |
| 63 | `XEP0384v08_roundtrip_empty_plaintext` | XEP-0384 v0.8 S4 | Empty input roundtrips (PKCS7 pads to 16) |
| 64 | `XEP0384v08_roundtrip_large_plaintext` | XEP-0384 v0.8 S4 | 4KB plaintext roundtrip |
| 65 | `XEP0384v08_mk_with_tag_is_48_bytes` | XEP-0384 v0.8 S4 | mk_with_tag = 32 mk + 16 HMAC = 48 bytes |
| 66 | `XEP0384v08_ciphertext_padded_to_block` | XEP-0384 v0.8 S4 | AES-CBC ciphertext is multiple of 16 |
| 67 | `XEP0384v08_same_mk_same_plaintext_same_output` | XEP-0384 v0.8 | Deterministic: same mk → same ciphertext |
| 68 | `XEP0384v08_different_mk_different_ciphertext` | XEP-0384 v0.8 | Different mk → different ciphertext |
| 69 | `XEP0384v08_tampered_ciphertext_fails_hmac` | XEP-0384 v0.8 | Flipped ciphertext bit → HMAC reject |
| 70 | `XEP0384v08_tampered_tag_fails_hmac` | XEP-0384 v0.8 | Flipped auth_tag bit → HMAC reject |
| 71 | `XEP0384v08_truncated_mk_and_tag_rejected` | XEP-0384 v0.8 | mk_with_tag < 48 bytes → error |
| 72 | `XEP0384v08_single_byte_plaintext` | XEP-0384 v0.8 | 1 byte → 16 bytes ciphertext (PKCS7) |
| 73 | `XEP0384v08_exactly_16_byte_plaintext` | XEP-0384 v0.8 | 16 bytes → 32 bytes ciphertext (PKCS7 full block) |

#### SessionVersionGuard (3 Tests) -- XEP-0384 v1/v2 Guard

Tests for the session version detection that prevents v4 sessions in the v1 encryptor.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 74 | `XEP0384_v3_session_reports_version_3` | XEP-0384 | v3 session → cipher reports version 3, guard does not fire |
| 75 | `XEP0384_session_cipher_version_matches_record` | XEP-0384 | SessionCipher version == SessionRecord version |
| 76 | `XEP0384_no_session_version_zero` | XEP-0384 | No session → get_session_version throws SG_ERR_NO_SESSION |

#### PreKeyUpdateClassifier (6 Tests) -- Identity Key Change Detection (Bug #19)

**Target:** Extracted `internal static classify_prekey_update()` from `update_db_for_prekey()`.
**CWE-295/322:** Identity key change accepted without user confirmation.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 77 | `SEC_prekey_new_device` | CWE-295 | New device (device_exists=false) → INSERT_NEW |
| 78 | `SEC_prekey_new_device_null_key` | CWE-295 | Device exists, stored key null → INSERT_NEW |
| 79 | `SEC_prekey_same_key_no_change` | CWE-295 | Same identity key → NO_CHANGE |
| 80 | `SEC_prekey_key_changed` | CWE-295 | Different key → KEY_CHANGED (Bug #19: silent accept) |
| 81 | `SEC_prekey_key_changed_is_not_no_change` | CWE-295 | KEY_CHANGED must not be NO_CHANGE (regression guard) |
| 82 | `SEC_prekey_empty_vs_populated` | CWE-295 | Empty existing key vs real key → KEY_CHANGED |

#### EncryptSafetyCheck (8 Tests) -- Encrypt Error Body Validation

**Target:** Extracted `internal static is_encrypt_result_safe_to_send()` from `encrypt()`.
**CWE-311/319:** Plaintext or error body leak on encryption failure.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 83 | `SEC_encrypt_success_safe_to_send` | CWE-311 | encrypted=true + marker body → safe |
| 84 | `SEC_encrypt_failure_must_not_send` | CWE-311 | encrypted=false → NEVER safe |
| 85 | `SEC_encrypt_null_body_not_safe` | CWE-311 | null body → not safe |
| 86 | `SEC_encrypt_plaintext_leak_detected` | CWE-311 | body == original plaintext → catastrophic leak detected |
| 87 | `SEC_encrypt_error_body_not_safe` | CWE-311 | Error string body → not safe even if encrypted=true |
| 88 | `SEC_encrypt_success_null_original_ok` | CWE-311 | null original body + marker → safe |
| 89 | `SEC_encrypt_false_with_marker_not_safe` | CWE-311 | encrypted=false + marker body → still not safe |
| 90 | `SEC_encrypt_true_with_error_body_not_safe` | CWE-311 | encrypted=true + error body → inconsistent, not safe |

#### DecryptFailureStage (12 Tests) -- Ratchet Advance Detection

**Target:** Extracted `internal static classify_decrypt_failure_stage()` from decrypt path.
**CWE-755:** Inconsistent state when ratchet advances on partial success.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 91 | `SEC_stage_no_session_pre_ratchet` | CWE-755 | SG_ERR_NO_SESSION → PRE_RATCHET (safe to retry) |
| 92 | `SEC_stage_invalid_message_pre_ratchet` | CWE-755 | SG_ERR_INVALID_MESSAGE → PRE_RATCHET |
| 93 | `SEC_stage_legacy_message_pre_ratchet` | CWE-755 | SG_ERR_LEGACY_MESSAGE → PRE_RATCHET |
| 94 | `SEC_stage_deserialize_pre_ratchet` | CWE-755 | Deserialization error → PRE_RATCHET |
| 95 | `SEC_stage_db_update_failed_pre_ratchet` | CWE-755 | DB update failure → PRE_RATCHET |
| 96 | `SEC_stage_hmac_failed_post_ratchet` | CWE-755 | HMAC verification → POST_RATCHET (cannot retry) |
| 97 | `SEC_stage_aes_failed_post_ratchet` | CWE-755 | AES-256-CBC failure → POST_RATCHET |
| 98 | `SEC_stage_sce_parse_post_ratchet` | CWE-755 | SCE envelope parse → POST_RATCHET |
| 99 | `SEC_stage_key_too_short_post_ratchet` | CWE-755 | Key too short → POST_RATCHET |
| 100 | `SEC_stage_hkdf_failed_post_ratchet` | CWE-755 | HKDF failure → POST_RATCHET |
| 101 | `SEC_stage_hmac_compute_post_ratchet` | CWE-755 | HMAC computation failure → POST_RATCHET |
| 102 | `SEC_stage_unknown_error_assume_post` | CWE-755 | Unknown error → UNKNOWN_ASSUME_POST (conservative) |

### 1.4 Main / UI View Models (62 Tests)

**Target:** `main-test` -- `main/meson.build`

#### PreferencesRow (16 Tests) -- GObject Property/Signal Contract

Pure GObject view model classes (zero GTK dependency). First UI-layer tests in the project.

| # | Test | Contract | Verifies |
|---|------|----------|----------|
| 1 | `GObject_Text_title_roundtrip` | GObject property | title get/set round-trip |
| 2 | `GObject_Text_text_roundtrip` | GObject property | text get/set round-trip |
| 3 | `GObject_Text_media_type_nullable` | GObject property | Nullable media_type/media_uri, null accepted |
| 4 | `GObject_Entry_text_roundtrip` | GObject property | Entry text + title properties |
| 5 | `GObject_Entry_changed_signal_fires` | GObject signal | changed signal emits, multiple firings counted |
| 6 | `GObject_Entry_notify_on_text_change` | GObject notify | notify["text"] fires on property assignment |
| 7 | `GObject_PrivateText_text_roundtrip` | GObject property | PrivateText text round-trip |
| 8 | `GObject_PrivateText_changed_signal_fires` | GObject signal | changed signal emits |
| 9 | `GObject_Toggle_state_default_false` | GObject property | bool property defaults to false |
| 10 | `GObject_Toggle_state_roundtrip` | GObject property | true/false round-trip |
| 11 | `GObject_Toggle_subtitle_roundtrip` | GObject property | subtitle get/set |
| 12 | `GObject_ComboBox_items_list_operations` | Gee.ArrayList | add, size, indexer, remove_at |
| 13 | `GObject_ComboBox_active_item_roundtrip` | GObject property | active_item index round-trip |
| 14 | `GObject_Button_text_roundtrip` | GObject property | button_text get/set |
| 15 | `GObject_Button_clicked_signal_fires` | GObject signal | clicked fires, multiple clicks counted |
| 16 | `GObject_inheritance_all_subtypes_are_Any` | GObject type | Text, Entry, PrivateText, Toggle, ComboBox, Button are-a Any |

#### UiHelperAudit (46 Tests) -- Pure UI Helper Functions

Pure static functions from `helper.vala` (`Dino.Ui.Util` namespace) -- no GTK widgets needed.

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 17 | `XMPP_color_for_show_online` | RFC 6121 | "online" → #9CCC65 |
| 18 | `XMPP_color_for_show_away` | RFC 6121 | "away" → #FFCA28 |
| 19 | `XMPP_color_for_show_chat` | RFC 6121 | "chat" → #66BB6A |
| 20 | `XMPP_color_for_show_xa` | RFC 6121 | "xa" → #EF5350 |
| 21 | `XMPP_color_for_show_dnd` | RFC 6121 | "dnd" → #EF5350 |
| 22 | `XMPP_color_for_show_unknown_default` | RFC 6121 | unknown → #BDBDBD |
| 23 | `CONTRACT_rgba_to_hex_red` | Contract | {1,0,0,1} → #FF0000FF |
| 24 | `CONTRACT_rgba_to_hex_green` | Contract | {0,1,0,1} → #00FF00FF |
| 25 | `CONTRACT_rgba_to_hex_blue` | Contract | {0,0,1,1} → #0000FFFF |
| 26 | `CONTRACT_rgba_to_hex_white` | Contract | {1,1,1,1} → #FFFFFFFF |
| 27 | `CONTRACT_rgba_to_hex_transparent` | Contract | {0,0,0,0} → #00000000 |
| 28 | `CONTRACT_rgba_to_hex_clamp_overflow` | Contract | Values >1.0 / <0.0 clamped |
| 29 | `CONTRACT_is_24h_format_returns_true` | Contract | Hardcoded true |
| 30 | `CONTRACT_format_time_24h` | Contract | Uses 24h branch |
| 31 | `CONTRACT_format_time_uses_24h_branch` | Contract | Selects format_24h string |
| 32 | `RFC3986_url_regex_matches_https` | RFC 3986 | https:// matched |
| 33 | `RFC3986_url_regex_matches_http` | RFC 3986 | http:// with path matched |
| 34 | `RFC3986_url_regex_matches_xmpp` | RFC 3986 | xmpp: URI matched |
| 35 | `RFC3986_url_regex_matches_mailto` | RFC 3986 | mailto: URI matched |
| 36 | `RFC3986_url_regex_no_plain_text` | RFC 3986 | Plain text NOT matched |
| 37 | `RFC3986_url_regex_matches_ftp` | RFC 3986 | ftp:// matched |
| 38 | `RFC3986_url_regex_embedded_in_text` | RFC 3986 | URL extracted from prose |
| 39 | `CONTRACT_matching_chars_paren` | Contract | ) → ( |
| 40 | `CONTRACT_matching_chars_bracket` | Contract | ] → [ |
| 41 | `CONTRACT_matching_chars_brace` | Contract | } → { |
| 42 | `CONTRACT_summarize_ws_multiple_spaces` | Contract | Multiple spaces → single |
| 43 | `CONTRACT_summarize_ws_tabs` | Contract | Tab → space |
| 44 | `CONTRACT_summarize_ws_newlines` | Contract | Newline → space |
| 45 | `CONTRACT_summarize_ws_mixed` | Contract | Mixed whitespace → single space |
| 46 | `CONTRACT_summarize_ws_no_change` | Contract | Single space preserved |
| 47 | `CONTRACT_summarize_ws_empty` | Contract | Empty string → empty |
| 48 | `ICU_emoji_count_single` | ICU UAX #44 | Single emoji → 1 |
| 49 | `ICU_emoji_count_multiple` | ICU UAX #44 | Three emoji → 3 |
| 50 | `ICU_emoji_count_text_returns_neg1` | ICU UAX #44 | Plain text → -1 |
| 51 | `ICU_emoji_count_mixed_returns_neg1` | ICU UAX #44 | Text + emoji → -1 |
| 52 | `ICU_emoji_count_empty` | ICU UAX #44 | Empty → 0 |
| 53 | `ICU_emoji_count_zwj_sequence` | ICU UAX #44 | ZWJ family → 1 |
| 54 | `ICU_emoji_count_variation_selector` | ICU UAX #44 | VS16 keycap → 1 |
| 55 | `CONTRACT_markup_bold` | Contract | *word* → \<b\> |
| 56 | `CONTRACT_markup_italic` | Contract | _word_ → \<i\> |
| 57 | `CONTRACT_markup_code` | Contract | \`word\` → \<tt\> |
| 58 | `CONTRACT_markup_strikethrough` | Contract | ~word~ → \<s\> |
| 59 | `CONTRACT_markup_plain_no_change` | Contract | Plain text passes through |
| 60 | `CONTRACT_markup_link_detection` | Contract | URL → \<a href=\> |
| 61 | `CONTRACT_markup_highlight_word` | Contract | Highlight → \<b\> |
| 62 | `CONTRACT_markup_escape_entities` | CWE-79 | \<script\> escaped to &lt; |

### 1.5 OpenPGP (48 Tests)

**Target:** `openpgp-test` -- `plugins/openpgp/meson.build`

#### StreamModuleLogic (16 Tests) -- XEP-0373/0374 Security Audit

Security audit tests for OpenPGP stream_module helper functions.
Required `private static` → `internal static` to enable testing via `--internal-vapi` + `-include openpgp-internal.h`.
First test suite for the openpgp plugin (new test infrastructure).

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 1 | `XEP0374_extract_body_simple` | XEP-0374 S3 | Simple body extraction |
| 2 | `XEP0374_extract_body_with_namespace` | XEP-0374 S3 | Body with xmlns='jabber:client' |
| 3 | `XEP0374_extract_body_no_body_returns_null` | XEP-0374 | No body → null |
| 4 | `XEP0374_extract_body_empty_body` | XEP-0374 | Empty body → empty string |
| 5 | `XEP0374_extract_body_missing_close_tag` | XEP-0374 | Missing </body> → null |
| 6 | `XEP0374_extract_body_bodyguard_no_false_match` | XEP-0374 | **Bug #17 FIXED**: `<bodyguard>` no longer matches `<body>` |
| 7 | `XEP0374_extract_body_with_attributes` | XEP-0374 | Body with xml:lang + xmlns |
| 8 | `XEP0374_extract_body_xml_entities` | XEP-0374 | XML entities preserved |
| 9 | `XEP0374_extract_body_nested_elements` | XEP-0374 | Body nested in payload |
| 10 | `XEP0374_extract_body_full_signcrypt` | XEP-0374 S3 | Full spec example |
| 11 | `XEP0374_extract_pgp_data_normal_armor` | XEP-0374 | Normal ASCII armor extraction |
| 12 | `XEP0374_extract_pgp_data_crlf_headers` | XEP-0374 | CRLF line endings handled |
| 13 | `XEP0374_extract_pgp_data_no_headers_fallback` | XEP-0374 | No headers → base64 fallback (FINDING: double-encode) |
| 14 | `XEP0374_extract_pgp_data_missing_footer` | XEP-0374 | Missing END footer → rest of data |
| 15 | `XEP0374_extract_pgp_data_empty` | XEP-0374 | Empty input → base64 fallback |
| 16 | `XEP0374_extract_pgp_data_preserves_base64` | XEP-0374 | Base64 data preserved exactly |

#### GPGKeylistParser (16 Tests) -- `gpg_cli_helper.vala::parse_keylist_output()`

**Target:** Extracted `internal static parse_keylist_output()` from `get_keylist()`.
Parses GPG `--with-colons` output into `Key` objects (fpr, keyid, uid, email, flags).

| # | Test Name | Spec | Description |
|---|-----------|------|-------------|
| 17 | `GPG_keylist_empty_output` | GPG colons | Empty string → empty list |
| 18 | `GPG_keylist_single_pub_key` | GPG colons | pub+fpr+uid → 1 Key, fpr/keyid/uid/email correct |
| 19 | `GPG_keylist_single_sec_key` | GPG colons | sec+fpr+uid → Key.secret = true |
| 20 | `GPG_keylist_expired_key` | GPG colons | validity "e" → Key.expired = true |
| 21 | `GPG_keylist_revoked_key` | GPG colons | validity "r" → Key.revoked = true |
| 22 | `GPG_keylist_email_normal` | GPG colons | `<alice@example.com>` extracted from uid |
| 23 | `GPG_keylist_email_no_brackets` | GPG colons | No `<>` → email = null |
| 24 | `GPG_keylist_email_malformed_brackets` | GPG colons | `<no-at-sign>` → extracted verbatim |
| 25 | `GPG_keylist_fpr_to_keyid_40char` | GPG colons | Last 16 of 40-char fpr = keyid |
| 26 | `GPG_keylist_subkey_fpr_skipped` | GPG colons | fpr after ssb/sub → not used as main fpr |
| 27 | `GPG_keylist_multiple_keys` | GPG colons | Two pub blocks → 2 Key objects |
| 28 | `GPG_keylist_no_uid_not_added` | GPG colons | pub+fpr but no uid → key not in list |
| 29 | `GPG_keylist_no_fpr_not_added` | GPG colons | pub+uid but no fpr → key not in list |
| 30 | `GPG_keylist_malformed_line` | GPG colons | Short/garbage lines skipped |
| 31 | `GPG_keylist_only_first_uid` | GPG colons | Multiple uid lines → only first captured |
| 32 | `GPG_keylist_fpr_short` | GPG colons | fpr < 16 chars → keyid = fpr |

#### ArmorParser (16 Tests) -- `stream_module.vala::extract_signature/encrypted_from_armor()`

**Target:** Extracted `internal static extract_signature_from_armor()` and `extract_encrypted_from_armor()`.
**Bug #18 FIXED:** Fallback path used `begin_marker + 30` magic offset with unconditional `+2`,
extracting `----END PGP SIGNATURE-----` instead of base64 data.

| # | Test Name | Spec | Description |
|---|-----------|------|-------------|
| 33 | `XEP0027_sig_normal_armor` | XEP-0027 | Standard armor → base64 extracted |
| 34 | `XEP0027_sig_with_hash_header` | XEP-0027 | Hash: SHA256 header → skipped to base64 |
| 35 | `XEP0027_sig_multiline_base64` | XEP-0027 | Multi-line base64 → all lines joined |
| 36 | `XEP0027_sig_with_crc24` | XEP-0027 | CRC24 checksum line → included |
| 37 | `XEP0027_sig_no_begin` | XEP-0027 | Missing BEGIN → null |
| 38 | `XEP0027_sig_no_end` | XEP-0027 | Missing END → null |
| 39 | `XEP0027_sig_crlf` | XEP-0027 | CRLF line endings → normalized |
| 40 | `XEP0027_sig_fallback_no_blank_line` | XEP-0027 | No blank line separator → Bug #18 fix verified |
| 41 | `XEP0027_sig_empty_base64` | XEP-0027 | Empty base64 between headers → empty string |
| 42 | `XEP0027_enc_normal_armor` | XEP-0027 | Standard encrypted armor → base64 extracted |
| 43 | `XEP0027_enc_no_header` | XEP-0027 | Missing BEGIN → null |
| 44 | `XEP0027_enc_no_blank_line` | XEP-0027 | No blank line separator → null (no fallback) |
| 45 | `XEP0027_enc_no_footer` | XEP-0027 | Missing END → null |
| 46 | `XEP0027_enc_crlf` | XEP-0027 | CRLF line endings → normalized |
| 47 | `XEP0027_enc_multiline` | XEP-0027 | Multi-line base64 → all lines joined |
| 48 | `XEP0027_enc_with_version_header` | XEP-0027 | Version: header → skipped to base64 |

### 1.6 Bot-Features (24 Tests)

**Target:** `bot-features-test` -- `plugins/bot-features/meson.build`

#### RateLimiter (9 Tests) -- Contract-Based

| # | Test | Contract | Verifies |
|---|------|----------|----------|
| 1 | `CONTRACT1_allows_exactly_max_requests` | C-1 | Exactly max_requests allowed |
| 2 | `CONTRACT2_blocks_request_max_plus_one` | C-2 | (max+1)-th request blocked |
| 3 | `CONTRACT3_separate_keys_independent` | C-3 | Keys isolated from each other |
| 4 | `CONTRACT4_window_resets_after_expiry` | C-4 | Window expires -> quota reset |
| 5 | `CONTRACT5_retry_after_positive_when_blocked` | C-5 | retry_after > 0 and <= window |
| 6 | `CONTRACT5_retry_after_zero_unknown_key` | C-5 | Unknown key -> 0 |
| 7 | `CONTRACT6_cleanup_preserves_live_windows` | C-6 | Cleanup only removes stale entries |
| 8 | `CONTRACT7_window_seconds_clamped_to_1` | C-7 | window_seconds<=0 -> 1 (security) |
| 9 | `CONTRACT8_single_request_limit` | C-8 | max=1 -> 1 allowed, 2 blocked |

#### Crypto (8 Tests) -- FIPS/RFC

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 10 | `FIPS180_4_sha256_abc` | FIPS 180-4 SB.1 | SHA-256("abc") = ba7816bf... |
| 11 | `FIPS180_4_sha256_empty` | FIPS 180-4 | SHA-256("") = e3b0c442... |
| 12 | `FIPS180_4_sha256_multiblock` | FIPS 180-4 SB.2 | Multi-block 448-bit message |
| 13 | `FIPS180_4_sha256_digest_is_256_bits` | FIPS 180-4 S1 | Output = 64 hex characters (256 bits) |
| 14 | `RFC4231_case2_hmac_sha256` | RFC 4231 #2 | HMAC with key="Jefe" |
| 15 | `RFC4231_case3_hmac_sha256` | RFC 4231 #3 | HMAC with 0xaa*20 key, 0xdd*50 data |
| 16 | `SP800_63B_secret_min_128_bit_entropy` | NIST SP 800-63B | Webhook secret >= 128-bit entropy (64 hex chars) |
| 17 | `SP800_63B_secret_uniqueness_no_collision` | NIST SP 800-63B | Two secrets are unequal |

#### Audit RateLimiter (3 Tests) -- Security Audit

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 18 | `CONTRACT_zero_window_must_not_allow_unlimited` | Contract | window=0 clamped to 1, not unlimited |
| 19 | `CONTRACT_negative_max_must_block_all` | Contract | max<0 blocks all requests |
| 20 | `CONTRACT_int_overflow_in_cleanup_staleness` | Contract | int64 arithmetic prevents overflow in staleness |

#### Audit JSON Escape (4 Tests) -- RFC 8259

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 21 | `RFC8259_backslash_before_quote_produces_invalid_json` | RFC 8259 S7 | Backslash escaped before quote in JSON |
| 22 | `RFC8259_newline_raw_in_json_string` | RFC 8259 S7 | Raw newline escaped in JSON |
| 23 | `RFC8259_tab_raw_in_json_string` | RFC 8259 S7 | Raw tab escaped in JSON |
| 24 | `RFC8259_null_byte_in_description` | RFC 8259 S7 | Null byte handling in strings |

---

### 1.7 HTTP-Files (25 Tests)

**Target:** `http-files-test` -- `plugins/http-files/meson.build`

Tests the HTTP file upload/download plugin: URL recognition, filename extraction,
and log sanitization (secret stripping).

**Note:** Uses `_force_class_init(typeof(FileProvider))` to trigger GObject class
initialization for static Regex fields when linked via internal VAPI.

#### UrlRegex (13 Tests) -- XEP-0363 + OMEMO aesgcm://

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 1 | `XEP0363_http_url_accepts_https` | XEP-0363 | HTTPS upload URL recognized |
| 2 | `XEP0363_http_url_accepts_http` | XEP-0363 | HTTP upload URL recognized |
| 3 | `XEP0363_http_url_rejects_ftp_scheme` | XEP-0363 | Only http/https schemes valid |
| 4 | `RFC3986_rejects_spaces_in_url` | RFC 3986 §3.3 | Spaces invalid in URI path |
| 5 | `XEP0363_http_url_rejects_fragment` | XEP-0363 | Fragment breaks GET download |
| 6 | `CONTRACT_http_url_rejects_empty` | CONTRACT | Empty string rejected |
| 7 | `XEP0363_http_url_accepts_port_path` | XEP-0363 | URL with port and multi-segment path |
| 8 | `OMEMO_aesgcm_url_matches` | OMEMO | aesgcm:// with fragment recognized |
| 9 | `OMEMO_aesgcm_requires_fragment` | OMEMO | aesgcm:// without fragment rejected |
| 10 | `OMEMO_aesgcm_rejects_https_scheme` | OMEMO | https:// must not match omemo regex |
| 11 | `OMEMO_aesgcm_rejects_empty_fragment` | OMEMO | Empty fragment = no iv+key |
| 12 | `OMEMO_aesgcm_captures_host_and_secret` | OMEMO | Capture groups for host+path and secret |
| 13 | `RFC3986_aesgcm_rejects_spaces_in_fragment` | RFC 3986 §3.5 | Spaces in fragment corrupt iv+key |

#### FileNameExtraction (6 Tests) -- CONTRACT

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 14 | `CONTRACT_simple_https_url` | CONTRACT | Filename from simple HTTPS URL |
| 15 | `OMEMO_aesgcm_strips_fragment` | OMEMO | Fragment stripped before filename extraction |
| 16 | `RFC3986_url_decode_percent_encoding` | RFC 3986 | Percent-encoded characters decoded |
| 17 | `CONTRACT_deep_path_last_segment` | CONTRACT | Last path segment returned |
| 18 | `CONTRACT_trailing_slash_empty` | CONTRACT | Trailing slash gives empty name |
| 19 | `XEP0363_real_upload_url` | XEP-0363 | Real upload URL with port and hash path |

#### SanitizeLog (6 Tests) -- CONTRACT (Security)

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 20 | `CONTRACT_null_safe` | CONTRACT | null input returns "(null)" |
| 21 | `CONTRACT_strips_fragment_secret` | CONTRACT | Fragment (OMEMO key) replaced with "..." |
| 22 | `CONTRACT_preserves_url_without_fragment` | CONTRACT | Clean URL unchanged |
| 23 | `CONTRACT_truncates_oversized_url` | CONTRACT | URLs > 200 chars truncated |
| 24 | `CONTRACT_sender_strips_query_token` | CONTRACT | Query string (upload token) replaced with "..." |
| 25 | `CONTRACT_sender_null_safe` | CONTRACT | null input returns "(null)" |

---

## 2. DB Maintenance Tests (136 Standalone Tests)

### 2.1 Bash CLI Tests (71 Tests)

**Script:** `scripts/test_db_maintenance.sh`
**Requires:** `sqlcipher` in PATH

| Suite | Tests | Description |
|-------|-------|-------------|
| 1: Basic sqlcipher | ~15 | DB creation, key, tables, data |
| 2: Rekey | ~12 | Password change, old key rejected |
| 3: Multi-DB rekey | ~16 | All 4 DBs (dino, pgp, bot_registry, omemo) |
| 4: WAL checkpoint | ~12 | PRAGMA wal_checkpoint(TRUNCATE) |
| 5: Reset (unlink) | ~16 | File deletion + WAL/SHM + omemo.key |

### 2.2 Vala Integration Tests (65 Tests)

**Script:** `scripts/run_db_integration_tests.sh`
**Source:** `tests/test_db_maintenance_integration.vala`

| Suite | Tests | Description |
|-------|-------|-------------|
| 1: Change password | 20 | Validation, db.rekey(), plugin chain |
| 2: Reset database | 8 | FileUtils.unlink for all DBs |
| 3: Backup checkpoint | 10 | wal_checkpoint(TRUNCATE) |
| 4: E2E flow | 11 | Change PW -> checkpoint -> verification |
| 5: Edge cases | 9 | SQL injection, 1000-char PW, Unicode |
| 6: Plugin null-safety | 7 | if(db!=null) guards |

### Database Coverage

| Database | Key Source | Rekey | Reset | Checkpoint |
|----------|-----------|-------|-------|------------|
| `dino.db` | User password | YES | YES | YES |
| `pgp.db` | User password | YES | YES | YES |
| `bot_registry.db` | User password | YES | YES | YES |
| `omemo.db` | GNOME Keyring key | YES | YES | YES |

---

## 3. Ad-Hoc Tests

| File | Language | Purpose |
|------|----------|---------|
| `test_cb.vala` | Vala | TLS channel-binding enum availability |
| `test_omemo_deser.c` | C | OMEMO protobuf deserialization with Kaidan bytes |
| `test_socks.py` | Python | SOCKS5 proxy connectivity |

---

## 4. Specification References

Every test references its authoritative source:

| Spec | Area | Tests |
|------|------|-------|
| **RFC 4122** | UUID v4 format | 5 |
| **RFC 2397** | Data URI parsing | 4 |
| **RFC 6120** | XMPP Core (streams, stanzas, namespaces, bool attrs) | 10 |
| **RFC 7622** | XMPP JID format | 31 |
| **RFC 4231** | HMAC-SHA-256 test vectors | 3 |
| **RFC 4648** | Base64 encoding | 6 |
| **RFC 5116** | AEAD (IND-CPA) | 2 |
| **RFC 5869** | HKDF | 1 |
| **RFC 6350/6351** | vCard 4.0 / xCard XML | 2 |
| **RFC 7748** | Curve25519 elliptic curves | 4 |
| **RFC 8259** | JSON encoding (string escaping) | 7 |
| **NIST SP 800-38D** | AES-GCM authenticated encryption | 8 |
| **NIST SP 800-132** | PBKDF2 key derivation | 5 |
| **NIST SP 800-63B** | Secret entropy (128-bit minimum) | 2 |
| **NIST SP 800-90A** | CSPRNG (Crypto.randomize) | 2 |
| **NIST FIPS 180-4** | SHA-256 / SHA-1 hash vectors | 7 |
| **XML 1.0 S4** | Character references (&#xNN;, &amp;, etc.) | 9 |
| **CWE-22** | Path traversal prevention | 8 |
| **XEP-0082** | XMPP DateTime profiles (ISO 8601) | 3 |
| **XEP-0059** | Result Set Management | 1 |
| **XEP-0115** | Entity Capabilities (caps hash) | 5 |
| **XEP-0166** | Jingle (Senders + Role parse) | 9 |
| **XEP-0176** | ICE-UDP (candidate type parse) | 5 |
| **XEP-0198** | Stream Management | 15 |
| **XEP-0260** | SOCKS5 Bytestreams (candidate type) | 6 |
| **XEP-0300** | Cryptographic Hashes (roundtrip, Bug #21 fixed) | 15 |
| **XEP-0313** | Message Archive Management | 8 |
| **XEP-0359** | Unique Stable Stanza IDs | 4 |
| **XEP-0373** | OpenPGP for XMPP | 12 |
| **XEP-0374** | OpenPGP for XMPP Instant Messaging | 40 |
| **XEP-0380** | Explicit Encryption | 3 |
| **XEP-0384** | OMEMO encryption | 60 |
| **XEP-0392** | Consistent Color Generation | 3 |
| **XEP-0394** | Message Markup (span types) | 4 |
| **XEP-0424** | Message Retraction | 5 |
| **XEP-0448** | Encrypted File Sharing | 2 |
| **XEP-0454** | OMEMO Media Sharing | 3 |
| **Signal Protocol** | Double Ratchet, PreKeys | 5 |
| **Contract** | Data structure/API contracts (WeakMap, RateLimiter, arr_to_str, rgba_to_hex, ws, matching chars, markup) | 54 |
| **GObject** | Property/signal contract (PreferencesRow) | 16 |
| **RFC 3986** | URI syntax (URL regex detection) | 7 |
| **RFC 6121** | XMPP IM presence show values (color mapping) | 6 |
| **ICU UAX #44** | Unicode emoji properties (ZWJ, VS16, keycap) | 7 |
| **CWE-79** | XSS prevention (markup entity escaping) | 1 |
| **XSD** | xs:hexBinary parsing | 5 |
| **CWE-208** | Timing attack prevention (constant_time_compare) | 10 |

---

## 5. Test Architecture

```
ninja -C build test                    Meson-registered (556 tests)
  |-- xmpp-vala-test                   19 suites, 245 tests (GLib.Test)
  |     |-- Stanza (4)                   RFC 6120 S4 stream/namespace
  |     |-- util (5)                     xs:hexBinary parsing contract
  |     |-- Jid (28)                     RFC 7622 JID validation
  |     |-- color (3)                    XEP-0392 test vectors
  |     |-- VCard4 (2)                   RFC 6350/6351 xCard
  |     |-- Xep0448Test (2)              XEP-0448 ESFS
  |     |-- StreamManagement (12)        XEP-0198 S3-S6 + async XML
  |     |-- MAM (8)                      XEP-0313 S3-S5 + async XML
  |     |-- Audit_XEP0198 (3)            h-counter overflow
  |     |-- OmemoAudit (39)              XEP-0384 v0.3 + v0.8 stanza audit
  |     |-- OpenPgpAudit (36)            XEP-0373 + XEP-0374 stanza + rpad audit
  |     |-- StanzaEntryAudit (21)        XML entity decode + bool parse (Bug #20 fixed)
  |     |-- CryptoHashAudit (15)         XEP-0300 hash roundtrip + vectors (Bug #21 fixed)
  |     |-- EntityCapsAudit (5)          XEP-0115 caps hash verification
  |     |-- ProtocolParserAudit (27)     Jingle/SOCKS5/ICE/Markup/DateTime parsers
  |     |-- Socks5Audit (14)             XEP-0260/RFC 1928 SOCKS5 protocol logic
  |     |-- UtilAudit (9)               UUID format + Data URI parsing
  |     +-- XepRoundtripAudit (12)       XEP-0424/0380/0359 stanza roundtrips
  |
  |-- libdino-test                     9 suites, 50 tests (GLib.Test)
  |     |-- WeakMapTest (5)              Data structure contract
  |     |-- Jid (3)                      RFC 7622 basics
  |     |-- FileManagerTest (1)          GIO stream lifecycle
  |     |-- Security (15)                NIST SP 800-38D/132, RFC 5116
  |     |-- Audit_KeyDerivation (3)      NIST SP 800-132 KDF audit
  |     |-- Audit_KeyManager (1)         NIST SP 800-90A CSPRNG
  |     |-- Audit_TokenStorage (1)       RFC 4231 HMAC vs SHA-256
  |     |-- Audit_JSONInjection (3)      RFC 8259 JSON escape
  |     |-- FileTransferAudit (8)        CWE-22 path traversal
  |     +-- SrtpAudit (10)              RFC 3711 SRTP/SRTCP VoIP encryption
  |
  |-- main-test                        2 suites, 62 tests (GLib.Test)
  |     |-- PreferencesRow (16)          GObject property/signal contract
  |     +-- UiHelperAudit (46)           Pure helper.vala functions (no GTK)
  |
  |-- omemo-test                       11 suites, 102 tests (GLib.Test)
  |     |-- Curve25519 (4)               RFC 7748 key agreement
  |     |-- SessionBuilder (5)           Signal Protocol / XEP-0384
  |     |-- HKDF (1)                     RFC 5869 test vector
  |     |-- FileDecryptor (20)           RFC 4648 + XEP-0454 security audit
  |     |-- DecryptLogic (15)            CWE-208 constant-time + arr_to_str
  |     |-- BundleParser (16)            XEP-0384 v0.3 + v0.8 XML parser audit
  |     |-- Omemo2Crypto (12)            HKDF→AES→HMAC encrypt/decrypt roundtrip
  |     |-- SessionVersionGuard (3)      v3↔v4 session version detection
  |     |-- PreKeyUpdateClassifier (6)   Pre-key change detection
  |     |-- EncryptSafetyCheck (8)       Plaintext-leak guard, safety checks
  |     +-- DecryptFailureStage (12)     Pre/post-ratchet error classification
  |
  |-- openpgp-test                     3 suites, 48 tests (GLib.Test)
  |     |-- StreamModuleLogic (16)       XEP-0374 extract_body + extract_pgp_data
  |     |-- GPGKeylistParser (16)        GPG --with-colons keylist parser
  |     +-- ArmorParser (16)             XEP-0027 signature/encrypted armor parser
  |
  +-- bot-features-test                4 suites, 24 tests (GLib.Test)
  |     |-- RateLimiter (9)              Contract-based (C-1 to C-8)
  |     |-- Crypto (8)                   FIPS 180-4, RFC 4231
  |     |-- Audit_RateLimiter (3)        CONTRACT audit (zero-window, negative-max, overflow)
  |     +-- Audit_JSONEscape (4)         RFC 8259 JSON audit
  |
  +-- http-files-test                  3 suites, 25 tests (GLib.Test)
        |-- UrlRegex (13)                XEP-0363 + OMEMO aesgcm:// URL recognition
        |-- FileNameExtraction (6)       CONTRACT filename from URL path
        +-- SanitizeLog (6)              CONTRACT secret stripping for logs

scripts/test_db_maintenance.sh         Bash CLI, 71 tests
scripts/run_db_integration_tests.sh    Vala, 65 tests (Qlite)
```

---

## 6. What Is NOT Tested (Gaps)

Full gap analysis with UI file inventory, accessibility status, and prioritized
future test ideas: see `docs/internal/TESTING_GAPS.md` (not tracked in Git).

### 6.3 Partially Tested Components

| Area | Status | Difficulty |
|------|--------|------------|
| **qlite** (SQLite ORM) | Only indirectly via DB tests | Medium -- pure library, testable |
| **crypto-vala** | Fully tested: Cipher/Converter/Random/Error via libdino Security (15) + Audit (4), `srtp.vala` via SrtpAudit (10) in §1.2. Bug in `force_reset_encrypt_stream` found and fixed. | ~~Low~~ Done |
| **http-files plugin** | 25 tests (UrlRegex, FileNameExtraction, SanitizeLog) -- fully tested, see §1.7 | ~~Medium~~ Done |
| **openpgp plugin** | 48 tests (StreamModuleLogic, GPGKeylistParser, ArmorParser) + 36 OpenPgpAudit tests in xmpp-vala (XEP-0373/0374 stanza + rpad). GPG binary integration (keygen, sign, encrypt subprocess): untested | Medium |
| **omemo plugin** | 102 tests (11 suites): Curve25519, SessionBuilder, HKDF, FileDecryptor, DecryptLogic, BundleParser, Omemo2Crypto, SessionVersionGuard, PreKeyUpdateClassifier, EncryptSafetyCheck, DecryptFailureStage. Encrypt/decrypt roundtrip, safety checks, error classification fully tested. | ~~Medium~~ Done |

---

## 7. CI Pipeline

| Workflow | Trigger | Tests |
|----------|---------|-------|
| `build.yml` | push, PR | `meson test` (556 tests) |
| `build.yml` (Vala nightly) | push, PR | `meson test` (556 tests) |
| `build-flatpak.yml` | push | Build only |
| `build-appimage.yml` | Tag | Build only |
| `windows-build.yml` | push | Build only |

**Gap:** DB tests (136) do not run in CI.

---

## 8. Run All Tests

Script: `scripts/run_all_tests.sh`

```bash
# All 692 tests (Meson + DB)
./scripts/run_all_tests.sh

# Only Meson-registered tests (556)
./scripts/run_all_tests.sh --meson

# Only DB maintenance tests (136)
./scripts/run_all_tests.sh --db

# Help
./scripts/run_all_tests.sh --help
```

Output includes color-coded results per suite, date/branch/commit header, and exit code 0 (all pass) or 1 (any fail).

If `sqlcipher` is not installed, DB CLI tests are skipped with a warning.

---

## 9. Evaluating Test Results

### Meson Summary Output

```
1/7 Tests for http-files OK              0.03s
2/7 Tests for xmpp-vala  OK              0.08s
3/7 Tests for main       OK              0.09s
4/7 Tests for openpgp    OK              0.06s
5/7 Tests for omemo      OK              0.32s
6/7 bot-features-test    OK              2.21s
7/7 Tests for libdino    OK             11.10s

Ok:                 7
Expected Fail:      0
Fail:               0        <-- MUST be 0
Unexpected Pass:    0
Skipped:            0
Timeout:            0
```

| Field | Meaning |
|-------|---------|
| **Ok** | Suites that passed all their tests |
| **Fail** | Suites with at least one failing test -- investigate immediately |
| **Timeout** | Suite took too long (default: 30s) -- may indicate infinite loop |
| **Skipped** | Suite was skipped (missing dependency) |

### TAP Output (single-binary run)

```
TAP version 13
1..16
ok 1 /PreferencesRow/GObject_Text_title_roundtrip
ok 2 /PreferencesRow/GObject_Text_text_roundtrip
not ok 3 /PreferencesRow/GObject_Text_media_type_nullable   <-- FAILURE
# GLib.Test message: media_type should default to null
```

| Output | Meaning |
|--------|---------|
| `ok N /path/name` | Test passed |
| `not ok N /path/name` | Test **FAILED** |
| Lines starting with `#` after `not ok` | Failure message with spec violation |
| `1..N` | Total test count declared |

### When a Test Fails

1. Read the failure message -- it names the spec violation
2. The test name prefix tells you which spec: `RFC7622_` = JID format, `SP800_38D_` = AES-GCM, etc.
3. Look up the spec section referenced in the test's doc comment
4. Fix the code to match the spec, not the other way around
5. Re-run: `ninja -C build test`

**Rule: Tests must find bugs. Never change a test to make it pass -- fix the code.**

### Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | All tests passed |
| 1 | At least one test failed |
| 77 | Test was skipped |
| 99 | Hard error (segfault, build failure) |

### Build Log Location

After `meson test`, full logs are in: `build/meson-logs/testlog.txt`

---

## 10. Writing New Tests

### Spec-Based Test (Gee.TestCase)

```vala
/**
 * Spec reference: XEP-XXXX SY
 * What is verified: [description]
 */
class MySpecTest : Gee.TestCase {
    public MySpecTest() {
        base("MySpec");
        add_test("XEP_XXXX_requirement_name", test_requirement);
        add_async_test("XEP_XXXX_parse_xml", (cb) => { test_parse.begin(cb); });
    }

    private void test_requirement() {
        // Test against spec requirement, not code behavior
        fail_if(result != expected, "XEP-XXXX SY: [requirement]");
    }

    private async void test_parse(Gee.TestFinishedCallback cb) {
        try {
            // Parse real XML, do not build StanzaNode manually
            var reader = new StanzaReader.for_string("<element xmlns='...'>..</element>");
            var node = yield reader.read_node();
            fail_if_not_eq_str(node.ns_uri, "expected_ns");
        } catch (Error e) {
            fail_if_reached("Parse error: " + e.message);
        }
        cb();
    }
}
```

### Registration in `common.vala`

```vala
GLib.Test.init(ref args);
TestSuite.get_root().add_suite(new MySpecTest().get_suite());
GLib.Test.run();
```

### Naming Convention

```
{SPEC}_{what_is_tested}

Examples:
  RFC7622_valid_bare_jid           -- RFC 7622: valid bare JID parses
  SP800_38D_tag_is_128_bits        -- NIST SP 800-38D: GCM tag length
  CONTRACT3_keys_independent       -- Contract #3: keys isolated
  GObject_Entry_changed_signal     -- GObject signal: Entry.changed
  RFC8259_newline_raw_in_json      -- RFC 8259 S7: JSON string escaping
```

### Golden Rules

1. **Tests must find bugs**, not follow code
2. **Every test name carries its spec** (RFC, XEP, NIST, CONTRACT, GObject)
3. **Parse real XML** via StanzaReader, not StanzaNode roundtrips
4. **Async tests** with `add_async_test()` + `Gee.TestFinishedCallback`
5. **Error messages** name the spec violation
6. **Never change a test to make it pass** -- fix the code

---

*Last updated: 24 February 2026 -- v1.7.0.0, 556 Meson + 136 standalone = 692 tests, 0 failures, OMEMO coverage updated (11 suites, 102 tests), stale counts fixed*
