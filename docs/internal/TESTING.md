# DinoX -- Testing Guide

Complete inventory of all automated tests in the DinoX project.
Every test references its authoritative specification or contract.

**Status: v1.1.4.0 -- 241 Meson tests + 136 standalone tests = 377 automated tests, 0 failures**

---

## Quick Start

```bash
# All tests at once (recommended)
./scripts/run_all_tests.sh

# Only Meson-registered tests (5 suites, 241 tests)
./scripts/run_all_tests.sh --meson

# Only DB maintenance tests (136 standalone)
./scripts/run_all_tests.sh --db
```

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
build/xmpp-vala/xmpp-vala-test     # 142 tests
build/libdino/libdino-test          # 29 tests
build/main/main-test                # 16 tests
build/plugins/omemo/omemo-test      # 30 tests
build/plugins/bot-features/bot-features-test  # 24 tests
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
build/plugins/bot-features/bot-features-test -l
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

## 1. Meson-Registered Tests (241 Tests)

Compiled and executed via `ninja -C build test`.
Framework: GLib.Test + `Gee.TestCase` with `add_async_test()` for async XML parsing.

### 1.1 xmpp-vala (142 Tests)

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

### 1.2 libdino (29 Tests)

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

#### Security (12 Tests) -- NIST/RFC Crypto

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

#### Audit (8 Tests) -- Security Audit

| # | Test | Spec | Verifies |
|---|------|------|----------|
| 22 | `NIST_iterated_kdf_not_single_hash` | NIST SP 800-132 S5.2 | KDF uses iteration >= 10ms per derivation |
| 23 | `NIST_random_salt_per_encryption` | NIST SP 800-132 S5.1 | Each encryption gets its own 128-bit salt |
| 24 | `NIST_min_iterations_10000` | NIST SP 800-132 S5.2 | At least 10,000 PBKDF2 iterations |
| 25 | `SP800_90A_csprng_not_predictable_by_seed` | NIST SP 800-90A | Crypto.randomize() uses OS CSPRNG, not GLib.Random |
| 26 | `RFC4231_hmac_sha256_differs_from_plain_sha256` | RFC 4231 | HMAC(key,msg) != SHA256(msg) |
| 27 | `RFC8259_backslash_not_escaped_in_send_error` | RFC 8259 S7 | Backslash in error JSON properly escaped |
| 28 | `RFC8259_newline_not_escaped_in_send_error` | RFC 8259 S7 | Newline in JSON string escaped |
| 29 | `RFC8259_tab_not_escaped_in_send_error` | RFC 8259 S7 | Tab in JSON string escaped |

### 1.3 OMEMO (30 Tests)

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

### 1.4 Main / UI View Models (16 Tests)

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

### 1.5 Bot-Features (24 Tests)

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
| **RFC 6120** | XMPP Core (streams, stanzas, namespaces) | 4 |
| **RFC 7622** | XMPP JID format | 31 |
| **RFC 4231** | HMAC-SHA-256 test vectors | 3 |\n| **RFC 4648** | Base64 encoding | 6 |
| **RFC 5116** | AEAD (IND-CPA) | 2 |
| **RFC 5869** | HKDF | 1 |
| **RFC 6350/6351** | vCard 4.0 / xCard XML | 2 |
| **RFC 7748** | Curve25519 elliptic curves | 4 |
| **RFC 8259** | JSON encoding (string escaping) | 7 |
| **NIST SP 800-38D** | AES-GCM authenticated encryption | 8 |
| **NIST SP 800-132** | PBKDF2 key derivation | 5 |
| **NIST SP 800-63B** | Secret entropy (128-bit minimum) | 2 |
| **NIST SP 800-90A** | CSPRNG (Crypto.randomize) | 2 |
| **FIPS 180-4** | SHA-256 | 4 |
| **XEP-0059** | Result Set Management | 1 |
| **XEP-0198** | Stream Management | 15 |
| **XEP-0313** | Message Archive Management | 8 |
| **XEP-0373** | OpenPGP for XMPP | 6 |
| **XEP-0374** | OpenPGP for XMPP Instant Messaging | 30 |
| **XEP-0384** | OMEMO encryption | 42 |
| **XEP-0392** | Consistent Color Generation | 3 |
| **XEP-0448** | Encrypted File Sharing | 2 |
| **XEP-0454** | OMEMO Media Sharing | 3 |
| **Signal Protocol** | Double Ratchet, PreKeys | 5 |
| **Contract** | Data structure/API contracts (WeakMap, RateLimiter) | 17 |
| **GObject** | Property/signal contract (PreferencesRow) | 16 |
| **XSD** | xs:hexBinary parsing | 5 |
| **GIO** | Stream lifecycle | 1 |

