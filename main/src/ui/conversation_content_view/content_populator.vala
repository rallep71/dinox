/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Gtk;

using Xmpp;
using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class ContentProvider : ContentItemCollection, Object {

    private StreamInteractor stream_interactor;
    private Conversation? current_conversation;
    private Plugins.ConversationItemCollection? item_collection;

    public ContentProvider(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void init(Plugins.ConversationItemCollection item_collection, Conversation conversation, Plugins.WidgetType type) {
        if (current_conversation != null) {
            stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).uninit(current_conversation, this);
        }
        current_conversation = conversation;
        this.item_collection = item_collection;
        stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).init(conversation, this);
    }

    public void insert_item(ContentItem item) {
        var meta_item = create_content_meta_item(item);
        if (meta_item != null) {
            item_collection.insert_item(meta_item);
        }
    }

    public void remove_item(ContentItem item) { }


    public Gee.List<ContentMetaItem> populate_latest(Conversation conversation, int n) {
        Gee.List<ContentItem> items = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_n_latest(conversation, n);
        Gee.List<ContentMetaItem> ret = new ArrayList<ContentMetaItem>();
        foreach (ContentItem item in items) {
            var meta_item = create_content_meta_item(item);
            if (meta_item != null) {
                ret.add(meta_item);
            }
        }
        return ret;
    }

    public Gee.List<ContentMetaItem> populate_before(Conversation conversation, ContentItem before_item, int n) {
        Gee.List<ContentMetaItem> ret = new ArrayList<ContentMetaItem>();
        Gee.List<ContentItem> items = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_before(conversation, before_item, n);
        foreach (ContentItem item in items) {
            var meta_item = create_content_meta_item(item);
            if (meta_item != null) {
                ret.add(meta_item);
            }
        }
        return ret;
    }

    public Gee.List<ContentMetaItem> populate_after(Conversation conversation, ContentItem after_item, int n) {
        Gee.List<ContentMetaItem> ret = new ArrayList<ContentMetaItem>();
        Gee.List<ContentItem> items = stream_interactor.get_module<ContentItemStore>(ContentItemStore.IDENTITY).get_after(conversation, after_item, n);
        foreach (ContentItem item in items) {
            var meta_item = create_content_meta_item(item);
            if (meta_item != null) {
                ret.add(meta_item);
            }
        }
        return ret;
    }

    public ContentMetaItem? get_content_meta_item(ContentItem content_item) {
        return create_content_meta_item(content_item);
    }

    private ContentMetaItem? create_content_meta_item(ContentItem content_item) {
        if (content_item.type_ == MessageItem.TYPE) {
            return new MessageMetaItem(content_item, stream_interactor);
        } else if (content_item.type_ == FileItem.TYPE) {
            FileItem file_item = (FileItem) content_item;
            if (file_item.file_transfer == null) {
                return new FileMetaItem(content_item, stream_interactor);
            }
            string? mime_type = file_item.file_transfer.mime_type;
            // If mime_type is missing or generic (e.g. from encrypted on-disk storage),
            // try to guess from the filename extension.
            if (mime_type == null || mime_type == "" || mime_type == "application/octet-stream") {
                bool uncertain;
                string content_type = ContentType.guess(file_item.file_transfer.file_name, null, out uncertain);
                string guessed = ContentType.get_mime_type(content_type);
                if (guessed != null && guessed != "application/octet-stream") {
                    mime_type = guessed;
                    // Also fix the stored value so subsequent lookups are correct
                    file_item.file_transfer.mime_type = guessed;
                }
            }

            if (mime_type != null && mime_type.has_prefix("audio/")) {
                return new AudioFileMetaItem(content_item, stream_interactor);
            }
            if (mime_type != null && mime_type.has_prefix("video/")) {
                return new VideoFileMetaItem(content_item, stream_interactor);
            }
            return new FileMetaItem(content_item, stream_interactor);
        } else if (content_item.type_ == CallItem.TYPE) {
            return new CallMetaItem(content_item, stream_interactor);
        }
        critical("Got unknown content item type %s", content_item.type_);
        return null;
    }
}

public abstract class ContentMetaItem : Plugins.MetaConversationItem {

    public ContentItem content_item;

    protected ContentMetaItem(ContentItem content_item) {
        this.jid = content_item.jid;
        this.time = content_item.time;
        this.secondary_sort_indicator = content_item.id;
        this.encryption = content_item.encryption;
        this.mark = content_item.mark;

        content_item.bind_property("mark", this, "mark");
        content_item.bind_property("encryption", this, "encryption");

        this.can_merge = true;
        this.requires_avatar = true;
        this.requires_header = true;

        this.content_item = content_item;
    }
}

}
