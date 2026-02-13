using Dino.Entities;
using Gee;
using Xmpp;

namespace Dino.Plugins.NotificationSound {

public class Plugin : RootInterface, Object {

    public Dino.Application app;
    private Canberra.Context? sound_context;
    private uint ringtone_timeout_id = 0;
    private Call? ringing_call = null;
    private ulong ringing_state_handler = 0;

    public void registered(Dino.Application app) {
        this.app = app;

        int err = Canberra.Context.create(out sound_context);
        if (err != 0 || sound_context == null) {
            warning("NotificationSound: Failed to create libcanberra context (error %d)", err);
            sound_context = null;
            return;
        }

        sound_context.change_props(Canberra.PROP_APPLICATION_NAME, "DinoX",
                                   Canberra.PROP_APPLICATION_ID, "im.github.rallep71.DinoX");

        app.stream_interactor.get_module<NotificationEvents>(NotificationEvents.IDENTITY).notify_content_item.connect(on_notify_content_item);
        app.stream_interactor.get_module<Calls>(Calls.IDENTITY).call_incoming.connect(on_call_incoming);
        app.stream_interactor.get_module<Calls>(Calls.IDENTITY).call_terminated.connect(on_call_terminated);
    }

    private void on_notify_content_item(ContentItem item, Conversation conversation) {
        if (sound_context == null) return;
        sound_context.play(0,
            Canberra.PROP_EVENT_ID, "message-new-instant",
            Canberra.PROP_EVENT_DESCRIPTION, "New message");
    }

    private void on_call_incoming(Call call, CallState state, Conversation conversation, bool video, bool multiparty) {
        if (sound_context == null) return;

        // Stop any previous ringtone
        stop_ringtone();

        ringing_call = call;
        // Play ringtone immediately, then repeat every 3 seconds
        play_ringtone();
        ringtone_timeout_id = GLib.Timeout.add_seconds(3, () => {
            if (ringing_call == null || ringing_call.state != Call.State.RINGING) {
                stop_ringtone();
                return GLib.Source.REMOVE;
            }
            play_ringtone();
            return GLib.Source.CONTINUE;
        });

        // Monitor call state changes to stop ringtone
        ringing_state_handler = call.notify["state"].connect(() => {
            if (call.state != Call.State.RINGING) {
                stop_ringtone();
            }
        });
    }

    private void on_call_terminated(Call call, string? reason_name, string? reason_text) {
        if (ringing_call != null && ringing_call == call) {
            stop_ringtone();
        }
    }

    private void play_ringtone() {
        if (sound_context == null) return;
        sound_context.play(1,
            Canberra.PROP_EVENT_ID, "phone-incoming-call",
            Canberra.PROP_EVENT_DESCRIPTION, "Incoming call");
    }

    private void stop_ringtone() {
        if (ringtone_timeout_id != 0) {
            GLib.Source.remove(ringtone_timeout_id);
            ringtone_timeout_id = 0;
        }
        if (sound_context != null) {
            sound_context.cancel(1);
        }
        if (ringing_call != null && ringing_state_handler != 0) {
            ringing_call.disconnect(ringing_state_handler);
            ringing_state_handler = 0;
        }
        ringing_call = null;
    }

    public void shutdown() {
        stop_ringtone();
        sound_context = null;
    }
}

}
