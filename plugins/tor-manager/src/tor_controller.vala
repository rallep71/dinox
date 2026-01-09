using GLib;

namespace Dino.Plugins.TorManager {

    public class TorController : Object {
        private Subprocess? tor_process;
        // private DataInputStream? control_stream;

        public bool is_running { get; private set; default = false; }
        public int socks_port { get; private set; default = 9155; }
        public string bridge_lines { get; set; default = ""; }
        
        public signal void process_exited(int status);

        public TorController() {
            // Check if Tor is available
            check_installation();
        }

        ~TorController() {
            stop();
        }

        private void check_installation() {
            try {
                // Determine path to 'tor' executable
                // In Flatpak, it should be in /app/bin/tor or /usr/bin/tor
                string[] argv = {"tor", "--version"};
                Subprocess proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                proc.wait(null);
                if (proc.get_if_exited() && proc.get_exit_status() == 0) {
                    warning("Tor executable found.");
                } else {
                    warning("Tor executable NOT found or errored.");
                }
            } catch (Error e) {
                warning("Error checking for Tor: %s", e.message);
            }
        }

        public async void start() {
            if (is_running) return;

            string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dino", "tor");
            DirUtils.create_with_parents(data_dir, 0700);
            
            // ROBUST ZOMBIE KILLER: Force kill any previous instance by pattern, not just PID file
            try {
                // We look for any process running with our specific config file path.
                // "pkill -f" matches against the full command line.
                string[] kill_cmd = {"pkill", "-9", "-f", "dino/tor/torrc"};
                new Subprocess.newv(kill_cmd, SubprocessFlags.NONE).wait(null);
                
                // Give the OS a moment to reclaim the port (9155)
                Thread.usleep(300000); // 300ms
                
                warning("TorController: Zombie cleanup routine executed.");
            } catch (Error e) {
                // Ignored: pkill might fail if no process exists, which is good.
                message("TorController: No zombies found or pkill unavailable: %s", e.message);
            }

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

            if (bridge_lines.strip() != "") {
                string? obfs4_path = Environment.find_program_in_path("obfs4proxy");
                if (obfs4_path == null) {
                     // Check common locations if not in PATH
                     string[] locs = {"/app/bin/obfs4proxy", "/usr/bin/obfs4proxy", "/usr/local/bin/obfs4proxy"};
                     foreach(string l in locs) {
                        if (FileUtils.test(l, FileTest.EXISTS)) {
                            obfs4_path = l;
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
                warning("[TOR-DEBUG] Writing torrc to: %s", torrc_path);
                warning("[TOR-DEBUG] Content:\n%s", torrc.str);
            } catch (Error e) {
                warning("Failed to write torrc: %s", e.message);
                return;
            }

            string[] argv = {"tor", "-f", torrc_path};

            try {
                tor_process = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                is_running = true;
                warning("Tor process started with PID: %s", tor_process.get_identifier());
                
                // Monitor the process
                monitor_process.begin();
            } catch (Error e) {
                warning("Failed to start Tor: %s", e.message);
                is_running = false;
            }
        }

        public void stop() {
            if (tor_process != null) {
                tor_process.force_exit();
                tor_process = null;
            }
            is_running = false;
        }

        private async void monitor_process() {
            try {
                // Read stderr while waiting
                var stderr_pipe = new DataInputStream(tor_process.get_stderr_pipe());
                
                // We create a background task to read stderr logs
                read_logs.begin(stderr_pipe);

                yield tor_process.wait_async();
                
                if (tor_process != null) { // if not manually stopped
                    int status = tor_process.get_exit_status();
                    warning("Tor process exited unexpectedly with status: %d", status);
                    is_running = false;
                    tor_process = null;
                    process_exited(status);
                }
            } catch (Error e) {
                warning("Error waiting for Tor process: %s", e.message);
            }
        }

        private async void read_logs(DataInputStream pipe) {
            try {
                // Set the input stream to non-blocking to ensure we don't hang if there's no output initially?
                // Actually, read_line_async is fine. But we need to make sure we catch everything.
                string? line;
                while ((line = yield pipe.read_line_async()) != null) {
                    // PRINTING TO STDOUT/STDERR FORCEFULLY TO BYPASS LOG LEVEL FILTERING
                    GLib.stderr.printf("[TOR-STDERR] %s\n", line);
                    warning("[Tor Output] %s", line);
                }
            } catch (Error e) {
                 GLib.stderr.printf("[TOR-READ-ERROR] %s\n", e.message);
            }
        }
    }
}
