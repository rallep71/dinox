using GLib;
using Gee;

namespace Dino.Plugins.TorManager {

    public class TorController : Object {
        private Subprocess? tor_process;
        private LinkedList<string> last_log_lines = new LinkedList<string>();
        // private DataInputStream? control_stream;

        public bool is_running { get; private set; default = false; }
        public bool is_starting { get; private set; default = false; }
        public int socks_port { get; private set; default = 9155; }
        public string bridge_lines { get; set; default = ""; }
        public bool use_bridges { get; set; default = true; }
        public bool force_firewall_ports { get; set; default = true; } // Enabled by default for better UX
        
        public signal void process_exited(int status);
        public signal void bootstrap_status(int percent, string summary);
        public signal void started();


        public TorController() {
            // Check if Tor is available
            check_installation();
        }

        ~TorController() {
            stop();
        }

#if WINDOWS
        // Get the directory where the executable is located
        private string? get_executable_dir() {
            // On Windows, use Win32 API via GLib
            string? exe_path = null;
            // GLib provides this via get_current_dir, but we need the exe location
            // Use environment or fallback
            string? path = Environment.get_variable("_");  // The full path to the running exe
            if (path != null && path.has_suffix(".exe")) {
                exe_path = Path.get_dirname(path);
            }
            
            if (exe_path == null) {
                // Fallback: Check current working directory
                exe_path = Environment.get_current_dir();
            }
            return exe_path;
        }
#endif

        private void check_installation() {
            check_installation_async.begin();
        }

        private async void check_installation_async() {
            try {
                // Determine path to 'tor' executable
#if WINDOWS
                string? tor_path = Environment.find_program_in_path("tor.exe");
                if (tor_path == null) {
                    debug("Tor executable not in PATH yet (will be available via bin/ at runtime).");
                    return;
                }
                string[] argv = {tor_path, "--version"};
#else
                string[] argv = {"tor", "--version"};
#endif
                Subprocess proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                yield proc.wait_async();
                if (proc.get_if_exited() && proc.get_exit_status() == 0) {
                    debug("Tor executable found.");
                } else {
                    debug("Tor executable NOT found or errored.");
                }
            } catch (Error e) {
                debug("Tor check skipped: %s", e.message);
            }
        }

        private int find_free_port(int start_port) {
            int port = start_port;
            // Try up to 100 ports
            for (int i = 0; i < 100; i++) {
                try {
                    // Try to bind a socket to this port
                    Socket socket = new Socket(SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
                    InetAddress address = new InetAddress.from_string("127.0.0.1");
                    InetSocketAddress socket_address = new InetSocketAddress(address, (uint16)port);
                    
                    socket.bind(socket_address, false);
                    socket.close();
                    
                    // If we get here, port is free
                    return port;
                } catch (Error e) {
                    // Port likely in use, try next
                    port++;
                }
            }
            // Fallback to start_port if all fail (unlikely)
            return start_port;
        }

        public void clean_state() {
            string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "tor");
            warning("TorController: Cleaning Tor state in %s", data_dir);
            
            // Remove files that might contain corrupted state
            string[] files_to_delete = {"cached-certs", "cached-microdescs", "cached-microdesc-consensus", "cached-descriptors", "cached-descriptors.new", "state", "tor.pid", "lock", "cached-extrainfo", "cached-extrainfo.new"};
            
            foreach (string fname in files_to_delete) {
                string p = Path.build_filename(data_dir, fname);
                if (FileUtils.test(p, FileTest.EXISTS)) {
                    if (FileUtils.unlink(p) != 0) {
                        // Just log warning, not critical
                        warning("TorController: Failed to delete %s", p);
                    }
                }
            }
        }

