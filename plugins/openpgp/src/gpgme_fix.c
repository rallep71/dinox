#include <gpgme_fix.h>
#ifdef _WIN32
#include <stdio.h>
#include <fcntl.h>
#include <io.h>
#endif

GRecMutex gpgme_global_mutex = {0};

void openpgp_fix_windows_stdio (void) {
#ifdef _WIN32
    int null_fd = -1;
    int fd;
    for (fd = 0; fd <= 2; fd++) {
        if (_get_osfhandle(fd) == -1) {
             if (null_fd == -1) {
                 null_fd = _open("NUL", _O_RDWR);
             }
             if (null_fd != -1) {
                 _dup2(null_fd, fd);
             }
        }
    }
    if (null_fd != -1) {
        _close(null_fd);
    }
#endif
}

gpgme_key_t gpgme_key_ref_vapi (gpgme_key_t key) {
    gpgme_key_ref(key);
    return key;
}
gpgme_key_t gpgme_key_unref_vapi (gpgme_key_t key) {
    gpgme_key_unref(key);
    return key;
}
