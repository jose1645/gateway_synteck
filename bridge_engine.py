import asyncio
import json
import logging
import os
import sys
import hashlib
import subprocess
from datetime import datetime
from uuid import getnode as get_mac
from pymodbus.client import AsyncModbusTcpClient
from pymodbus import FramerType

# Logging configurado para archivo
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s',
                    handlers=[logging.FileHandler("bridge_engine.log")])
logger = logging.getLogger("BridgeEngine")

CONFIG_FILE = "config.json"

class ModbusEngine:
    def __init__(self):
        self.is_running = False
        self.config = self.load_config()
        self.hw_id = self.get_hw_id()

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f: return json.load(f)
            except: pass
        return {
            "plc_delta": {"ip": "192.168.0.1", "port": 502, "framer": "tcp"},
            "factory_io": {"ip": "127.0.0.1", "port": 502}
        }

    def get_hw_id(self):
        try:
            mac = ':'.join(['{:02x}'.format((get_mac() >> i) & 0xff) for i in range(0, 8*6, 8)][::-1])
            cmd = "wmic csproduct get uuid"
            uuid = subprocess.check_output(cmd, shell=True).decode().split('\n')[1].strip()
            return hashlib.sha256(f"{mac}-{uuid}".encode()).hexdigest()[:20]
        except: return "UNKNOWN-ID"

    def send_status(self, status, msg="", data=None):
        """Envía el estado actual por stdout en formato JSON para que Flutter lo lea."""
        print(json.dumps({
            "status": status,
            "message": msg,
            "data": data,
            "timestamp": datetime.now().isoformat()
        }), flush=True)

    async def run(self):
        self.is_running = True
        plc_conf = self.config.get("plc_delta", {})
        fio_conf = self.config.get("factory_io", {})

        framer = FramerType.ASCII if plc_conf.get("framer", "tcp").lower() == "ascii" else FramerType.SOCKET
        
        c1 = AsyncModbusTcpClient(plc_conf.get("ip"), port=plc_conf.get("port", 502), timeout=2, framer=framer)
        c2 = AsyncModbusTcpClient(fio_conf.get("ip"), port=fio_conf.get("port", 502), timeout=2)

        self.send_status("starting", "Iniciando comunicación Modbus...")

        while self.is_running:
            try:
                if not c1.connected: await c1.connect()
                if not c2.connected: await c2.connect()

                if c1.connected and c2.connected:
                    # Lectura X1024 (Inputs Delta) -> Escritura Coils 0 (Inputs FIO)
                    res_x = await c1.read_discrete_inputs(address=1024, count=10, slave=1)
                    if not res_x.isError():
                        await c2.write_coils(address=0, values=res_x.bits[:10], slave=1)
                        self.send_status("active", "Bridge funcionando OK", {"bits": res_x.bits[:10]})
                    else:
                        self.send_status("error", "Error de lectura en PLC (X1024)")
                else:
                    self.send_status("connecting", "Buscando dispositivos...")
                
                await asyncio.sleep(0.1)
            except Exception as e:
                self.send_status("critical", str(e))
                await asyncio.sleep(2)
        
        await c1.close()
        await c2.close()

if __name__ == "__main__":
    engine = ModbusEngine()
    try:
        asyncio.run(engine.run())
    except KeyboardInterrupt:
        pass
