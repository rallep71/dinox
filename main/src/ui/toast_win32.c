/***********************************************************************
 * toast_win32.c — WinRT Toast Notification helper for DinoX
 *
 * Uses raw COM vtable calls to access Windows.UI.Notifications APIs
 * from plain C (MinGW-w64 compatible). Dynamic-loads WinRT functions
 * from combase.dll for graceful fallback on Windows 7/8.
 *
 * Architecture:
 *   1. Dynamic-load combase.dll for WinRT functions
 *   2. Set Application User Model ID (AUMID) on the process
 *   3. Create Start Menu shortcut with AUMID + ToastActivatorCLSID
 *   4. Register COM class factory for activation callback
 *   5. Create IToastNotifier via WinRT ToastNotificationManager
 *   6. Show/hide toast notifications using XML templates
 *   7. Receive activation callbacks when user clicks toast / buttons
 ***********************************************************************/

#ifdef _WIN32

#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <propsys.h>
#include <glib.h>
#include "toast_win32.h"

/* ===================================================================
 * Section 1: WinRT type definitions
 * =================================================================== */

typedef void* HSTRING;

#ifndef RO_INIT_SINGLETHREADED
#define RO_INIT_SINGLETHREADED 0
#endif

#ifndef NOTIFICATION_USER_INPUT_DATA_DEFINED
#define NOTIFICATION_USER_INPUT_DATA_DEFINED
typedef struct NOTIFICATION_USER_INPUT_DATA {
    LPCWSTR Key;
    LPCWSTR Value;
} NOTIFICATION_USER_INPUT_DATA;
#endif

/* ===================================================================
 * Section 2: Dynamic WinRT function loading
 * =================================================================== */

typedef HRESULT (WINAPI *pfnRoInitialize)(int);
typedef HRESULT (WINAPI *pfnRoGetActivationFactory)(HSTRING, REFIID, void**);
typedef HRESULT (WINAPI *pfnRoActivateInstance)(HSTRING, void**);
typedef HRESULT (WINAPI *pfnWindowsCreateString)(LPCWSTR, UINT32, HSTRING*);
typedef HRESULT (WINAPI *pfnWindowsDeleteString)(HSTRING);
typedef HRESULT (WINAPI *pfnSetCurrentProcessExplicitAppUserModelID)(LPCWSTR);

static pfnRoInitialize                              pRoInitialize;
static pfnRoGetActivationFactory                     pRoGetActivationFactory;
static pfnRoActivateInstance                         pRoActivateInstance;
static pfnWindowsCreateString                        pWindowsCreateString;
static pfnWindowsDeleteString                        pWindowsDeleteString;
static pfnSetCurrentProcessExplicitAppUserModelID    pSetAppUserModelID;

static HMODULE g_combase_dll;

/* ===================================================================
 * Section 3: COM GUIDs
 * =================================================================== */

/* WinRT Toast interfaces */
static const GUID IID_IToastNotifMgrStatics =
    {0x50AC103F, 0xD235, 0x4598, {0xBB, 0xEF, 0x98, 0xFE, 0x4D, 0x1A, 0x3A, 0xD4}};
static const GUID IID_IToastNotifMgrStatics2 =
    {0x7AB93C52, 0x0E48, 0x4750, {0xBA, 0x9D, 0x1A, 0x41, 0x13, 0x98, 0x18, 0x47}};
static const GUID IID_IToastNotifier =
    {0x75927B93, 0x03F3, 0x41EC, {0x91, 0xD3, 0x6E, 0x5B, 0xAC, 0x1B, 0x38, 0xE8}};
static const GUID IID_IToastNotifFactory =
    {0x04124B20, 0x82C6, 0x4229, {0xB1, 0x09, 0xFD, 0x9E, 0xD4, 0x66, 0x2B, 0x53}};
static const GUID IID_IToastNotification2 =
    {0x9DFB9FD1, 0x143A, 0x490E, {0x90, 0xBF, 0xB9, 0xFB, 0xA7, 0x13, 0x2D, 0xE7}};
