/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Gdk;
using Gtk;
using Pango;

namespace Dino.Ui {

    /**
     * Data extracted from a web page's OpenGraph / HTML meta tags.
     */
    public class UrlPreviewData : Object {
        public string url { get; set; }
        public string? site_name { get; set; }
        public string? title { get; set; }
        public string? description { get; set; }
        public string? image_url { get; set; }
        public Gdk.Texture? image_texture { get; set; default = null; }
        public bool failed { get; set; default = false; }
    }

    /**
     * Static cache + fetcher for URL preview metadata.
     *
     * Keeps results in memory so scrolling / re-rendering does not re-fetch.
     */
    public class UrlPreviewCache : Object {
        private static UrlPreviewCache? _instance;
        public static UrlPreviewCache get_instance() {
            if (_instance == null) _instance = new UrlPreviewCache();
            return _instance;
        }

        /* url -> preview data (including "failed" entries) */
        private HashMap<string, UrlPreviewData> cache = new HashMap<string, UrlPreviewData>();
        /* urls currently being fetched */
        private HashSet<string> in_flight = new HashSet<string>();

        public signal void preview_ready(string url, UrlPreviewData data);

        public UrlPreviewData? lookup(string url) {
            if (cache.has_key(url)) return cache[url];
            return null;
        }

        /**
         * Start an async fetch for the given URL if not already cached / in-flight.
         * When done, the preview_ready signal fires.
         */
        public void fetch(string url) {
            if (cache.has_key(url) || in_flight.contains(url)) return;
            in_flight.add(url);
            fetch_async.begin(url);
        }

        private async void fetch_async(string url) {
            var data = new UrlPreviewData();
            data.url = url;

            try {
                var session = new Soup.Session();
                session.user_agent = "Mozilla/5.0 (compatible; DinoX/1.0)";
                session.timeout = 10;
                var msg = new Soup.Message("GET", url);

                // Only accept HTML content
                msg.request_headers.append("Accept", "text/html");

                Bytes bytes = yield session.send_and_read_async(msg, Priority.DEFAULT, null);

                if (msg.status_code < 200 || msg.status_code >= 400) {
                    data.failed = true;
                } else {
                    // Check content type - only parse HTML
                    string? content_type = msg.response_headers.get_content_type(null);
                    if (content_type == null || !content_type.has_prefix("text/html")) {
                        data.failed = true;
                    } else {
                        // Detect charset from Content-Type header, convert to UTF-8 if needed
                        string? charset = null;
                        HashTable<string, string>? ct_params = null;
                        msg.response_headers.get_content_type(out ct_params);
                        if (ct_params != null) {
                            charset = ct_params.lookup("charset");
                        }

                        string html;
                        if (charset != null && charset.down() != "utf-8" && charset.down() != "utf8") {
                            try {
                                html = GLib.convert((string) bytes.get_data(), (ssize_t) bytes.get_size(), "UTF-8", charset);
                            } catch (ConvertError ce) {
                                debug("URL preview charset convert failed (%s→UTF-8): %s", charset, ce.message);
                                html = ((string) bytes.get_data()).make_valid();
                            }
                        } else {
                            html = ((string) bytes.get_data()).make_valid();
                        }

                        if (html != null && html.length > 0) {
                            parse_html_meta(html, data, url);
                        } else {
                            data.failed = true;
                        }
                    }
                }
            } catch (Error e) {
                debug("URL preview fetch failed for %s: %s", url, e.message);
                data.failed = true;
            }

            // If we got an image URL, try to download it
            if (!data.failed && data.image_url != null) {
                yield fetch_image(data);
            }

            cache[url] = data;
            in_flight.remove(url);
            preview_ready(url, data);
        }

        private async void fetch_image(UrlPreviewData data) {
            try {
                var session = new Soup.Session();
                session.user_agent = "Mozilla/5.0 (compatible; DinoX/1.0)";
                session.timeout = 10;
                var msg = new Soup.Message("GET", data.image_url);
                Bytes bytes = yield session.send_and_read_async(msg, Priority.DEFAULT, null);

                if (msg.status_code >= 200 && msg.status_code < 400 && bytes != null && bytes.get_size() > 0) {
                    var stream = new MemoryInputStream.from_bytes(bytes);
                    var pixbuf = new Gdk.Pixbuf.from_stream(stream);
                    if (pixbuf != null) {
                        // Scale down if too large (max 300px wide, 200px tall)
                        int w = pixbuf.width;
                        int h = pixbuf.height;
                        int max_w = 300;
                        int max_h = 200;
                        if (w > max_w || h > max_h) {
                            double scale = double.min((double) max_w / w, (double) max_h / h);
                            int new_w = (int)(w * scale);
                            int new_h = (int)(h * scale);
                            pixbuf = pixbuf.scale_simple(new_w, new_h, Gdk.InterpType.BILINEAR);
                        }
                        data.image_texture = Gdk.Texture.for_pixbuf(pixbuf);
                    }
                }
            } catch (Error e) {
                debug("URL preview image fetch failed: %s", e.message);
                // Not fatal - just show preview without image
            }
        }

