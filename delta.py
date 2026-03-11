import asyncio
import time
import json
import logging
import os
import sys
import hashlib
import subprocess
import requests
import threading
import flet as ft
from datetime import datetime, timedelta, timezone
from uuid import getnode as get_mac
from pymodbus.client import AsyncModbusTcpClient, ModbusTcpClient
from pymodbus import FramerType

# --- CONFIGURACIÓN DE LOGGING ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s',
                    handlers=[logging.FileHandler("bridge_errors.log")])
logger = logging.getLogger("ModbusBridge")

API_BASE = "https://portal.synteck.org/api/public/licensing"
LICENSE_FILE = "license.dat"
CONFIG_FILE = "config.json"

class BridgeApp:
    def __init__(self):
        self.is_running = False
        self.loop = None
        self.config = self.load_initial_config()
        self.license_status = "Verificando..."
        self.days_remaining = 0
        self.uid, self.mac = self.get_hw_info()
        
    def load_initial_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f: return json.load(f)
            except: pass
        return {"plc_delta": {"ip": "192.168.0.1"}, "factory_io": {"ip": "127.0.0.1"}}

    def get_hw_info(self):
        try:
            mac = ':'.join(['{:02x}'.format((get_mac() >> i) & 0xff) for i in range(0, 8*6, 8)][::-1])
            cmd = "wmic csproduct get uuid"
            uuid = subprocess.check_output(cmd, shell=True).decode().split('\n')[1].strip()
            uid = hashlib.sha256(f"{mac}-{uuid}".encode()).hexdigest()[:20]
            return uid, mac
        except: return "ERROR-ID", "00:00:00:00:00:00"

    def save_config(self, plc_ip, fio_ip):
        self.config["plc_delta"]["ip"] = plc_ip
        self.config["factory_io"]["ip"] = fio_ip
        with open(CONFIG_FILE, "w") as f:
            json.dump(self.config, f, indent=4)

