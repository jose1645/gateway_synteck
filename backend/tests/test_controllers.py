import sys
import os
import asyncio

# Añadir la raíz del proyecto al sys.path para que los tests puedan importar 'backend'
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from backend.controllers.modbus_controller import ModbusClientController

async def test_modbus_controller():
    print("Iniciando Suite de Pruebas: Modbus Controller...")
    
    # Pruebas de inicialización
    controller = ModbusClientController("127.0.0.1", port=502)
    assert controller.host == "127.0.0.1", "Error: Host incorrecto"
    assert controller.port == 502, "Error: Puerto incorrecto"
    print("  - Inicialización: PASSED")

    # Prueba de lectura (sin conexión debe fallar con mensaje controlado)
    res = await controller.read_data(1, 3, 0, 10)
    assert res["status"] == "error", "Error: Debería fallar sin conexión"
    print("  - Validación de estado desconectado: PASSED")

    print("\nSuite de Pruebas: FINALIZADA CON ÉXITO")

if __name__ == "__main__":
    asyncio.run(test_modbus_controller())
