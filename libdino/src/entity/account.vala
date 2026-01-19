/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;
using Xmpp;

namespace Dino.Entities {

public class Account : Object {

    public int id { get; set; }
    public string localpart { get { return full_jid.localpart; } }
    public string domainpart { get { return full_jid.domainpart; } }
    public string resourcepart {
        get { return full_jid.resourcepart; }
        private set { full_jid.resourcepart = value; }
    }
    public Jid bare_jid { owned get { return full_jid.bare_jid; } }
    public Jid full_jid { get; private set; }
    public string? password { get; set; }
    public string display_name {
        owned get { return (alias != null && alias.length > 0) ? alias.dup() : bare_jid.to_string(); }
    }
    public string? alias { get; set; }
    public bool enabled { get; set; default = false; }
    public string? roster_version { get; set; }
    public string? custom_host { get; set; }
    public int custom_port { get; set; default = 0; }
    public string proxy_type { get; set; default = "none"; }
    public string? proxy_host { get; set; }
    public int proxy_port { get; set; default = 0; }

    private Database? db;

    public Account(Jid bare_jid, string password) {
        this.id = -1;
        try {
            this.full_jid = bare_jid.with_resource(get_random_resource());
        } catch (InvalidJidError e) {
            error("Auto-generated resource was invalid (%s)", e.message);
        }
        this.password = password;
    }

    public Account.from_row(Database db, Qlite.Row row) throws InvalidJidError {
        this.db = db;
        id = row[db.account.id];
        full_jid = new Jid(row[db.account.bare_jid]).with_resource(row[db.account.resourcepart]);
        password = row[db.account.password];
        alias = row[db.account.alias];
        enabled = row[db.account.enabled];
        roster_version = row[db.account.roster_version];
        custom_host = row[db.account.custom_host];
        custom_port = row[db.account.custom_port];
        proxy_type = row[db.account.proxy_type];
        proxy_host = row[db.account.proxy_host];
        proxy_port = row[db.account.proxy_port];

        notify.connect(on_update);
    }

    public void persist(Database db) {
        if (id > 0) return;

        this.db = db;
        id = (int) db.account.insert()
                .value(db.account.bare_jid, bare_jid.to_string())
                .value(db.account.resourcepart, resourcepart)
                .value(db.account.password, password)
                .value(db.account.alias, alias)
                .value(db.account.enabled, enabled)
                .value(db.account.roster_version, roster_version)
                .value(db.account.custom_host, custom_host)
                .value(db.account.custom_port, custom_port)
                .value(db.account.proxy_type, proxy_type)
                .value(db.account.proxy_host, proxy_host)
                .value(db.account.proxy_port, proxy_port)
                .perform();

        notify.connect(on_update);
    }

    public void remove() {
        db.account.delete().with(db.account.bare_jid, "=", bare_jid.to_string()).perform();
        notify.disconnect(on_update);
        id = -1;
        db = null;
    }

    public void set_random_resource() {
        this.resourcepart = get_random_resource();
    }

    private static string get_random_resource() {
        return "DinoX." + Random.next_int().to_string("%x");
    }

    public bool equals(Account acc) {
        return equals_func(this, acc);
    }

    public static bool equals_func(Account acc1, Account acc2) {
        return acc1.bare_jid.to_string() == acc2.bare_jid.to_string();
    }

    public static uint hash_func(Account acc) {
        return acc.bare_jid.to_string().hash();
    }

    private void on_update(Object o, ParamSpec sp) {
        var update = db.account.update().with(db.account.id, "=", id);
        switch (sp.name) {
            case "bare-jid":
                update.set(db.account.bare_jid, bare_jid.to_string()); break;
            case "resourcepart":
                update.set(db.account.resourcepart, resourcepart); break;
            case "password":
                update.set(db.account.password, password); break;
            case "alias":
                update.set(db.account.alias, alias); break;
            case "enabled":
                update.set(db.account.enabled, enabled); break;
            case "roster-version":
                update.set(db.account.roster_version, roster_version); break;
            case "custom-host":
                update.set(db.account.custom_host, custom_host); break;
            case "custom-port":
                update.set(db.account.custom_port, custom_port); break;
            case "proxy-type":
                update.set(db.account.proxy_type, proxy_type); break;
            case "proxy-host":
                update.set(db.account.proxy_host, proxy_host); break;
            case "proxy-port":
                update.set(db.account.proxy_port, proxy_port); break;
        }
        update.perform();
    }
}

}