        /**
         * Parse OpenGraph and standard HTML meta tags from raw HTML.
         */
        private void parse_html_meta(string html, UrlPreviewData data, string page_url) {
            // Limit parsing to <head> section (or first 32KB)
            string head_html = html;
            int head_end = html.index_of("</head>");
            if (head_end < 0) head_end = html.index_of("</HEAD>");
            if (head_end > 0) {
                head_html = html.substring(0, head_end);
            } else if (html.length > 32768) {
                head_html = html.substring(0, 32768);
            }

            // og:title
            data.title = extract_meta_content(head_html, "og:title");
            // og:description
            data.description = extract_meta_content(head_html, "og:description");
            // og:site_name
            data.site_name = extract_meta_content(head_html, "og:site_name");
            // og:image
            data.image_url = extract_meta_content(head_html, "og:image");

            // Fallback: <title>
            if (data.title == null || data.title == "") {
                data.title = extract_tag_content(head_html, "title");
            }
            // Fallback: <meta name="description">
            if (data.description == null || data.description == "") {
                data.description = extract_meta_name_content(head_html, "description");
            }

            // Make relative image URL absolute
            if (data.image_url != null && data.image_url != "" && !data.image_url.has_prefix("http")) {
                if (data.image_url.has_prefix("//")) {
                    // Protocol-relative
                    string scheme = "https";
                    if (page_url.has_prefix("http://")) scheme = "http";
                    data.image_url = scheme + ":" + data.image_url;
                } else if (data.image_url.has_prefix("/")) {
                    // Absolute path
                    try {
                        var uri = GLib.Uri.parse(page_url, GLib.UriFlags.NONE);
                        data.image_url = "%s://%s%s".printf(uri.get_scheme(), uri.get_host(), data.image_url);
                    } catch (Error e) {
                        data.image_url = null;
                    }
                }
            }

            // If no title at all, mark as failed
            if (data.title == null || data.title.strip() == "") {
                data.failed = true;
            }

            // Truncate very long text
            if (data.title != null && data.title.length > 200) {
                data.title = data.title.substring(0, 197) + "...";
            }
            if (data.description != null && data.description.length > 300) {
                data.description = data.description.substring(0, 297) + "...";
            }

            // Decode HTML entities
            if (data.title != null) data.title = decode_html_entities(data.title);
            if (data.description != null) data.description = decode_html_entities(data.description);
            if (data.site_name != null) data.site_name = decode_html_entities(data.site_name);
        }

        /**
         * Extract content from <meta property="name" content="...">
         */
        private string? extract_meta_content(string html, string property) {
            // Match both property= and name= variants, both single and double quotes
            // <meta property="og:title" content="Hello World">
            // <meta content="Hello World" property="og:title">
            string lower = html.down();
            string prop_lower = property.down();

            // Find the meta tag containing our property
            int pos = 0;
            while (true) {
                int meta_start = lower.index_of("<meta", pos);
                if (meta_start < 0) break;
                int meta_end = lower.index_of(">", meta_start);
                if (meta_end < 0) break;

                string tag = html.substring(meta_start, meta_end - meta_start + 1);
                string tag_lower = tag.down();

                // Check if this meta tag has our property
                bool has_prop = false;
                if (tag_lower.contains("property=\"" + prop_lower + "\"") ||
                    tag_lower.contains("property='" + prop_lower + "'")) {
                    has_prop = true;
                }

                if (has_prop) {
                    return extract_attribute(tag, "content");
                }

                pos = meta_end + 1;
            }
            return null;
        }

        /**
         * Extract content from <meta name="description" content="...">
         */
        private string? extract_meta_name_content(string html, string name) {
            string lower = html.down();
            string name_lower = name.down();

            int pos = 0;
            while (true) {
                int meta_start = lower.index_of("<meta", pos);
                if (meta_start < 0) break;
                int meta_end = lower.index_of(">", meta_start);
                if (meta_end < 0) break;

                string tag = html.substring(meta_start, meta_end - meta_start + 1);
                string tag_lower = tag.down();

                if (tag_lower.contains("name=\"" + name_lower + "\"") ||
                    tag_lower.contains("name='" + name_lower + "'")) {
                    return extract_attribute(tag, "content");
                }

                pos = meta_end + 1;
            }
            return null;
        }

