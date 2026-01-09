import socket
import struct
import sys

def test_socks5(proxy_host, proxy_port, target_host, target_port):
    print(f"Testing SOCKS5 Proxy at {proxy_host}:{proxy_port} -> {target_host}:{target_port}")
    
    try:
        # 1. Connect to Proxy
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect((proxy_host, proxy_port))
        print("Connected to proxy server.")

        # 2. SOCKS5 Handshake (Method selection)
        # Version 5, 1 Method, Method 0 (No auth)
        sock.sendall(b'\x05\x01\x00')
        response = sock.recv(2)
        if response != b'\x05\x00':
            print(f"Handshake failed or authentication required: {response}")
            return
        print("Handshake successful (No Auth).")

        # 3. Request Connection
        # Version 5, Cmd 1 (Connect), Rsv 0, AddrType 3 (Domain name), Len, Domain, Port
        port_bytes = struct.pack('>H', target_port)
        host_bytes = target_host.encode('utf-8')
        cmd = b'\x05\x01\x00\x03' + bytes([len(host_bytes)]) + host_bytes + port_bytes
        
        sock.sendall(cmd)
        print(f"Sent connection request for {target_host}...")
        
        # 4. Read Response
        resp = sock.recv(4) # Version, Rep, Rsv, Atyp
        if len(resp) < 4:
            print("Proxy closed connection prematurely.")
            return

        if resp[1] != 0:
            print(f"Proxy returned error code: {resp[1]}")
            return
            
        print("Proxy established connection successfully!")
        
        # Consuming the rest of the response (Address + Port)
        addr_type = resp[3]
        if addr_type == 1: # IPv4
            sock.recv(4 + 2)
        elif addr_type == 3: # Domain
            l = sock.recv(1)[0]
            sock.recv(l + 2)
        elif addr_type == 4: # IPv6
            sock.recv(16 + 2)

        print("Test passed.")
        sock.close()

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_socks5("127.0.0.1", 9050, "check.torproject.org", 443)
