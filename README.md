# Deep Reef - Modbus Bridge (Delta PLC to Factory I/O)

Este software actúa como un puente de alto rendimiento entre un PLC Delta y Factory I/O.

## 🚀 Instalación Rápida
1. Coloque el archivo `Delta-FIO-Bridge.exe` y `config.json` en la misma carpeta.
2. Configure las IPs y puertos en `config.json` usando cualquier editor de texto (Bloc de Notas).
3. Ejecute `Delta-FIO-Bridge.exe`.

## ⚙️ Configuración (`config.json`)
- **`plc_delta`**:
    - `ip`: Dirección IP del PLC o simulador (ej: `127.0.0.1` para simulador).
    - `port`: Puerto Modbus (Default Delta: `10003`).
    - `framer`: `ascii` o `socket`.
- **`factory_io`**:
    - `ip`: Dirección IP donde corre Factory I/O (ej: `192.168.18.29`).
    - `port`: Puerto Modbus (Default FIO: `502`).

## 🛠 Soporte y Logs
Si hay errores de comunicación, el programa generará automáticamente un archivo `bridge_errors.log`. Revise este archivo para diagnosticar problemas de red o de registros.

---
*Producto desarrollado por Deep Reef Automation*
