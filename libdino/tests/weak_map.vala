using Dino.Entities;

namespace Dino.Test {

    /**
     * Contract tests for WeakMap<K,V> — a map that holds weak references.
     *
     * WeakMap contract:
     *   CONTRACT-1: set stores value, has_key returns true, [] retrieves it
     *   CONTRACT-2: set with existing key replaces value (size stays 1)
     *   CONTRACT-3: Values that go out of scope are automatically removed
     *   CONTRACT-4: unset removes the key, size/is_empty update accordingly
     *   CONTRACT-5: Combination of live and dead references is consistent
     */
    class WeakMapTest : Gee.TestCase {

        public WeakMapTest() {
            base("WeakMapTest");
            add_test("CONTRACT1_set_and_get", test_set);
            add_test("CONTRACT2_set_replaces_value", test_set2);
            add_test("CONTRACT5_mixed_live_dead_refs", test_set3);
            add_test("CONTRACT4_unset_removes_key", test_unset);
            add_test("CONTRACT3_auto_remove_on_scope_exit", test_remove_when_out_of_scope);
        }

        /**
         * CONTRACT-1: After map[k] = v, map.has_key(k) == true,
         * map[k] == v, map.size == 1.
         */
        private void test_set() {
            WeakMap<int, Object> map = new WeakMap<int, Object>();
            var o = new Object();
            map[1] = o;

            assert(map.size == 1);
            assert(map.has_key(1));
            assert(map[1] == o);
        }

        /**
         * CONTRACT-2: Setting the same key twice replaces the value.
         * Size MUST remain 1, and the new value is returned.
         */
        private void test_set2() {
            WeakMap<int, Object> map = new WeakMap<int, Object>();
            var o = new Object();
            var o2 = new Object();
            map[1] = o;
            map[1] = o2;

            assert(map.size == 1);
            assert(map.has_key(1));
            assert(map[1] == o2);
        }

        /**
         * CONTRACT-5: When objects go out of scope (weak refs die),
         * size MUST reflect only live references.
         * Keys with dead values are auto-removed.
         */
        private void test_set3() {
            WeakMap<int, Object> map = new WeakMap<int, Object>();

            var o1 = new Object();
            var o2 = new Object();

            map[0] = o1;
            map[3] = o2;

            {
                // o3, o4 die when leaving this scope
                var o3 = new Object();
                var o4 = new Object();
                map[7] = o3;
                map[50] = o4;
            }

            var o5 = new Object();
            map[5] = o5;

            // Only o1 (key 0), o2 (key 3), o5 (key 5) are alive
            assert(map.size == 3);

            assert(map.has_key(0));
            assert(map.has_key(3));
            assert(map.has_key(5));

            assert(map[0] == o1);
            assert(map[3] == o2);
            assert(map[5] == o5);
        }

        /**
         * CONTRACT-4: unset(k) removes the key.
         * After unset, size == 0, is_empty == true, has_key(k) == false.
         */
        private void test_unset() {
            WeakMap<int, Object> map = new WeakMap<int, Object>();
            var o1 = new Object();
            map[7] = o1;
            map.unset(7);

            assert_true(map.size == 0);
            assert_true(map.is_empty);
            assert_false(map.has_key(7));

        }

        /**
         * CONTRACT-3: When the last strong reference to a value goes
         * out of scope, the weak reference dies and has_key returns false.
         */
        private void test_remove_when_out_of_scope() {
            WeakMap<int, Object> map = new WeakMap<int, Object>();

            {
                map[0] = new Object();
            }

            assert_false(map.has_key(0));
        }
    }

}
