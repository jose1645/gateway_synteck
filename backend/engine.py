import asyncio
import json
import os
import sys
import logging
from datetime import datetime

# Add the project root to sys.path to allow importing from backend modules
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from backend.utils.hwid import get_hw_id
from backend.utils.scanner import get_network_interfaces, get_serial_ports
from backend.controllers.modbus_controller import ModbusClientController

# Setup Logging - More Verbose for Debugging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s [%(levelname)s] %(message)s',
                    handlers=[logging.FileHandler("backend_engine.log")])
logger = logging.getLogger("ModbusEngine")

class ModbusEngine:
    def __init__(self):
        self.controllers = {} # connection_id: ModbusClientController
        self.polls = {} # poll_id: {connection_id, slave_id, function, address, count, rate, last_run}
        self.is_running = True
        self.hw_id = get_hw_id()

    def send_to_flutter(self, event_type, data):
        """Sends data to Flutter in JSON format through stdout."""
        msg = json.dumps({
            "event": event_type,
            "data": data,
            "hw_id": self.hw_id,
            "timestamp": datetime.now().isoformat()
        })
        print(msg, flush=True)

    async def poll_task(self):
        """Infinite loop to periodically scan all active polls."""
        while self.is_running:
            for poll_id, poll_def in list(self.polls.items()):
                conn_id = poll_def['connection_id']
                controller = self.controllers.get(conn_id)
                
                if controller and controller.is_connected:
                    now = datetime.now()
                    if (now - poll_def['last_run']).total_seconds() * 1000 >= poll_def['rate']:
                        try:
                            res_coro = controller.read_data(
                                poll_def['slave_id'],
                                poll_def['function'],
                                poll_def['address'],
                                poll_def['count']
                            )
                            
                            if asyncio.iscoroutine(res_coro) or asyncio.isfuture(res_coro) or hasattr(res_coro, '__await__'):
                                res = await res_coro
                            else:
                                res = res_coro
                            
                            self.send_to_flutter("poll_update", {
                                "id": poll_id,
                                "connection_id": conn_id,
                                "status": res["status"],
                                "message": res.get("message", "OK"),
                                "values": res.get("values", [])
                            })
                        except Exception as e:
                            logger.error(f"Poll Error ({poll_id}) on {conn_id}: {e}")
                            self.send_to_flutter("poll_update", {
                                "id": poll_id,
                                "connection_id": conn_id,
                                "status": "error",
                                "message": str(e)
                            })
                        poll_def['last_run'] = now
            
            await asyncio.sleep(0.01)

    async def handle_input(self):
        """Listen to commands from Flutter via stdin."""
        while self.is_running:
            try:
                loop = asyncio.get_event_loop()
                line = await loop.run_in_executor(None, sys.stdin.readline)
                if not line: break
                
                cmd_data = json.loads(line)
                action = cmd_data.get("action")
                params = cmd_data.get("params", {})
                
                logger.debug(f"Received action: {action} with params: {params}")

                if action == "scan_interfaces":
                    self.send_to_flutter("interfaces_data", {
                        "network": get_network_interfaces(),
                        "serial": get_serial_ports()
                    })

                elif action == "connect":
                    conn_id = params.get("connection_id")
                    host = params.get("host")
                    mode = params.get("mode", "tcp")

                    # Check for existing connection to same physical port/host
                    existing_ctrl = None
                    existing_id = None
                    for cid, ctrl in self.controllers.items():
                        if ctrl.mode == mode and ctrl.config.get("host") == host:
                            existing_ctrl = ctrl
                            existing_id = cid
                            break
                    
                    if existing_ctrl:
                        conn_id = existing_id
                        connected = existing_ctrl.is_connected
                        if not connected:
                            # Try to reconnect if it was disconnected
                            res_conn = existing_ctrl.connect()
                            if asyncio.iscoroutine(res_conn) or asyncio.isfuture(res_conn) or hasattr(res_conn, '__await__'):
                                connected = await res_conn
                            else:
                                connected = res_conn
                    else:
                        if not conn_id:
                            conn_id = f"conn_{len(self.controllers) + 1}"
                        
                        mode_pop = params.pop("mode", "tcp")
                        controller = ModbusClientController(mode=mode_pop, **params)
                        
                        res_conn = controller.connect()
                        if asyncio.iscoroutine(res_conn) or asyncio.isfuture(res_conn) or hasattr(res_conn, '__await__'):
                            connected = await res_conn
                        else:
                            connected = res_conn
                        
                        if connected:
                            self.controllers[conn_id] = controller
                    
                    self.send_to_flutter("connection_status", {
                        "connection_id": conn_id,
                        "status": "connected" if connected else "error",
                        "message": "Conectado (Reutilizado)" if existing_id else ("Conectado" if connected else "Fallo Connection"),
                        "details": self.controllers[conn_id].get_details() if connected else "Error",
                        "config": params
                    })
                
                elif action == "sync_connections":
                    # Send all current connections to Flutter
                    conns_data = []
                    for cid, ctrl in self.controllers.items():
                        conns_data.append({
                            "connection_id": cid,
                            "status": "connected" if ctrl.is_connected else "error",
                            "details": ctrl.get_details(),
                            "config": ctrl.config
                        })
                    self.send_to_flutter("connections_list", conns_data)

                elif action == "disconnect":
                    conn_id = params.get("connection_id")
                    if conn_id in self.controllers:
                        res_dis = self.controllers[conn_id].disconnect()
                        if asyncio.iscoroutine(res_dis) or asyncio.isfuture(res_dis) or hasattr(res_dis, '__await__'):
                            await res_dis
                        del self.controllers[conn_id]
                        # Optional: Remove polls associated with this connection
                        self.polls = {pid: pdef for pid, pdef in self.polls.items() if pdef['connection_id'] != conn_id}
                        self.send_to_flutter("connection_status", {
                            "connection_id": conn_id,
                            "status": "disconnected", 
                            "message": "Desconectado"
                        })

                elif action == "define_poll":
                    poll_id = params.get("id")
                    conn_id = params.get("connection_id")
                    self.polls[poll_id] = {
                        "connection_id": conn_id,
                        "slave_id": params.get("slave_id", 1),
                        "function": params.get("function", 3),
                        "address": params.get("address", 0),
                        "count": params.get("count", 10),
                        "rate": params.get("rate", 1000),
                        "last_run": datetime.now()
                    }
                    self.send_to_flutter("poll_defined", {"id": poll_id, "connection_id": conn_id})

                elif action == "remove_poll":
                    poll_id = params.get("id")
                    if poll_id in self.polls: del self.polls[poll_id]
                    self.send_to_flutter("poll_removed", {"id": poll_id})

                elif action == "write":
                    conn_id = params.get("connection_id")
                    controller = self.controllers.get(conn_id)
                    if controller:
                        # slave, function, address, values
                        res_w = controller.write_data(
                            params.get("slave_id", 1),
                            params.get("function", 6),
                            params.get("address", 0),
                            params.get("values", [0])
                        )
                        
                        if asyncio.iscoroutine(res_w) or asyncio.isfuture(res_w) or hasattr(res_w, '__await__'):
                            res = await res_w
                        else:
                            res = res_w
                            
                        self.send_to_flutter("write_response", {
                            "connection_id": conn_id,
                            "status": res["status"],
                            "message": res.get("message", "OK")
                        })
                    else:
                        self.send_to_flutter("write_response", {
                            "connection_id": conn_id,
                            "status": "error",
                            "message": "Controlador no encontrado"
                        })

            except Exception as e:
                import traceback
                error_trace = traceback.format_exc()
                logger.error(f"Input handling error: {e}\n{error_trace}")
                self.send_to_flutter("error", {"message": f"Engine Critical: {str(e)}", "trace": error_trace})

    async def main(self):
        self.send_to_flutter("engine_ready", {"hw_id": self.hw_id})
        await asyncio.gather(self.poll_task(), self.handle_input())

if __name__ == "__main__":
    engine = ModbusEngine()
    try:
        asyncio.run(engine.main())
    except KeyboardInterrupt: pass
