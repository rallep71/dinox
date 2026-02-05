@echo off
REM DinoX Windows Launcher
REM Sets environment variables for GTK4/Adwaita to find resources

REM Get the directory where this script is located
set "DINOX_DIR=%~dp0"
set "DINOX_DIR=%DINOX_DIR:~0,-1%"

REM Set GTK/GLib paths
set "XDG_DATA_DIRS=%DINOX_DIR%\share"
set "GSETTINGS_SCHEMA_DIR=%DINOX_DIR%\share\glib-2.0\schemas"
set "GDK_PIXBUF_MODULE_FILE=%DINOX_DIR%\lib\gdk-pixbuf-2.0\2.10.0\loaders.cache"
set "GDK_PIXBUF_MODULEDIR=%DINOX_DIR%\lib\gdk-pixbuf-2.0\2.10.0\loaders"
set "GTK_PATH=%DINOX_DIR%"
set "GST_PLUGIN_PATH=%DINOX_DIR%\lib\gstreamer-1.0"

REM SSL certificates
set "SSL_CERT_FILE=%DINOX_DIR%\ssl\certs\ca-bundle.crt"
set "SSL_CERT_DIR=%DINOX_DIR%\ssl\certs"

REM Add bin directory to PATH for gpg, tor, etc.
set "PATH=%DINOX_DIR%\bin;%DINOX_DIR%;%PATH%"

REM Launch DinoX
start "" "%DINOX_DIR%\dinox.exe" %*