static const GUID IID_IXmlDocumentIO =
    {0x6CD0E74E, 0xEE65, 0x4489, {0x9E, 0xBF, 0xCA, 0x43, 0xE8, 0x7B, 0xA6, 0x37}};
static const GUID IID_IToastNotifHistory =
    {0x5CADDC63, 0x01D3, 0x4C97, {0x98, 0x6F, 0x05, 0x33, 0x48, 0x3F, 0xEE, 0x14}};
static const GUID IID_INotifActivationCb =
    {0x53E31837, 0x6600, 0x4A81, {0x93, 0x95, 0x75, 0xCF, 0xFE, 0x74, 0x6F, 0x94}};

/* Standard COM GUIDs */
static const GUID CLSID_ShellLink_ =
    {0x00021401, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID IID_IShellLinkW_ =
    {0x000214F9, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID IID_IPersistFile_ =
    {0x0000010B, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID IID_IPropertyStore_ =
    {0x886D8EEB, 0x8CF2, 0x4446, {0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99}};

/* Our toast activator CLSID (fixed, used in shortcut + registry) */
static const GUID CLSID_DinoXToastActivator =
    {0xD8F35E81, 0x2B7C, 0x4A19, {0x8F, 0xD3, 0x6E, 0x1B, 0x9C, 0x5A, 0x42, 0xF0}};

/* Property keys for Start Menu shortcut */
static const PROPERTYKEY PK_AppUserModel_ID = {
    {0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 5
};
static const PROPERTYKEY PK_AppUserModel_ToastActivatorCLSID = {
    {0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 26
};

/* ===================================================================
 * Section 4: Global state
 * =================================================================== */

static ToastWin32ActivatedCallback g_activated_callback;
static gpointer                    g_callback_user_data;
static void                       *g_toast_notifier;    /* IToastNotifier      */
static void                       *g_toast_factory;     /* IToastNotifFactory  */
static void                       *g_toast_mgr;         /* IToastNotifMgrStat  */
static void                       *g_toast_mgr2;        /* IToastNotifMgrStat2 */
static DWORD                       g_com_cookie;        /* CoRegisterClassObj   */
static HSTRING                     g_aumid_hs;          /* AUMID as HSTRING    */
static WCHAR                      *g_aumid_wide;        /* AUMID as WCHAR*     */
static gboolean                    g_toast_inited;

/* ===================================================================
 * Section 5: HSTRING helpers
 * =================================================================== */

static HSTRING create_hs(const WCHAR *str) {
    if (!str || !pWindowsCreateString) return NULL;
    HSTRING hs = NULL;
    pWindowsCreateString(str, (UINT32)wcslen(str), &hs);
    return hs;
}

static HSTRING create_hs_utf8(const char *utf8) {
    if (!utf8 || !pWindowsCreateString) return NULL;
    gunichar2 *wide = g_utf8_to_utf16(utf8, -1, NULL, NULL, NULL);
    if (!wide) return NULL;
    HSTRING hs = NULL;
    pWindowsCreateString((LPCWSTR)wide, (UINT32)wcslen((WCHAR*)wide), &hs);
    g_free(wide);
    return hs;
}

static void free_hs(HSTRING hs) {
    if (hs && pWindowsDeleteString) pWindowsDeleteString(hs);
}

/* ===================================================================
 * Section 6: COM vtable call macros
 *
 * WinRT COM vtable layout:
 *   [0] QueryInterface  [1] AddRef  [2] Release
 *   [3] GetIids  [4] GetRuntimeClassName  [5] GetTrustLevel
 *   [6+] Interface-specific methods
 * =================================================================== */

#define VT(obj, idx) (((void**)(*(void**)(obj)))[(idx)])

static inline HRESULT com_qi(void *obj, const GUID *riid, void **out) {
    typedef HRESULT (STDMETHODCALLTYPE *fn)(void*, const GUID*, void**);
    return ((fn)VT(obj, 0))(obj, riid, out);
}

static inline ULONG com_release(void *obj) {
    typedef ULONG (STDMETHODCALLTYPE *fn)(void*);
    return ((fn)VT(obj, 2))(obj);
}

/*
 * WinRT vtable indices for interfaces we use:
 *
 * IToastNotificationManagerStatics:
 *   [6] GetTemplateContent  [7] CreateToastNotifier  [8] CreateToastNotifierWithId
 *
 * IToastNotificationManagerStatics2:
 *   [6] get_History
 *
 * IToastNotifier:
 *   [6] Show  [7] Hide  [8] get_Setting
 *
 * IToastNotificationFactory:
 *   [6] CreateToastNotification(IXmlDocument*, IToastNotification**)
 *
 * IToastNotification2:
 *   [6] put_Tag  [7] get_Tag  [8] put_Group  [9] get_Group
 *
 * IXmlDocumentIO:
 *   [6] LoadXml
 *
 * IToastNotificationHistory:
 *   [6] RemoveGroup  [7] RemoveGroupWithId  [8] Remove(tag,group,appId)  [9] Clear
 *
 * IShellLinkW:
 *   [7] SetDescription  [17] SetIconLocation  [20] SetPath
 *
 * IPersistFile:
 *   [6] Save(filename, fRemember)
 *
 * IPropertyStore:
 *   [6] SetValue  [7] Commit
 */

/* ===================================================================
 * Section 7: INotificationActivationCallback implementation
 *
 * When user clicks a toast (body or button), Windows calls Activate()
 * with the arguments string from the toast XML. We dispatch this to
 * the Vala callback on the GTK main thread via g_idle_add().
 * =================================================================== */

typedef struct {
    /* Our vtable (INotificationActivationCallback) */
    void **lpVtbl;
    LONG    ref_count;
} ToastActivator;

/* Data struct for g_idle_add dispatch */
typedef struct {
    gchar *action_args;
} ActivationDispatch;

static gboolean dispatch_activation_idle(gpointer user_data) {
    ActivationDispatch *d = (ActivationDispatch*)user_data;
    if (g_activated_callback && d->action_args) {
        g_activated_callback(d->action_args, g_callback_user_data);
    }
    g_free(d->action_args);
    g_free(d);
    return G_SOURCE_REMOVE;
}

static HRESULT STDMETHODCALLTYPE Activator_QueryInterface(void *this_, REFIID riid, void **ppv) {
    if (!ppv) return E_POINTER;
    if (IsEqualGUID(riid, &IID_INotifActivationCb) ||
        IsEqualGUID(riid, &IID_IUnknown)) {
        *ppv = this_;
        ((ToastActivator*)this_)->ref_count++;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE Activator_AddRef(void *this_) {
    return InterlockedIncrement(&((ToastActivator*)this_)->ref_count);
}

static ULONG STDMETHODCALLTYPE Activator_Release(void *this_) {
    LONG rc = InterlockedDecrement(&((ToastActivator*)this_)->ref_count);
    if (rc == 0) {
        g_free(this_);
    }
    return rc;
}

static HRESULT STDMETHODCALLTYPE Activator_Activate(
    void *this_,
    LPCWSTR appUserModelId,
    LPCWSTR invokedArgs,
    const NOTIFICATION_USER_INPUT_DATA *data,
    ULONG count)
{
    (void)this_; (void)appUserModelId; (void)data; (void)count;

    if (invokedArgs && invokedArgs[0]) {
        gchar *utf8 = g_utf16_to_utf8((const gunichar2*)invokedArgs, -1, NULL, NULL, NULL);
        if (utf8) {
            ActivationDispatch *d = g_new0(ActivationDispatch, 1);
            d->action_args = utf8;
            g_idle_add(dispatch_activation_idle, d);
        }
    }
    return S_OK;
}

static void *activator_vtbl[] = {
    Activator_QueryInterface,
    Activator_AddRef,
    Activator_Release,
    Activator_Activate
};

/* ===================================================================
 * Section 8: IClassFactory implementation
 *
 * COM class factory that creates ToastActivator instances.
 * Registered with CoRegisterClassObject so Windows can call us back.
 * =================================================================== */

typedef struct {
    void **lpVtbl;
} ToastClassFactory;

static HRESULT STDMETHODCALLTYPE Factory_QueryInterface(void *this_, REFIID riid, void **ppv) {
    if (!ppv) return E_POINTER;
    static const GUID IID_IClassFactory_ =
        {0x00000001, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
    if (IsEqualGUID(riid, &IID_IClassFactory_) ||
        IsEqualGUID(riid, &IID_IUnknown)) {
        *ppv = this_;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE Factory_AddRef(void *this_)  { (void)this_; return 2; }
static ULONG STDMETHODCALLTYPE Factory_Release(void *this_) { (void)this_; return 1; }

static HRESULT STDMETHODCALLTYPE Factory_CreateInstance(
    void *this_, void *pOuter, REFIID riid, void **ppv)
{
    (void)this_;
    if (pOuter) return CLASS_E_NOAGGREGATION;
    if (!ppv)   return E_POINTER;

    ToastActivator *activator = g_new0(ToastActivator, 1);
    activator->lpVtbl    = activator_vtbl;
    activator->ref_count = 1;

    HRESULT hr = Activator_QueryInterface(activator, riid, ppv);
    Activator_Release(activator);
    return hr;
}

static HRESULT STDMETHODCALLTYPE Factory_LockServer(void *this_, BOOL lock) {
    (void)this_; (void)lock; return S_OK;
}

static void *factory_vtbl[] = {
    Factory_QueryInterface,
    Factory_AddRef,
    Factory_Release,
    Factory_CreateInstance,
    Factory_LockServer
};

static ToastClassFactory g_class_factory = { factory_vtbl };

/* ===================================================================
 * Section 9: Shortcut + Registry setup
 *
 * Creates a Start Menu shortcut with AUMID + ToastActivatorCLSID
 * and registers the COM LocalServer32 entry. Required for toast
 * notifications to work on unpackaged desktop apps.
 * =================================================================== */

static gboolean create_start_menu_shortcut(const WCHAR *aumid_wide, const WCHAR *app_name_wide) {
    HRESULT hr;
    WCHAR exe_path[MAX_PATH];
    WCHAR shortcut_path[MAX_PATH];

    /* Get our exe path */
    GetModuleFileNameW(NULL, exe_path, MAX_PATH);

    /* Build shortcut path: %CSIDL_PROGRAMS%\DinoX.lnk */
    hr = SHGetFolderPathW(NULL, CSIDL_PROGRAMS, NULL, 0, shortcut_path);
    if (FAILED(hr)) return FALSE;
    wcsncat(shortcut_path, L"\\DinoX.lnk", MAX_PATH - wcslen(shortcut_path) - 1);

    /* Create IShellLinkW */
    void *psl = NULL;
    hr = CoCreateInstance(&CLSID_ShellLink_, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IShellLinkW_, &psl);
    if (FAILED(hr) || !psl) return FALSE;

    /* IShellLinkW::SetPath [vtable 20] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_SL_SetPath)(void*, LPCWSTR);
    ((pfn_SL_SetPath)VT(psl, 20))(psl, exe_path);

    /* IShellLinkW::SetDescription [vtable 7] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_SL_SetDesc)(void*, LPCWSTR);
    ((pfn_SL_SetDesc)VT(psl, 7))(psl, app_name_wide);

    /* IShellLinkW::SetIconLocation [vtable 17] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_SL_SetIcon)(void*, LPCWSTR, int);
    ((pfn_SL_SetIcon)VT(psl, 17))(psl, exe_path, 0);

    /* Set AUMID via IPropertyStore */
    void *pps = NULL;
    hr = com_qi(psl, &IID_IPropertyStore_, &pps);
    if (SUCCEEDED(hr) && pps) {
        /* IPropertyStore::SetValue [vtable 6] */
        typedef HRESULT (STDMETHODCALLTYPE *pfn_PS_SetValue)(void*, const PROPERTYKEY*, const PROPVARIANT*);
        typedef HRESULT (STDMETHODCALLTYPE *pfn_PS_Commit)(void*);

        /* Set AUMID (VT_LPWSTR) */
        PROPVARIANT pv_aumid;
        memset(&pv_aumid, 0, sizeof(pv_aumid));
        pv_aumid.vt = VT_LPWSTR;
        pv_aumid.pwszVal = (LPWSTR)CoTaskMemAlloc((wcslen(aumid_wide) + 1) * sizeof(WCHAR));
        if (pv_aumid.pwszVal) {
            wcscpy(pv_aumid.pwszVal, aumid_wide);
            ((pfn_PS_SetValue)VT(pps, 6))(pps, &PK_AppUserModel_ID, &pv_aumid);
            CoTaskMemFree(pv_aumid.pwszVal);
        }

        /* Set ToastActivatorCLSID (VT_CLSID) */
        PROPVARIANT pv_clsid;
        memset(&pv_clsid, 0, sizeof(pv_clsid));
        pv_clsid.vt = VT_CLSID;
        pv_clsid.puuid = (CLSID*)CoTaskMemAlloc(sizeof(GUID));
        if (pv_clsid.puuid) {
            memcpy(pv_clsid.puuid, &CLSID_DinoXToastActivator, sizeof(GUID));
            ((pfn_PS_SetValue)VT(pps, 6))(pps, &PK_AppUserModel_ToastActivatorCLSID, &pv_clsid);
            CoTaskMemFree(pv_clsid.puuid);
        }

        /* IPropertyStore::Commit [vtable 7] */
        ((pfn_PS_Commit)VT(pps, 7))(pps);
        com_release(pps);
    }

    /* Save shortcut via IPersistFile */
    void *ppf = NULL;
    hr = com_qi(psl, &IID_IPersistFile_, &ppf);
    if (SUCCEEDED(hr) && ppf) {
        /* IPersistFile::Save [vtable 6] */
        typedef HRESULT (STDMETHODCALLTYPE *pfn_PF_Save)(void*, LPCOLESTR, BOOL);
        ((pfn_PF_Save)VT(ppf, 6))(ppf, shortcut_path, TRUE);
        com_release(ppf);
    }

    com_release(psl);
    return TRUE;
}

static void register_com_server(void) {
    /* Register LocalServer32 so Windows can find our COM activator */
    WCHAR exe_path[MAX_PATH];
    GetModuleFileNameW(NULL, exe_path, MAX_PATH);

    /* Build: HKCU\Software\Classes\CLSID\{GUID}\LocalServer32 */
    WCHAR clsid_str[64];
    StringFromGUID2(&CLSID_DinoXToastActivator, clsid_str, 64);

    WCHAR key_path[256];
    _snwprintf(key_path, 256,
        L"Software\\Classes\\CLSID\\%ls\\LocalServer32", clsid_str);

    HKEY hKey;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path, 0, NULL,
                        0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        WCHAR quoted[MAX_PATH + 4];
        _snwprintf(quoted, MAX_PATH + 4, L"\"%ls\"", exe_path);
        RegSetValueExW(hKey, NULL, 0, REG_SZ,
                       (BYTE*)quoted, (DWORD)((wcslen(quoted) + 1) * sizeof(WCHAR)));
        RegCloseKey(hKey);
    }
}

/* ===================================================================
 * Section 10: toast_win32_init()
 * =================================================================== */

gboolean toast_win32_init(const gchar *app_name, const gchar *aumid,
                           ToastWin32ActivatedCallback callback,
                           gpointer user_data)
{
    HRESULT hr;

    if (g_toast_inited) return TRUE;

    /* Step 1: Dynamic-load combase.dll */
    g_combase_dll = LoadLibraryW(L"combase.dll");
    if (!g_combase_dll) {
        g_info("toast_win32: combase.dll not available (pre-Win8?)");
        return FALSE;
    }

    pRoInitialize          = (pfnRoInitialize)GetProcAddress(g_combase_dll, "RoInitialize");
    pRoGetActivationFactory = (pfnRoGetActivationFactory)GetProcAddress(g_combase_dll, "RoGetActivationFactory");
    pRoActivateInstance     = (pfnRoActivateInstance)GetProcAddress(g_combase_dll, "RoActivateInstance");
    pWindowsCreateString    = (pfnWindowsCreateString)GetProcAddress(g_combase_dll, "WindowsCreateString");
    pWindowsDeleteString    = (pfnWindowsDeleteString)GetProcAddress(g_combase_dll, "WindowsDeleteString");

    /* SetCurrentProcessExplicitAppUserModelID is in shell32.dll */
    HMODULE shell32 = GetModuleHandleW(L"shell32.dll");
    if (shell32) {
        pSetAppUserModelID = (pfnSetCurrentProcessExplicitAppUserModelID)
            GetProcAddress(shell32, "SetCurrentProcessExplicitAppUserModelID");
    }

    if (!pRoInitialize || !pRoGetActivationFactory || !pRoActivateInstance ||
        !pWindowsCreateString || !pWindowsDeleteString) {
        g_info("toast_win32: WinRT functions not available");
        return FALSE;
    }

    /* Step 2: Initialize WinRT */
    hr = pRoInitialize(RO_INIT_SINGLETHREADED);
    if (FAILED(hr) && hr != (HRESULT)0x80010106 /* RPC_E_CHANGED_MODE */ && hr != S_FALSE) {
        g_warning("toast_win32: RoInitialize failed: 0x%08lx", (unsigned long)hr);
        return FALSE;
    }

    /* Store callback */
    g_activated_callback = callback;
    g_callback_user_data = user_data;

    /* Step 3: Convert AUMID to wide string and HSTRING */
    g_aumid_wide = g_utf8_to_utf16(aumid, -1, NULL, NULL, NULL);
    if (!g_aumid_wide) return FALSE;
    g_aumid_hs = create_hs((WCHAR*)g_aumid_wide);

    /* Step 4: Set AUMID on process */
    if (pSetAppUserModelID) {
        pSetAppUserModelID((LPCWSTR)g_aumid_wide);
    }

    /* Step 5: Create Start Menu shortcut */
    {
        gunichar2 *app_name_wide = g_utf8_to_utf16(app_name, -1, NULL, NULL, NULL);
        if (app_name_wide) {
            create_start_menu_shortcut((WCHAR*)g_aumid_wide, (WCHAR*)app_name_wide);
            g_free(app_name_wide);
        }
    }

    /* Step 6: Register COM server in registry + class factory */
    register_com_server();
    hr = CoRegisterClassObject(&CLSID_DinoXToastActivator, (IUnknown*)&g_class_factory,
                                CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &g_com_cookie);
    if (FAILED(hr)) {
        g_warning("toast_win32: CoRegisterClassObject failed: 0x%08lx", (unsigned long)hr);
        /* Non-fatal: toasts will show, but clicks may not work */
    }

    /* Step 7: Get ToastNotificationManager factory */
    HSTRING hs_mgr_class = create_hs(L"Windows.UI.Notifications.ToastNotificationManager");
    hr = pRoGetActivationFactory(hs_mgr_class, &IID_IToastNotifMgrStatics, &g_toast_mgr);
    free_hs(hs_mgr_class);
    if (FAILED(hr) || !g_toast_mgr) {
        g_warning("toast_win32: Failed to get ToastNotificationManager: 0x%08lx", (unsigned long)hr);
        return FALSE;
    }

    /* Also get IToastNotificationManagerStatics2 for History API */
    com_qi(g_toast_mgr, &IID_IToastNotifMgrStatics2, &g_toast_mgr2);

    /* Step 8: Create ToastNotifier with our AUMID */
    /* IToastNotificationManagerStatics::CreateToastNotifierWithId [vtable 8] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_CreateNotifierWithId)(void*, HSTRING, void**);
    hr = ((pfn_CreateNotifierWithId)VT(g_toast_mgr, 8))(g_toast_mgr, g_aumid_hs, &g_toast_notifier);
    if (FAILED(hr) || !g_toast_notifier) {
        g_warning("toast_win32: CreateToastNotifierWithId failed: 0x%08lx", (unsigned long)hr);
        return FALSE;
    }

    /* Step 9: Get ToastNotification factory */
    HSTRING hs_notif_class = create_hs(L"Windows.UI.Notifications.ToastNotification");
    hr = pRoGetActivationFactory(hs_notif_class, &IID_IToastNotifFactory, &g_toast_factory);
    free_hs(hs_notif_class);
    if (FAILED(hr) || !g_toast_factory) {
        g_warning("toast_win32: Failed to get ToastNotification factory: 0x%08lx", (unsigned long)hr);
        return FALSE;
    }

    g_toast_inited = TRUE;
    g_info("toast_win32: Toast notifications initialized successfully");
    return TRUE;
}

/* ===================================================================
 * Section 11: toast_win32_show()
 * =================================================================== */

void toast_win32_show(const gchar *xml_utf8, const gchar *tag) {
    HRESULT hr;

    if (!g_toast_inited || !xml_utf8) return;

    /* Step 1: Create XmlDocument and load XML */
    HSTRING hs_xml_class = create_hs(L"Windows.Data.Xml.Dom.XmlDocument");
    void *xml_doc = NULL;  /* IInspectable (default interface = IXmlDocument) */
    hr = pRoActivateInstance(hs_xml_class, &xml_doc);
    free_hs(hs_xml_class);
    if (FAILED(hr) || !xml_doc) {
        g_warning("toast_win32: RoActivateInstance(XmlDocument) failed: 0x%08lx", (unsigned long)hr);
        return;
    }

    /* QI for IXmlDocumentIO to call LoadXml */
    void *xml_doc_io = NULL;
    hr = com_qi(xml_doc, &IID_IXmlDocumentIO, &xml_doc_io);
    if (FAILED(hr) || !xml_doc_io) {
        g_warning("toast_win32: QI IXmlDocumentIO failed: 0x%08lx", (unsigned long)hr);
        com_release(xml_doc);
        return;
    }

    /* IXmlDocumentIO::LoadXml [vtable 6] */
    HSTRING hs_xml = create_hs_utf8(xml_utf8);
    typedef HRESULT (STDMETHODCALLTYPE *pfn_LoadXml)(void*, HSTRING);
    hr = ((pfn_LoadXml)VT(xml_doc_io, 6))(xml_doc_io, hs_xml);
    free_hs(hs_xml);
    com_release(xml_doc_io);

    if (FAILED(hr)) {
        g_warning("toast_win32: LoadXml failed: 0x%08lx", (unsigned long)hr);
        com_release(xml_doc);
        return;
    }

    /* Step 2: Create ToastNotification from XmlDocument */
    void *toast = NULL;
    /* IToastNotificationFactory::CreateToastNotification [vtable 6] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_CreateToast)(void*, void*, void**);
    hr = ((pfn_CreateToast)VT(g_toast_factory, 6))(g_toast_factory, xml_doc, &toast);
    com_release(xml_doc);

    if (FAILED(hr) || !toast) {
        g_warning("toast_win32: CreateToastNotification failed: 0x%08lx", (unsigned long)hr);
        return;
    }

    /* Step 3: Set Tag and Group for retraction support */
    if (tag) {
        void *toast2 = NULL;
        hr = com_qi(toast, &IID_IToastNotification2, &toast2);
        if (SUCCEEDED(hr) && toast2) {
            HSTRING hs_tag = create_hs_utf8(tag);
            HSTRING hs_group = create_hs(L"dinox");

            /* IToastNotification2::put_Tag [vtable 6] */
            typedef HRESULT (STDMETHODCALLTYPE *pfn_put_Tag)(void*, HSTRING);
            ((pfn_put_Tag)VT(toast2, 6))(toast2, hs_tag);

            /* IToastNotification2::put_Group [vtable 8] */
            typedef HRESULT (STDMETHODCALLTYPE *pfn_put_Group)(void*, HSTRING);
            ((pfn_put_Group)VT(toast2, 8))(toast2, hs_group);

            free_hs(hs_tag);
            free_hs(hs_group);
            com_release(toast2);
        }
    }

    /* Step 4: Show the toast */
    /* IToastNotifier::Show [vtable 6] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_Show)(void*, void*);
    hr = ((pfn_Show)VT(g_toast_notifier, 6))(g_toast_notifier, toast);

    if (FAILED(hr)) {
        g_warning("toast_win32: Show failed: 0x%08lx", (unsigned long)hr);
    }

    com_release(toast);
}

/* ===================================================================
 * Section 12: toast_win32_hide()
 * =================================================================== */

void toast_win32_hide(const gchar *tag) {
    HRESULT hr;

    if (!g_toast_inited || !g_toast_mgr2 || !tag) return;

    /* Get IToastNotificationHistory */
    void *history = NULL;
    /* IToastNotificationManagerStatics2::get_History [vtable 6] */
    typedef HRESULT (STDMETHODCALLTYPE *pfn_GetHistory)(void*, void**);
    hr = ((pfn_GetHistory)VT(g_toast_mgr2, 6))(g_toast_mgr2, &history);
    if (FAILED(hr) || !history) return;

    /* IToastNotificationHistory::Remove(tag, group, appId) [vtable 8] */
    HSTRING hs_tag   = create_hs_utf8(tag);
    HSTRING hs_group = create_hs(L"dinox");

    typedef HRESULT (STDMETHODCALLTYPE *pfn_Remove)(void*, HSTRING, HSTRING, HSTRING);
    ((pfn_Remove)VT(history, 8))(history, hs_tag, hs_group, g_aumid_hs);

    free_hs(hs_tag);
    free_hs(hs_group);
    com_release(history);
}

/* ===================================================================
 * Section 13: toast_win32_cleanup()
 * =================================================================== */

void toast_win32_cleanup(void) {
    if (!g_toast_inited) return;

    if (g_com_cookie) {
        CoRevokeClassObject(g_com_cookie);
        g_com_cookie = 0;
    }
    if (g_toast_notifier) { com_release(g_toast_notifier); g_toast_notifier = NULL; }
    if (g_toast_factory)  { com_release(g_toast_factory);  g_toast_factory  = NULL; }
    if (g_toast_mgr2)     { com_release(g_toast_mgr2);     g_toast_mgr2     = NULL; }
    if (g_toast_mgr)      { com_release(g_toast_mgr);      g_toast_mgr      = NULL; }

    free_hs(g_aumid_hs); g_aumid_hs = NULL;
    g_free(g_aumid_wide); g_aumid_wide = NULL;

    g_activated_callback = NULL;
    g_callback_user_data = NULL;
    g_toast_inited = FALSE;
}

#else

/* Linux stubs (file is not compiled on Linux, but included for safety) */
gboolean toast_win32_init(const char *n, const char *a,
                           ToastWin32ActivatedCallback cb, void *ud) {
    (void)n; (void)a; (void)cb; (void)ud; return FALSE;
}
void toast_win32_show(const char *x, const char *t) { (void)x; (void)t; }
void toast_win32_hide(const char *t) { (void)t; }
void toast_win32_cleanup(void) {}

#endif