---

## 5. Test Architecture

```
ninja -C build test                    Meson-registered (241 tests)
  |-- xmpp-vala-test                   12 suites, 142 tests (GLib.Test)
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
  |     +-- OpenPgpAudit (36)            XEP-0373 + XEP-0374 stanza + rpad audit
  |
  |-- libdino-test                     8 suites, 29 tests (GLib.Test)
  |     |-- WeakMapTest (5)              Data structure contract
  |     |-- Jid (3)                      RFC 7622 basics
  |     |-- FileManagerTest (1)          GIO stream lifecycle
  |     |-- Security (12)                NIST SP 800-38D/132, RFC 5116
  |     |-- Audit_KeyDerivation (3)      NIST SP 800-132 KDF audit
  |     |-- Audit_KeyManager (1)         NIST SP 800-90A CSPRNG
  |     |-- Audit_TokenStorage (1)       RFC 4231 HMAC vs SHA-256
  |     +-- Audit_JSONInjection (3)      RFC 8259 JSON escape
  |
  |-- main-test                        1 suite, 16 tests (GLib.Test)
  |     +-- PreferencesRow (16)          GObject property/signal contract
  |
  |-- omemo-test                       4 suites, 30 tests (GLib.Test)
  |     |-- Curve25519 (4)               RFC 7748 key agreement
  |     |-- SessionBuilder (5)           Signal Protocol / XEP-0384
  |     |-- HKDF (1)                     RFC 5869 test vector
  |     +-- FileDecryptor (20)           RFC 4648 + XEP-0454 security audit
  |
  +-- bot-features-test                4 suites, 24 tests (GLib.Test)
        |-- RateLimiter (9)              Contract-based (C-1 to C-8)
        |-- Crypto (8)                   FIPS 180-4, RFC 4231
        |-- Audit_RateLimiter (3)        CONTRACT audit (zero-window, negative-max, overflow)
        +-- Audit_JSONEscape (4)         RFC 8259 JSON audit

scripts/test_db_maintenance.sh         Bash CLI, 71 tests
scripts/run_db_integration_tests.sh    Vala, 65 tests (Qlite)
```

---

## 6. What Is NOT Tested (Gaps)

### 6.1 UI/GTK -- Mostly Untested

**16 of 92 UI files** have automated tests (PreferencesRow view model).

| Area | Files | Status |
|------|-------|--------|
| **View models** | 4 files | `preferences_row.vala`: 16 tests (section 1.4). Others: NONE |
| **Main window** | `main_window.vala`, `main_window_controller.vala` | NONE |
| **Chat input** | 13 files (text_view, encryption, sticker, smiley, audio/video recorder) | NONE |
| **Conversation view** | 22 files (message, file, call, quote, reactions, URL preview, video, audio) | NONE |
| **Conversation list** | 2 files (selector, row) | NONE |
| **Title bar** | 4 files (call, menu, occupants, search) | NONE |
| **Add contact** | 12 files (add_contact, add_conference, roster, room_browser, user_search) | NONE |
| **Call window** | 10 files (call_window, bottom_bar, dialpad, participant_list, audio/video settings) | NONE |
| **Bot management** | 2 files (bot_create_dialog, bot_manager_dialog) | NONE |
| **Settings** | 10 files (preferences, account, add_account, change_password, encryption) | NONE |
| **Widgets** | 4 files (avatar, date_separator, fixed_ratio_picture, natural_size_increase) | NONE |
| **UI templates** | 40 .ui files | NONE |

### 6.2 Accessibility -- NO Tests

- No ATK/AT-SPI tests
- No `accessible-role`, `accessible-label` checks
- No screen reader compatibility tests

### 6.3 Other Gaps