        /**
         * Extract an attribute value from an HTML tag string.
         */
        private string? extract_attribute(string tag, string attr) {
            string lower = tag.down();
            string search_dq = attr.down() + "=\"";
            string search_sq = attr.down() + "='";

            int idx = lower.index_of(search_dq);
            if (idx >= 0) {
                int start = idx + search_dq.length;
                int end = tag.index_of("\"", start);
                if (end > start) return tag.substring(start, end - start);
            }

            idx = lower.index_of(search_sq);
            if (idx >= 0) {
                int start = idx + search_sq.length;
                int end = tag.index_of("'", start);
                if (end > start) return tag.substring(start, end - start);
            }
            return null;
        }

        /**
         * Extract text content between <tag> and </tag>.
         */
        private string? extract_tag_content(string html, string tag_name) {
            string lower = html.down();
            int start = lower.index_of("<" + tag_name.down());
            if (start < 0) return null;
            int content_start = lower.index_of(">", start);
            if (content_start < 0) return null;
            content_start++;
            int end = lower.index_of("</" + tag_name.down() + ">", content_start);
            if (end < 0) return null;
            if (end <= content_start) return null;
            return html.substring(content_start, end - content_start).strip();
        }

        /**
         * Decode common HTML entities.
         */
        private string decode_html_entities(string text) {
            string result = text;
            result = result.replace("&amp;", "&");
            result = result.replace("&lt;", "<");
            result = result.replace("&gt;", ">");
            result = result.replace("&quot;", "\"");
            result = result.replace("&#39;", "'");
            result = result.replace("&apos;", "'");
            result = result.replace("&#x27;", "'");
            result = result.replace("&ndash;", "\u2013");
            result = result.replace("&mdash;", "\u2014");
            result = result.replace("&nbsp;", " ");
            result = result.replace("&#8211;", "\u2013");
            result = result.replace("&#8212;", "\u2014");
            // Decode numeric entities &#NNN;
            try {
                var regex = new Regex("&#(\\d+);");
                result = regex.replace_eval(result, -1, 0, 0, (match_info, sb) => {
                    string num_str = match_info.fetch(1);
                    int code = int.parse(num_str);
                    if (code > 0 && code < 0x10FFFF) {
                        unichar uc = (unichar) code;
                        char buf[6];
                        int len = uc.to_utf8((string) buf);
                        sb.append(((string) buf).substring(0, len));
                    }
                    return false;
                });
            } catch (RegexError e) {
                // ignore
            }
            return result;
        }
    }

    /**
     * Widget that displays a URL link preview card.
     *
     * Layout:
     * +-------------------------------------------------------+
     * | [Image]  Site Name                                     |
     * |          Title (bold)                                  |
     * |          Description text...                           |
     * +-------------------------------------------------------+
     */
    public class UrlPreviewWidget : Box {

        private string url;
        private ulong ready_handler_id = 0;

        private Box card_box;
        private Picture? image_widget = null;
        private Label? site_label = null;
        private Label? title_label = null;
        private Label? desc_label = null;

        public UrlPreviewWidget(string url) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.url = url;
            this.halign = Align.START;
            this.hexpand = false;
            this.margin_top = 4;

            // Check cache first
            var cache = UrlPreviewCache.get_instance();
            var data = cache.lookup(url);

            if (data != null) {
                if (!data.failed) {
                    build_card(data);
                }
                // If failed, widget stays empty (invisible)
                return;
            }

            // Not cached yet - start fetch and listen for result
            ready_handler_id = cache.preview_ready.connect((ready_url, ready_data) => {
                if (ready_url == this.url) {
                    if (!ready_data.failed) {
                        build_card(ready_data);
                    }
                    // Disconnect after we got our result
                    if (ready_handler_id != 0) {
                        cache.disconnect(ready_handler_id);
                        ready_handler_id = 0;
                    }
                }
            });
            cache.fetch(url);
        }

