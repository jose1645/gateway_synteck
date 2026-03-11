import psutil
import serial.tools.list_ports

def get_network_interfaces():
    """Returns a list of available network interfaces (IPv4)."""
    interfaces = []
    addrs = psutil.net_if_addrs()
    for name, info in addrs.items():
        for addr in info:
            if addr.family == 2:  # AF_INET (IPv4)
                interfaces.append({
                    "name": name,
                    "ip": addr.address
                })
    return interfaces

def get_serial_ports():
    """Returns a list of available COM/Serial ports with detailed hardware info."""
    ports = serial.tools.list_ports.comports()
    result = []
    for p in ports:
        desc = p.description if p.description else "Unknown Device"
        manufacturer = p.manufacturer if p.manufacturer else "Unknown Manufacturer"
        result.append({
            "port": p.device,
            "description": desc,
            "manufacturer": manufacturer,
            "hwid": p.hwid
        })
    return result