        public async void start() {
            if (is_running || is_starting) return;
            is_starting = true;

            string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox", "tor");
            
            // ROBUST ZOMBIE KILLER: Force kill any previous instance
            // We do this BEFORE finding a free port to free up the default port (9155) if possible.
            try {
#if WINDOWS
                // Windows: Use taskkill to kill any running tor.exe
                string[] kill_cmd = {"taskkill", "/F", "/IM", "tor.exe"};
                var kill_proc = new Subprocess.newv(kill_cmd, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                yield kill_proc.wait_async();
#else
                // Linux/macOS: Use pkill to match config file path
                string[] kill_cmd = {"pkill", "-9", "-f", "dinox/tor/torrc"};
                var kill_proc = new Subprocess.newv(kill_cmd, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                yield kill_proc.wait_async();
#endif
                
                // Give the OS a moment to reclaim the ports
                Timeout.add(500, () => {
                    start.callback();
                    return false;
                });
                yield;
                
                debug("TorController: Zombie cleanup routine executed.");
            } catch (Error e) {
                // Ignored: kill might fail if no process exists, which is good.
                debug("TorController: No zombies found or kill unavailable: %s", e.message);
            }

            // Find a free port dynamically (after cleanup!)
            socks_port = find_free_port(9155);
            debug("TorController: Selected available port: %d", socks_port);

            DirUtils.create_with_parents(data_dir, 0700);

            // Cleanup stale PID file if it exists, just to be clean
            string pid_file = Path.build_filename(data_dir, "tor.pid");
            if (FileUtils.test(pid_file, FileTest.EXISTS)) {
                FileUtils.unlink(pid_file);
            }
            
            string torrc_path = Path.build_filename(data_dir, "torrc");

            StringBuilder torrc = new StringBuilder();
            torrc.append_printf("DataDirectory %s\n", data_dir);
            torrc.append_printf("PidFile %s\n", pid_file);
            torrc.append_printf("SocksPort %d\n", socks_port);
            
            // Try to find GeoIP files
            string[] geoip_opts = {"/app/share/tor/geoip", "/usr/share/tor/geoip", "/usr/local/share/tor/geoip"};
            foreach (string p in geoip_opts) {
                if (FileUtils.test(p, FileTest.EXISTS)) {
                    torrc.append_printf("GeoIPFile %s\n", p);
                    break;
                }
            }
            string[] geoip6_opts = {"/app/share/tor/geoip6", "/usr/share/tor/geoip6", "/usr/local/share/tor/geoip6"};
            foreach (string p in geoip6_opts) {
                 if (FileUtils.test(p, FileTest.EXISTS)) {
                    torrc.append_printf("GeoIPv6File %s\n", p);
                    break;
                }
            }

            if (use_bridges && bridge_lines.strip() != "") {
#if WINDOWS
                string obfs4_exe = "obfs4proxy.exe";
#else
                string obfs4_exe = "obfs4proxy";
#endif
                string? obfs4_path = Environment.find_program_in_path(obfs4_exe);
                
                // Fallback strategies for AppImage / Flatpak / Windows portable / Custom installs
                if (obfs4_path == null) {
                     var candidates = new Gee.ArrayList<string>();
                     
#if WINDOWS
                     // Windows portable: Look in bin/ subfolder relative to exe
                     string? exe_dir = get_executable_dir();
                     if (exe_dir != null) {
                         candidates.add(Path.build_filename(exe_dir, "bin", "obfs4proxy.exe"));
                         candidates.add(Path.build_filename(exe_dir, "obfs4proxy.exe"));
                     }
#else
                     // 1. AppImage specific: $APPDIR/usr/bin or $APPDIR/bin
                     string? appdir = Environment.get_variable("APPDIR");
                     if (appdir != null) {
                         candidates.add(Path.build_filename(appdir, "usr", "bin", "obfs4proxy"));
                         candidates.add(Path.build_filename(appdir, "bin", "obfs4proxy"));
                     }

                     // 2. Flatpak specific
                     candidates.add("/app/bin/obfs4proxy");

                     // 3. System locations
                     candidates.add("/usr/bin/obfs4proxy");
                     candidates.add("/usr/local/bin/obfs4proxy");
                     
                     // 4. Relative to executable (Portable builds)
                     try {
                         string self_path = FileUtils.read_link("/proc/self/exe");
                         string? self_dir = Path.get_dirname(self_path);
                         if (self_dir != null) {
                             candidates.add(Path.build_filename(self_dir, "obfs4proxy"));
                         }
                     } catch (Error e) { /* ignore */ }
#endif

                     foreach(string l in candidates) {
                        if (FileUtils.test(l, FileTest.EXISTS)) {
                            obfs4_path = l;
                            debug("[TOR] Found obfs4proxy at: %s", l);
                            break;
                        }
                     }
                }

                if (obfs4_path != null) {
                    torrc.append_printf("ClientTransportPlugin obfs4 exec %s\n", obfs4_path);
                } else {
                    warning("obfs4proxy not found, bridges might fail if they use obfs4");
                }

                torrc.append("UseBridges 1\n");
                
                // Firewall Bypass Logic
                if (force_firewall_ports) {
                    torrc.append("FascistFirewall 1\n");
                    torrc.append("ReachableAddresses *:80,*:443\n");
                }

                foreach (string line in bridge_lines.split("\n")) {
                    string clean_line = line.strip();
                    if (clean_line != "" && !clean_line.has_prefix("#")) {
                        torrc.append_printf("Bridge %s\n", clean_line);
                    }
                }
            }

            try {
                FileUtils.set_contents(torrc_path, torrc.str);
                // DEBUG PRINT TORRC
                debug("[TOR-DEBUG] Writing torrc to: %s", torrc_path);
                debug("[TOR-DEBUG] Content:\n%s", torrc.str);
            } catch (Error e) {
                warning("Failed to write torrc: %s", e.message);
                return;
            }

#if WINDOWS
            string[] argv = {"tor.exe", "-f", torrc_path};
#else
            string[] argv = {"tor", "-f", torrc_path};
#endif

            try {
                tor_process = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                is_running = true;
                is_starting = false;
                debug("Tor process started with PID: %s", tor_process.get_identifier());
                
                // Monitor the process
                monitor_process.begin(tor_process);
                
                // Wait for port to be open (Increased timeout for bridges)
                yield wait_until_port_open(socks_port);

                started();
                
            } catch (Error e) {
                warning("Failed to start Tor: %s", e.message);
                // CRITICAL FIX: Ensure we don't leave a zombie process if start fails (e.g. timeout)
                if (tor_process != null) {
                    tor_process.force_exit();
                    tor_process = null;
                }
                is_running = false;
                is_starting = false;
            }
        }
        
        private async void wait_until_port_open(int port) {
            debug("Waiting for Tor request port %d to open...", port);
            // Wait up to 20 seconds (200 * 100ms) - Bridges can be slow to initialize
            for (int i = 0; i < 200; i++) { 
                try {
                    Socket socket = new Socket(SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
                    InetAddress address = new InetAddress.from_string("127.0.0.1");
                    InetSocketAddress socket_address = new InetSocketAddress(address, (uint16)port);
                    
                    if (socket.connect(socket_address)) {
                        socket.close();
                        debug("Tor request port %d is open!", port);
                        return;
                    }
                } catch (Error e) {
                    // Ignore connection refused, keep waiting
                }
                
                // Yield to main loop properly so IO can happen
                Timeout.add(100, () => {
                    wait_until_port_open.callback();
                    return false;
                });
                yield;
            }
            warning("Timed out waiting for Tor port %d to open.", port);
        }

        public void stop() {
            if (tor_process != null) {
                tor_process.force_exit();
                tor_process = null;
            }
            is_running = false;
            is_starting = false;
        }

        private async void monitor_process(Subprocess proc) {
            try {
                // Read stderr AND stdout while waiting
                var stderr_pipe = new DataInputStream(proc.get_stderr_pipe());
                var stdout_pipe = new DataInputStream(proc.get_stdout_pipe());
                
                // We create a background task to read logs
                read_logs.begin(stderr_pipe, "STDERR");
                read_logs.begin(stdout_pipe, "STDOUT");

                yield proc.wait_async();
                
                if (this.tor_process == proc) { // if still the active process
                    int status = proc.get_exit_status();
                    warning("Tor process exited unexpectedly with status: %d", status);
                    if (status != 0) {
                        warning("--- Last Tor Logs ---");
                        foreach (string l in last_log_lines) {
                            warning("%s", l);
                        }
                        warning("---------------------");
                    }
                    is_running = false;
                    tor_process = null;
                    process_exited(status);
                }
            } catch (Error e) {
                warning("Error waiting for Tor process: %s", e.message);
            }
        }

        private async void read_logs(DataInputStream pipe, string type) {
            try {
                // Set the input stream to non-blocking to ensure we don't hang if there's no output initially?
                // Actually, read_line_async is fine. But we need to make sure we catch everything.
                string? line;
                Regex? bootstrap_regex = null;
                try {
                     bootstrap_regex = new Regex("Bootstrapped (\\d+)% \\((.+?)\\): (.+)");
                } catch (Error e) { warning("Regex error: %s", e.message); }

                while ((line = yield pipe.read_line_async()) != null) {
                    
                    if (bootstrap_regex != null && line.contains("Bootstrapped")) {
                        MatchInfo info;
                        if (bootstrap_regex.match(line, 0, out info)) {
                            int percent = int.parse(info.fetch(1));
                            string summary = info.fetch(3);
                            bootstrap_status(percent, summary);
                        }
                    }

                    string log_entry = "[Tor %s] %s".printf(type, line);
                    debug("%s", log_entry);
                    last_log_lines.add(log_entry);
                    if (last_log_lines.size > 20) last_log_lines.remove_at(0);
                }
            } catch (Error e) {
                 debug("[TOR-READ-ERROR-%s] %s", type, e.message);
            }
        }

    }
}
