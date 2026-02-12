using Xmpp.Util;

namespace Dino.Plugins.Omemo {

public static string fingerprint_from_base64(string b64) {
    uint8[] arr = Base64.decode(b64);

    arr = arr[1:arr.length];
    string s = "";
    foreach (uint8 i in arr) {
        string tmp = i.to_string("%x");
        if (tmp.length == 1) tmp = "0" + tmp;
        s = s + tmp;
    }

    return s;
}

public static string fingerprint_markup(string s) {
    // XEP-0384 §8: 8 groups of 8 lowercase hex chars,
    // each colored per XEP-0392 (Consistent Color Generation)
    string markup = "<span font_family='monospace' font='9'>";
    for (int i = 0; i < s.length && i < 64; i += 8) {
        int remaining = int.min(8, s.length - i);
        string group = s.substring(i, remaining).down();
        uint8[] rgb = Xmpp.Xep.ConsistentColor.string_to_rgb(group);
        string color = "#%02x%02x%02x".printf(rgb[0], rgb[1], rgb[2]);
        if (i > 0) {
            markup += (i == 32) ? "\n" : "\u00a0";
        }
        markup += @"<span foreground='$(color)'>$(group)</span>";
    }
    markup += "</span>";
    return markup;
}

public static string format_fingerprint(string s) {
    // Plain text: 8 groups of 8 lowercase hex chars
    string result = "";
    for (int i = 0; i < s.length && i < 64; i += 8) {
        int remaining = int.min(8, s.length - i);
        string group = s.substring(i, remaining).down();
        if (i > 0) {
            result += (i == 32) ? "\n" : " ";
        }
        result += group;
    }
    return result;
}

}