        private void build_card(UrlPreviewData data) {
            card_box = new Box(Orientation.HORIZONTAL, 8);
            card_box.add_css_class("dino-link-preview");
            card_box.halign = Align.START;
            card_box.hexpand = false;
            // Don't use width_request (sets MINIMUM width, not max).
            // Instead, constrain via max_width_chars on labels.

            // Image on the left (if available)
            if (data.image_texture != null) {
                image_widget = new Picture();
                image_widget.set_paintable(data.image_texture);
                image_widget.content_fit = ContentFit.COVER;
                image_widget.can_shrink = true;
                image_widget.set_size_request(80, 80);
                image_widget.width_request = 80;
                image_widget.height_request = 80;
                image_widget.add_css_class("dino-link-preview-image");
                image_widget.overflow = Overflow.HIDDEN;
                card_box.append(image_widget);
            }

            // Text column on the right
            var text_box = new Box(Orientation.VERTICAL, 2);
            text_box.hexpand = true;
            text_box.valign = Align.CENTER;

            // Site name
            if (data.site_name != null && data.site_name.strip() != "") {
                site_label = new Label(data.site_name.strip());
                site_label.add_css_class("dim-label");
                site_label.halign = Align.START;
                site_label.xalign = 0;
                site_label.ellipsize = Pango.EllipsizeMode.END;
                site_label.max_width_chars = 50;
                var attrs = new Pango.AttrList();
                attrs.insert(Pango.attr_scale_new(0.85));
                site_label.set_attributes(attrs);
                text_box.append(site_label);
            } else {
                // Use domain as site name
                try {
                    var uri = GLib.Uri.parse(url, GLib.UriFlags.NONE);
                    string? host = uri.get_host();
                    if (host != null && host != "") {
                        site_label = new Label(host);
                        site_label.add_css_class("dim-label");
                        site_label.halign = Align.START;
                        site_label.xalign = 0;
                        site_label.ellipsize = Pango.EllipsizeMode.END;
                        var attrs = new Pango.AttrList();
                        attrs.insert(Pango.attr_scale_new(0.85));
                        site_label.set_attributes(attrs);
                        text_box.append(site_label);
                    }
                } catch (Error e) {
                    // ignore
                }
            }

            // Title
            if (data.title != null && data.title.strip() != "") {
                title_label = new Label(data.title.strip());
                title_label.halign = Align.START;
                title_label.xalign = 0;
                title_label.wrap = true;
                title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
                title_label.max_width_chars = 50;
                title_label.lines = 2;
                title_label.ellipsize = Pango.EllipsizeMode.END;
                var attrs = new Pango.AttrList();
                attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
                title_label.set_attributes(attrs);
                text_box.append(title_label);
            }

            // Description
            if (data.description != null && data.description.strip() != "") {
                desc_label = new Label(data.description.strip());
                desc_label.halign = Align.START;
                desc_label.xalign = 0;
                desc_label.wrap = true;
                desc_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
                desc_label.max_width_chars = 50;
                desc_label.lines = 3;
                desc_label.ellipsize = Pango.EllipsizeMode.END;
                desc_label.add_css_class("dim-label");
                text_box.append(desc_label);
            }

            card_box.append(text_box);
            this.append(card_box);

            // Make clickable -> open in browser
            var gesture = new GestureClick();
            gesture.pressed.connect(() => {
                var launcher = new Gtk.UriLauncher(this.url);
                launcher.launch.begin(null, null, (obj, res) => {
                    try {
                        launcher.launch.end(res);
                    } catch (Error e) {
                        warning("Failed to open URL: %s", e.message);
                    }
                });
            });
            card_box.add_controller(gesture);
            card_box.set_cursor(new Gdk.Cursor.from_name("pointer", null));
        }

        public override void dispose() {
            if (ready_handler_id != 0) {
                UrlPreviewCache.get_instance().disconnect(ready_handler_id);
                ready_handler_id = 0;
            }
            base.dispose();
        }
    }

    /**
     * Extract the first http/https URL from a message body, if any.
     * Returns null if none found or if it's a special URL (aesgcm, geo, etc.)
     */
    public string? extract_preview_url(string? body) {
        if (body == null || body.length == 0) return null;

        try {
            Regex url_regex = Dino.Ui.Util.get_url_regex();
            MatchInfo match;
            url_regex.match(body, 0, out match);
            while (match.matches()) {
                string url = match.fetch(0);
                // Only preview http:// and https:// URLs
                if (url.has_prefix("http://") || url.has_prefix("https://")) {
                    // Skip aesgcm (OMEMO file transfer)
                    if (url.contains("aesgcm")) {
                        match.next();
                        continue;
                    }
                    return url;
                }
                match.next();
            }
        } catch (Error e) {
            debug("URL extraction error: %s", e.message);
        }
        return null;
    }
}