| Area | Status | Difficulty |
|------|--------|------------|
| **qlite** (SQLite ORM) | Only indirectly via DB tests | Medium -- pure library, testable |
| **crypto-vala** | No dedicated suite -- tested via libdino Security | Low |
| **http-files plugin** | No tests | Medium |
| **ice plugin** | No tests | High -- ICE/STUN/TURN networking |
| **notification-sound plugin** | No tests | Low -- pure GStreamer pipeline |
| **openpgp plugin** | Stanza tests via xmpp-vala (36 tests). Plugin logic: No tests | Medium |\n| **omemo plugin** | 30 tests (Curve25519, Signal, HKDF, FileDecryptor). Encrypt/decrypt logic: No tests | Medium |
| **rtp plugin** | No tests | High -- real-time media |
| **tor-manager plugin** | No tests | Medium -- SOCKS5 proxy |
| **Network/protocol integration** | No mock XMPP server | High |
| **App startup** (`main.vala`) | Untested | High -- requires full GTK/D-Bus |
| **Translations** | `check_translations.py` exists, not in CI | Low |

### 6.4 What COULD Be Tested (Prioritized)

#### Priority 1: View Model Tests (testable WITHOUT GTK)

The view models contain business logic without GTK dependency:

| File | What can be tested |
|------|--------------------|
| `conversation_details.vala` | Sorter logic: `compare()` must return correct ordering |
| `preferences_dialog.vala` | Account selection model, active accounts list |
| ~~`preferences_row.vala`~~ | ~~Row data binding~~ -- **DONE** (16 tests, section 1.4) |
| `account_details.vala` | Account data transformation |

#### Priority 2: UI Logic Tests (with Gtk.init() but without display)

| Component | What can be tested |
|-----------|--------------------|
| `smiley_converter.vala` | Text-to-emoji conversion: `:)` to smiley |
| `occupants_tab_completer.vala` | Tab completion logic |
| `chat_text_view.vala` | Text processing before send |
| `url_preview_widget.vala` | URL detection and validation |
| `file_metadata_providers.vala` | MIME type detection |

#### Priority 3: Widget Unit Tests (requires headless GTK)

| Widget | Spec | What can be tested |
|--------|------|--------------------|
| `AvatarPicture` | -- | Fallback initials computation |
| `DateSeparator` | i18n | Date formatting |
| `FixedRatioPicture` | -- | Aspect ratio calculation |
| `ConversationRow` | -- | Timestamp formatting, unread badge |

#### Priority 4: Spec-Based UI Tests (complex)

| What | Spec | How |
|------|------|-----|
| Password dialog | NIST SP 800-63B | Password validation: minimum length, entropy |
| OMEMO fingerprint display | XEP-0384 S5 | Fingerprint format (8x4 hex) |
| Encryption button | XEP-0384 | Encryption indicator correct |
| JID input field | RFC 7622 | Input validation |
| Contact details | RFC 6350 | vCard fields displayed correctly |

#### Priority 5: Screenshot/Visual Regression (complex)

- GTK Broadway backend for headless rendering
- Pixmap comparison against reference screenshots
- Required for theme compatibility

---

## 7. CI Pipeline

| Workflow | Trigger | Tests |
|----------|---------|-------|
| `build.yml` | push, PR | `meson test` (217 tests) |
| `build.yml` (Vala nightly) | push, PR | `meson test` (217 tests) |
| `build-flatpak.yml` | push | Build only |
| `build-appimage.yml` | Tag | Build only |
| `windows-build.yml` | push | Build only |

**Gap:** DB tests (136) do not run in CI.

---

## 8. Run All Tests

Script: `scripts/run_all_tests.sh`

```bash
# All 377 tests (Meson + DB)
./scripts/run_all_tests.sh

# Only Meson-registered tests (241)
./scripts/run_all_tests.sh --meson

# Only DB maintenance tests (136)
./scripts/run_all_tests.sh --db

# Help
./scripts/run_all_tests.sh --help
```

Output includes color-coded results per suite, date/branch/commit header, and exit code 0 (all pass) or 1 (any fail).

If `sqlcipher` is not installed, DB CLI tests are skipped with a warning.

---

## 9. Evaluating Test Results (Auswertung)

### Meson Summary Output

```
1/5 Tests for main      OK              0.01s
2/5 Tests for xmpp-vala OK              0.03s
3/5 Tests for omemo     OK              0.27s
4/5 bot-features-test   OK              2.21s
5/5 Tests for libdino   OK              9.68s

Ok:                 5
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

*Last updated: 23 February 2026 -- v1.1.4.0, 241 Meson tests (all spec-prefixed), 5 suites, 0 failures*