async def main(page: ft.Page):
    app = BridgeApp()
    page.title = "Deep Reef Modbus Gateway v4.0"
    page.window_width = 420
    page.window_height = 700
    page.theme_mode = ft.ThemeMode.DARK
    page.bgcolor = "#121212"
    page.window_resizable = False
    page.padding = 20

    # --- UI STATE ELEMENTS ---
    status_icon = ft.Icon(icon="power_settings_new", color="white", size=48)
    status_text = ft.Text("Listo para iniciar", size=18, weight=ft.FontWeight.BOLD)
    plc_ip_entry = ft.TextField(label="IP PLC Delta", value=app.config["plc_delta"]["ip"], 
                              border_color="#1a73e8", focused_border_color="#4285f4", prefix_icon="lan")
    fio_ip_entry = ft.TextField(label="IP Factory I/O", value=app.config["factory_io"]["ip"], 
                              border_color="#1a73e8", focused_border_color="#4285f4", prefix_icon="computer")
    license_badge = ft.Text("Licencia: Verificando...", size=14, color="grey")
    terminal = ft.ListView(expand=1, spacing=5, padding=10, auto_scroll=True)

    def log_ui(msg):
        t = datetime.now().strftime("%H:%M:%S")
        terminal.controls.append(ft.Text(f"[{t}] {msg}", size=12, color="green" if "OK" in msg else "white"))
        page.update()

    async def bridge_logic():
        log_ui("Conectando con dispositivos...")
        
        # Get settings from config
        plc_conf = app.config.get("plc_delta", {})
        fio_conf = app.config.get("factory_io", {})
        
        plc_ip = plc_ip_entry.value
        plc_port = plc_conf.get("port", 502)
        plc_framer = plc_conf.get("framer", "tcp")
        
        fio_ip = fio_ip_entry.value
        fio_port = fio_conf.get("port", 502)

        # Framer selection
        framer_obj = FramerType.ASCII if plc_framer.lower() == "ascii" else FramerType.SOCKET
        
        c1 = AsyncModbusTcpClient(plc_ip, port=plc_port, timeout=2, framer=framer_obj)
        c2 = AsyncModbusTcpClient(fio_ip, port=fio_port, timeout=2)
        
        while app.is_running:
            try:
                if not c1.connected: await c1.connect()
                if not c2.connected: await c2.connect()

                if c1.connected and c2.connected:
                    # Delta PLC X addresses start at 1024
                    res_x = await c1.read_discrete_inputs(address=1024, count=10, slave=1)
                    if not res_x.isError():
                        await c2.write_coils(address=0, values=res_x.bits[:10], slave=1)
                        if status_text.value != "BRIDGE ACTIVO":
                            status_text.value = "BRIDGE ACTIVO"
                            status_text.color = "green"
                            status_icon.color = "green"
                            page.update()
                    else:
                        log_ui("❌ Error de lectura en PLC (X1024)")
                else:
                    status_text.value = "CONECTANDO..."
                    status_text.color = "orange"
                    page.update()
                
                await asyncio.sleep(0.1)
            except Exception as e:
                log_ui(f"⚠️ Error: {str(e)}")
                await asyncio.sleep(2)
        
        await c1.close()
        await c2.close()

    def handle_toggle(e):
        if not app.is_running:
            app.is_running = True
            app.save_config(plc_ip_entry.value, fio_ip_entry.value)
            btn_start.text = "DETENER PUENTE"
            btn_start.bgcolor = "red"
            status_icon.color = "blue"
            asyncio.create_task(bridge_logic())
        else:
            app.is_running = False
            btn_start.text = "INICIAR PUENTE"
            btn_start.bgcolor = "#1a73e8"
            status_text.value = "Listo para iniciar"
            status_text.color = "white"
            status_icon.color = "white"
        page.update()

    # --- LICENSE DIALOG ---
    async def handle_reg(e):
        name = reg_name.value.strip()
        mail = reg_mail.value.strip()
        if not name or "@" not in mail: return
        try:
            loop = asyncio.get_event_loop()
            res = await loop.run_in_executor(None, lambda: requests.post(f"{API_BASE}/register", json={
                "hw_id": app.uid, "mac": app.mac, "product": "delta-fio-bridge",
                "client_name": name, "client_email": mail
            }, timeout=10))
            if res.status_code == 200:
                dlg_reg.open = False
                await check_license_task()
            else: log_ui("Fallo en registro")
        except: log_ui("Servidor no disponible")
        page.update()

    reg_name = ft.TextField(label="Nombre o Empresa")
    reg_mail = ft.TextField(label="Correo Electrónico")
    dlg_reg = ft.AlertDialog(
        modal=True, title=ft.Text("Registro de Deep Reef"),
        content=ft.Column([ft.Text("Capture sus datos para activar el trial."), reg_name, reg_mail], height=200),
        actions=[ft.ElevatedButton("Comenzar Trial", on_click=handle_reg)],
    )

    async def check_license_task():
        # Check Cache first
        if os.path.exists(LICENSE_FILE):
            try:
                with open(LICENSE_FILE, "r") as f:
                    cache = json.load(f)
                if cache["status"] == "active" and cache["hw_id"] == app.uid:
                    license_badge.value = "✅ LICENCIA: ACTIVA"
                    license_badge.color = "green"
                    page.update()
                    return
            except: pass

        try:
            # Running in executor to avoid blocking the main event loop
            loop = asyncio.get_event_loop()
            res = await loop.run_in_executor(None, lambda: requests.post(f"{API_BASE}/check", json={"hw_id": app.uid}, timeout=5))
            if res.status_code == 200:
                data = res.json()
                app.license_status = data["status"]
                if data["status"] == "trial":
                    license_badge.value = f"⏳ MODO TRIAL ({data['remaining_days']} días)"
                    license_badge.color = "#1a73e8"
                elif data["status"] == "active":
                    license_badge.value = "✅ LICENCIA: ACTIVA"
                    license_badge.color = "green"
            elif res.status_code == 404:
                page.dialog = dlg_reg
                dlg_reg.open = True
        except: license_badge.value = "⚠️ Validación Offline"
        page.update()

    # --- UI LAYOUT ---
    btn_start = ft.ElevatedButton("INICIAR PUENTE", on_click=handle_toggle, 
                                 bgcolor="#1a73e8", color="white", height=50, width=250)

    page.add(
        ft.Column([
            ft.Container(
                content=ft.Column([
                    ft.Text("DEEP REEF", size=32, weight=ft.FontWeight.BOLD, color="#1a73e8"),
                    ft.Text("Modbus Gateway for Factor I/O", size=14, color="grey"),
                ], horizontal_alignment="center", spacing=0),
                alignment=ft.alignment.center, margin=ft.margin.only(bottom=20)
            ),
            ft.Container(
                content=ft.Column([
                    status_icon,
                    status_text,
                ], horizontal_alignment="center"),
                bgcolor="#1e1e1e", padding=20, border_radius=20, alignment=ft.alignment.center
            ),
            ft.Container(height=10),
            plc_ip_entry,
            fio_ip_entry,
            ft.Container(height=10),
            ft.Row([btn_start], alignment="center"),
            ft.Container(height=10),
            ft.Container(
                content=terminal, bgcolor="#000000", border_radius=10, height=150, border=ft.border.all(1, "#333333")
            ),
            ft.Divider(height=20, color="transparent"),
            ft.Row([license_badge], alignment="center"),
            ft.Row([ft.Text(f"HWID: {app.uid[:10]}...", size=10, color="grey")], alignment="center")
        ], spacing=15)
    )

    # Start licensing check
    await check_license_task()

if __name__ == "__main__":
    ft.app(target=main)



