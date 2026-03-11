import hashlib
import subprocess
from uuid import getnode as get_mac

def get_hw_id():
    """Returns a unique 20-char Hardware ID based on MAC and UUID."""
    try:
        mac = ':'.join(['{:02x}'.format((get_mac() >> i) & 0xff) for i in range(0, 8*6, 8)][::-1])
        cmd = "wmic csproduct get uuid"
        uuid = subprocess.check_output(cmd, shell=True).decode().split('\n')[1].strip()
        return hashlib.sha256(f"{mac}-{uuid}".encode()).hexdigest()[:20]
    except Exception:
        return "UNKNOWN-HARDWARE-ID"
