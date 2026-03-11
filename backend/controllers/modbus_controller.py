import asyncio
import logging
from pymodbus.client import AsyncModbusTcpClient, AsyncModbusSerialClient
from pymodbus import FramerType

logger = logging.getLogger("ModbusController")

class ModbusClientController:
    """Manages a single Modbus TCP or Serial connection."""
    
    def __init__(self, mode="tcp", **kwargs):
        self.mode = mode
        self.config = kwargs
        self.is_connected = False
        
        if mode == "tcp":
            host = kwargs.get("host", "127.0.0.1")
            port = kwargs.get("port", 502)
            timeout = kwargs.get("timeout", 2)
            framer_type = kwargs.get("framer", "tcp")
            framer = FramerType.ASCII if framer_type.lower() == "ascii" else FramerType.SOCKET
            self.client = AsyncModbusTcpClient(host, port=port, timeout=timeout, framer=framer)
        else:
            # Serial Mode
            port = kwargs.get("host") # In serial mode, host parameter is the COM port
            baudrate = int(kwargs.get("baudrate", 9600))
            parity = kwargs.get("parity", "N")
            stopbits = int(kwargs.get("stopbits", 1))
            bytesize = int(kwargs.get("bytesize", 8))
            timeout = kwargs.get("timeout", 2)
            framer_type = kwargs.get("framer", "rtu")
            framer = FramerType.ASCII if framer_type.lower() == "ascii" else FramerType.RTU
            
            self.client = AsyncModbusSerialClient(
                port,
                framer=framer,
                baudrate=baudrate,
                parity=parity,
                stopbits=stopbits,
                bytesize=bytesize,
                timeout=timeout
            )

    @property
    def host_info(self):
        return self.config.get("host", "Unknown")

    async def connect(self):
        try:
            # Defensive check: some versions of pymodbus might return None or a non-awaitable
            # if already connected or in certain states
            if not self.client.connected:
                res = self.client.connect()
                if asyncio.iscoroutine(res) or asyncio.isfuture(res) or hasattr(res, '__await__'):
                    self.is_connected = await res
                else:
                    self.is_connected = res
            return self.is_connected
        except Exception as e:
            logger.error(f"Connect error: {e}")
            return False

    async def disconnect(self):
        try:
            self.client.close() # In pymodbus async clients, close() is usually synchronized
        except: pass
        self.is_connected = False

    def get_details(self):
        """Returns string representation of the controller settings."""
        if self.mode == "tcp":
            return f"TCP {self.config.get('host')}:{self.config.get('port', 502)} ({self.config.get('framer', 'tcp')})"
        else:
            return f"Serial {self.config.get('host')} {self.config.get('baudrate', 9600)},{self.config.get('parity', 'N')},{self.config.get('bytesize', 8)},{self.config.get('stopbits', 1)}"

    async def read_data(self, slave_id, function_code, address, count):
        """Standard Modbus read operations."""
        if not self.client.connected:
            return {"status": "error", "message": "Dispositivo no conectado"}
            
        try:
            res = None
            if function_code == 1: # Read Coils
                res = await self.client.read_coils(address=address, count=count, device_id=slave_id)
            elif function_code == 2: # Read Discrete Inputs
                res = await self.client.read_discrete_inputs(address=address, count=count, device_id=slave_id)
            elif function_code == 3: # Read Holding Registers
                res = await self.client.read_holding_registers(address=address, count=count, device_id=slave_id)
            elif function_code == 4: # Read Input Registers
                res = await self.client.read_input_registers(address=address, count=count, device_id=slave_id)
            
            if res is None:
                return {"status": "error", "message": "No response from device (Timeout)"}
            
            if res.isError():
                return {"status": "error", "message": f"Modbus Error: {res}"}
            
            if function_code in [1, 2]:
                return {"status": "ok", "values": res.bits[:count]}
            else:
                return {"status": "ok", "values": res.registers[:count]}
                
        except Exception as e:
            return {"status": "error", "message": str(e)}

    async def write_data(self, slave_id, function_code, address, values):
        """Standard Modbus write operations."""
        if not self.client.connected:
            return {"status": "error", "message": "Dispositivo no conectado"}
        
        try:
            res = None
            if function_code == 5: # Write Single Coil
                res = await self.client.write_coil(address=address, value=values[0], device_id=slave_id)
            elif function_code == 6: # Write Single Register
                res = await self.client.write_register(address=address, value=values[0], device_id=slave_id)
            elif function_code == 15: # Write Multiple Coils
                res = await self.client.write_coils(address=address, values=values, device_id=slave_id)
            elif function_code == 16: # Write Multiple Registers
                res = await self.client.write_registers(address=address, values=values, device_id=slave_id)
            
            if res is None:
                return {"status": "error", "message": "No response from device (Timeout)"}
                
            if res.isError():
                return {"status": "error", "message": f"Modbus Error: {res}"}
                
            return {"status": "ok", "message": "Escritura Exitosa"}
        except Exception as e:
            return {"status": "error", "message": str(e)}
