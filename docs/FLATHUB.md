# Flathub Submission Guide for DinoX

## 🎯 Quick Start

Your app is ready for Flathub submission! Here's what you need to do:

### 1. Create Flathub Account

1. Go to https://github.com/flathub/flathub
2. Create a GitHub account if you don't have one
3. Fork the flathub/flathub repository

### 2. Prepare Submission

Your app needs these files (✅ = ready, ⚠️ = needs update):

- ✅ `im.dino.Dino.json` - Flatpak manifest
- ✅ `flathub.json` - Build configuration
- ⚠️ `im.dino.Dino.appdata.xml` - Needs version 0.6.0 entry
- ✅ Icons and desktop file

### 3. Update AppData for Fork

The appdata.xml needs to reflect that this is DinoX:

**Required changes to `main/data/im.dino.Dino.appdata.xml.in`:**

```xml
<name translate="no">DinoX</name>
<summary>Modern XMPP chat client with extended features</summary>
<description>
  <p>DinoX is an active fork of Dino with faster development and additional features.</p>
  <p>New features include: system tray support, custom server settings, comprehensive contact management with blocking, and improved message history management.</p>
  <p>It maintains full compatibility with the XMPP protocol and supports 60+ XEPs including OMEMO and OpenPGP encryption.</p>
</description>
<url type="homepage">https://github.com/rallep71/dinox</url>
<url type="bugtracker">https://github.com/rallep71/dinox/issues</url>
<url type="vcs-browser">https://github.com/rallep71/dinox</url>

<releases>
  <release date="2025-11-21" version="0.6.0">
    <description>
      <p>First release of DinoX with extended features:</p>
      <ul>
        <li>System tray support (StatusNotifierItem)</li>
        <li>Background mode - keep running when window closed</li>
        <li>Custom server connection settings</li>
        <li>Contact management with block/mute features</li>
        <li>Delete conversation history</li>
        <li>XEP-0191 blocking command UI</li>
      </ul>
    </description>
  </release>
</releases>
```

### 4. Submit to Flathub

**Option A: New App Submission**

Since this is a fork, you should use a different App ID to avoid conflicts:

```
im.github.rallep71.DinoX  (New ID - recommended ⭐)
```

or alternative:

```
im.dinox.Dino  (Requires custom domain)
```

**Steps:**

1. Go to https://github.com/flathub/flathub/issues/new
2. Select "New app submission"
3. Provide:
   - App ID: `im.github.rallep71.DinoX`
   - Repository: https://github.com/rallep71/dinox
   - Flatpak manifest: Already in repo
   
4. Flathub creates a repository: `https://github.com/flathub/im.dino.Dino`
5. You get write access to that repo
6. Push your manifest files there

**Option B: Fork Existing App**

If Dino is already on Flathub (check: https://flathub.org/apps/im.dino.Dino):

1. Contact Flathub maintainers
2. Explain it's an actively developed fork
3. Request either:
   - New app ID for extended version
   - Or update existing app to point to your fork

### 5. Flathub Build Requirements

✅ Your manifest already meets these:

- Uses stable GNOME runtime (49)
- Includes appdata.xml with screenshots
- Has desktop file with correct categories
- Includes icon in multiple sizes
- finish-args are reasonable (no --filesystem=host)

### 6. Review Process

After submission:

1. **Automated checks** (~5 minutes)
   - Manifest validity
   - AppData validation
   - License checks
   
2. **Manual review** (1-7 days)
   - Security review
   - Quality checks
   - Policy compliance
   
3. **Approval & publish**
   - App appears on Flathub
   - Available via: `flatpak install flathub im.dino.Dino`

## 📋 Pre-submission Checklist

Before submitting, ensure:

- [ ] AppData includes version 0.6.0 release notes
- [ ] URLs point to your fork (rallep71/dino)
- [ ] Name indicates it's "Dino Extended"
- [ ] Screenshots are included (see below)
- [ ] License is correct (GPL-3.0)
- [ ] No bundled proprietary code

## 📸 Screenshots Required

Flathub requires at least 3 screenshots showing:

1. Main chat window
2. Settings/preferences
3. Unique features (contact management, systray)

Add to appdata.xml:

```xml
<screenshots>
  <screenshot type="default">
    <image>https://your-url/screenshot1.png</image>
    <caption>Main chat interface</caption>
  </screenshot>
  <screenshot>
    <image>https://your-url/screenshot2.png</image>
    <caption>Contact management</caption>
  </screenshot>
</screenshots>
```

## 🔑 App ID Consideration

**Important decision:**

1. **Keep `im.dino.Dino`** (original ID)
   - ✅ Users find it easily
   - ❌ Conflicts with upstream if they submit
   - ❌ Might confuse with original
   
2. **Use `im.dino.DinoExtended`** (new ID)
   - ✅ Clear it's a fork
   - ✅ No conflicts
   - ❌ Users must know the exact name

**Recommendation:** Use new ID if upstream Dino might submit to Flathub later.

## 🌐 Alternative: Unofficial Repository

If Flathub submission takes too long, you can host your own Flatpak repo:

```bash
# Users add your repo
flatpak remote-add --user dino-extended https://rallep71.github.io/dino/repo

# Then install
flatpak install dino-extended im.dino.Dino
```

This requires setting up a flatpak repository with OSTree.

## 📚 Resources

- Flathub Submission: https://docs.flathub.org/docs/for-app-authors/submission
- App Requirements: https://docs.flathub.org/docs/for-app-authors/requirements
- AppData Spec: https://www.freedesktop.org/software/appstream/docs/
- Flathub App List: https://flathub.org/apps

## 🆘 Support

- Flathub Matrix: #flathub:matrix.org
- Flathub Discourse: https://discourse.flathub.org/
- GitHub Issues: https://github.com/flathub/flathub/issues

## ⏱️ Timeline

- Submission: 10 minutes
- Automated checks: 5 minutes  
- Review: 1-7 days
- First build: 30 minutes
- Published: Immediately after approval

Your app is well-prepared and should pass review easily! 🚀
