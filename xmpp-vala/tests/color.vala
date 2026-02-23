using Xmpp.Xep;

namespace Xmpp.Test {

/**
 * Spec-based tests for XEP-0392 Consistent Color Generation.
 *
 * References:
 *   - XEP-0392 §5: Test Vectors (angle and RGB)
 *   - XEP-0392 §3: Algorithm (SHA-1 → uint16 → angle → HSLuv → RGB)
 */
class ColorTest : Gee.TestCase {

    public ColorTest() {
        base("color");

        add_test("XEP0392_angle_test_vectors", () => { test_xep_vectors_angle(); });
        add_test("XEP0392_rgbf_test_vectors", () => { test_xep_vectors_rgbf(); });
        add_test("XEP0392_rgb_angle_range_0_360", () => { test_rgb_angle_range(); });
    }

    /**
     * XEP-0392 §5 Test Vectors: angle values for known inputs.
     * These are the official test vectors from the XEP.
     */
    public void test_xep_vectors_angle() {
        fail_if_not_eq_double(ConsistentColor.string_to_angle("Romeo"), 327.255249);
        fail_if_not_eq_double(ConsistentColor.string_to_angle("juliet@capulet.lit"), 209.410400);
        fail_if_not_eq_double(ConsistentColor.string_to_angle("😺"), 331.199341);
        fail_if_not_eq_double(ConsistentColor.string_to_angle("council"), 359.994507);
        fail_if_not_eq_double(ConsistentColor.string_to_angle("Board"), 171.430664);
    }

    private bool fail_if_not_eq_rgbf(float[] left, float[] right) {
        bool failed = false;
        for (int i = 0; i < 3; i++) {
            failed = fail_if_not_eq_float(left[i], right[i]) || failed;
        }
        return failed;
    }

    /**
     * XEP-0392 §5 Test Vectors: RGB float values for known inputs.
     */
    public void test_xep_vectors_rgbf() {
        fail_if_not_eq_rgbf(ConsistentColor.string_to_rgbf("Romeo"), {0.865f,0.000f,0.686f});
        fail_if_not_eq_rgbf(ConsistentColor.string_to_rgbf("juliet@capulet.lit"), {0.000f,0.515f,0.573f});
        fail_if_not_eq_rgbf(ConsistentColor.string_to_rgbf("😺"), {0.872f,0.000f,0.659f});
        fail_if_not_eq_rgbf(ConsistentColor.string_to_rgbf("council"), {0.918f,0.000f,0.394f});
        fail_if_not_eq_rgbf(ConsistentColor.string_to_rgbf("Board"), {0.000f,0.527f,0.457f});
    }

    /**
     * XEP-0392 §3: The angle MUST be in range [0, 360).
     * Algorithm: angle = (uint16_le / 65536.0) × 360.0
     * Since uint16 ∈ [0, 65535], angle ∈ [0, 359.9945...).
     *
     * RGB values from HSLuv SHOULD be in [0, 1] per the color model.
     * NOTE: HSLuv can produce values like -2.9e-13 due to IEEE 754
     * floating-point arithmetic. We allow ±1e-10 tolerance.
     */
    public void test_rgb_angle_range() {
        string[] inputs = {
            "e57373", "f06292", "ba68c8", "9575cd", "7986cb", "64b5f6",
            "4fc3f7", "4dd0e1", "4db6ac", "81c784", "aed581", "dce775",
            "fff176", "ffd54f", "ffb74d", "ff8a65",
            "Romeo", "juliet@capulet.lit", "😺", "", "a", "zzzzzz"
        };
        foreach (string input in inputs) {
            float angle = ConsistentColor.string_to_angle(input);
            // XEP-0392 §3: angle = (uint16 / 65536) × 360 → [0, 360)
            fail_if(angle < 0.0f, @"Angle for '$input' must be ≥ 0, got $angle");
            fail_if(angle >= 360.0f, @"Angle for '$input' must be < 360, got $angle");

            // Verify RGB components are in valid range (allow IEEE 754 epsilon)
            float[] rgb = ConsistentColor.string_to_rgbf(input);
            for (int i = 0; i < 3; i++) {
                fail_if(rgb[i] < -1e-10f || rgb[i] > 1.0f + 1e-10f,
                    @"RGB[$i] for '$input' out of valid range: $(rgb[i])");
            }
        }
    }

}

}
