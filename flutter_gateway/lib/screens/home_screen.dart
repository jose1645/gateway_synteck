import 'package:flutter/material.dart';
import '../models/poll_definition.dart';
import '../models/gateway_connection.dart';
import '../models/driver_node.dart';
import '../services/engine_service.dart';
import '../widgets/modbus_address_card.dart';
import '../models/asset_node.dart';
import '../services/tag_registry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EngineService _engine = EngineService();
  final TagRegistry _tagRegistry = TagRegistry();
  
  // App State
  final List<GatewayConnection> _connections = [];
  final List<PollDefinition> _polls = [];
  
  // Heirarchical State
  final Map<String, AssetNode> _connectionAssets = {}; // ConnID -> Root Node
  
  String _currentStep = "welcome"; // Start with Welcome/Hub
  DriverNode? _selectedDriver;
  String _physicalLayer = "Ethernet"; 
  String _protocol = "ASCII"; 
  
  // Temp Connection Selection
  String _selectedIp = "";
  String _selectedCom = "";
  
  // Serial Config
  String _baudrate = "9600";
  String _parity = "E";
  String _dataBits = "7";
  String _stopBits = "1";
  int _slaveId = 1;

  // Dynamic Lists
  List<dynamic> _networkInterfaces = [];
  List<dynamic> _serialPorts = [];
  bool _isScanning = false;
  bool _isEngineReady = false;
  String _engineStatus = "Iniciando motor...";

  @override
  void initState() {
    super.initState();
    _engine.init().then((_) {
      _engine.events.listen(_handleEngineEvent);
      // Wait a bit for engine_ready event
    });
  }

  void _refreshScanner() {
    if (!_isEngineReady) return;
    setState(() => _isScanning = true);
    _engine.sendCommand("scan_interfaces", {});
  }

  void _handleEngineEvent(Map<String, dynamic> event) {
    final type = event['event'];
    final data = event['data'];
    
    debugPrint("ENGINE EVENT: $type -> $data");

    setState(() {
      if (type == "engine_ready") {
        _isEngineReady = true;
        _engineStatus = "Motor LISTO";
        _refreshScanner();
      } else if (type == "error" || type == "critical") {
        String msg = "Error desconocido";
        if (data != null && data is Map && data.containsKey('message')) {
          msg = data['message'];
        } else if (event.containsKey('message')) {
          msg = event['message'];
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ ERROR MOTOR: $msg"), backgroundColor: Colors.redAccent)
        );
      } else if (type == "log") {
        debugPrint("PY_LOG: ${event['message']}");
      } else if (type == "interfaces_data") {
        _isScanning = false;
        if (data != null) {
          _networkInterfaces = data['network'] ?? [];
          _serialPorts = data['serial'] ?? [];
          if (_serialPorts.isNotEmpty && _selectedCom.isEmpty) _selectedCom = _serialPorts[0]['port'];
          if (_networkInterfaces.isNotEmpty && _selectedIp.isEmpty) _selectedIp = _networkInterfaces[0]['ip'];
        }
      } else if (type == "connection_status") {
        final connId = data['connection_id'];
        final status = data['status'];
        final message = data['message'];
        final details = data['details'] ?? "";
        
        final idx = _connections.indexWhere((c) => c.id == connId);
        if (idx != -1) {
          if (status == "disconnected") {
            _connections.removeAt(idx);
            _polls.removeWhere((p) => p.connectionId == connId);
            _connectionAssets.remove(connId);
            _tagRegistry.removeConnection(connId);
          } else {
            _connections[idx].status = status == "connected" ? "Conectado" : status;
            _connections[idx].statusColor = status == "connected" ? Colors.greenAccent : Colors.redAccent;
            _connections[idx].lastError = status == "error" ? message : "";
          }
        } else if (status == "connected") {
          _connections.add(GatewayConnection(
            id: connId,
            host: data['config']?['host'] ?? "Unknown",
            framer: data['config']?['framer'] ?? "tcp",
            details: details,
            status: "Conectado",
            statusColor: Colors.greenAccent,
            config: data['config'] ?? {},
          ));
          _connectionAssets[connId] = AssetNode(
            id: "root_$connId",
            name: data['config']?['host'] ?? "Gateway",
            type: NodeType.folder,
            children: [],
          );
        }
        _currentStep = "monitoring";
      } else if (type == "poll_update") {
        final pollId = data['id'];
        final index = _polls.indexWhere((p) => p.id == pollId);
        if (index != -1) {
          _polls[index].values = data['values'] ?? [];
          _polls[index].status = data['status'];
          _polls[index].message = data['message'] ?? "";
        }
      } else if (type == "write_response") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${data['status'] == 'ok' ? '✅' : '❌'} ${data['message']}"),
            backgroundColor: data['status'] == 'ok' ? Colors.green : Colors.red,
          )
        );
      }
    });
  }

  void _showWriteDialog(String connId, int address, dynamic currentValue) {
    final TextEditingController textController = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: Text("ESCRIBIR REGISTRO: $address", style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Conexión: $connId", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 20),
            TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: "Nuevo Valor",
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(textController.text) ?? 0;
              _engine.sendCommand("write", {
                "connection_id": connId,
                "slave_id": _slaveId,
                "function": 6, // Write Single Holding Register
                "address": address,
                "values": [val]
              });
              Navigator.pop(context);
            },
            child: const Text("ESCRIBIR"),
          ),
        ],
      ),
    );
  }

  void _addNewConnection() {
    final host = _physicalLayer == "Ethernet" ? _selectedIp : _selectedCom;
    final framer = _protocol.toLowerCase(); 
    final connId = "GW_${_connections.length + 1}";
    
    Map<String, dynamic> params = {
      "connection_id": connId,
      "mode": _physicalLayer.toLowerCase(),
      "host": host,
      "framer": framer,
      "slave_id": _slaveId, // Global Slave ID for this gateway
    };

    if (_physicalLayer == "Serial") {
      params.addAll({
        "baudrate": _baudrate,
        "parity": _parity,
        "bytesize": _dataBits,
        "stopbits": _stopBits,
      });
    }
    
    _engine.sendCommand("connect", params);
  }

  void _addPoll(String connectionId) {
    if (_selectedDriver?.id == "delta_dvp") {
      _showDeltaAddPollDialog(connectionId);
    } else {
      final id = "Poll_${_polls.length + 1}";
      final newPoll = PollDefinition(
        id: id, 
        connectionId: connectionId, 
        slaveId: _slaveId,
        count: 10, 
        rate: 500
      );
      setState(() => _polls.add(newPoll));
      _engine.sendCommand("define_poll", newPoll.toJson());
    }
  }

  void _showDeltaAddPollDialog(String connectionId) {
    String selectedType = "D"; // Default Data Register
    final TextEditingController indexController = TextEditingController(text: "0");
    final TextEditingController countController = TextEditingController(text: "10");
    final TextEditingController tagController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: const Text("AÑADIR MONITOREO DELTA", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedType,
              dropdownColor: const Color(0xFF1E1E26),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Tipo de Registro", labelStyle: TextStyle(color: Colors.grey)),
              items: ["X (Entrada)", "Y (Salida)", "M (Relé)", "D (Dato)", "S (Paso)", "T (Timer)", "C (Contador)"]
                  .map((t) => DropdownMenuItem(value: t.split(" ")[0], child: Text(t))).toList(),
              onChanged: (val) => selectedType = val!,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: indexController,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: Colors.blueAccent),
              decoration: const InputDecoration(
                labelText: "Índice (X/Y en Octal)", 
                labelStyle: TextStyle(color: Colors.grey),
                hintText: "Ej: 0, 10, 20...",
                hintStyle: TextStyle(color: Colors.white24)
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: countController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Cantidad", labelStyle: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tagController,
              style: const TextStyle(color: Colors.greenAccent),
              decoration: const InputDecoration(
                labelText: "Tag / Nombre (Opcional)", 
                labelStyle: TextStyle(color: Colors.grey),
                hintText: "Ej: Temp Calandria",
                hintStyle: TextStyle(color: Colors.white24)
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              int baseAddress = 0;
              int function = 3;
              int index = 0;
              
              String rawIdx = indexController.text;
              if (selectedType == "X" || selectedType == "Y") {
                index = int.tryParse(rawIdx, radix: 8) ?? 0;
              } else {
                index = int.tryParse(rawIdx) ?? 0;
              }

              switch (selectedType) {
                case "X": baseAddress = 0x0400; function = 2; break;
                case "Y": baseAddress = 0x0500; function = 1; break;
                case "M": baseAddress = 0x0800; function = 1; break;
                case "D": baseAddress = 0x1000; function = 3; break;
                case "S": baseAddress = 0x0000; function = 1; break;
                case "T": baseAddress = 0x0600; function = 1; break;
                case "C": baseAddress = 0x0E00; function = 1; break;
              }

              final int count = int.tryParse(countController.text) ?? 10;
              final int finalAddress = baseAddress + index;
              final String mainTag = tagController.text.trim();

              // Validation: Check for Address-Tag collisions
              if (mainTag.isNotEmpty) {
                for (int i = 0; i < count; i++) {
                  int addr = finalAddress + i;
                  if (!_tagRegistry.registerTag(connectionId, _slaveId, function, addr, mainTag)) {
                    Navigator.pop(context); // Close add dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error Lógico: La dirección Modbus $addr ya tiene un Tag diferente asignado. No se permiten duplicados."),
                        backgroundColor: Colors.redAccent,
                      )
                    );
                    return;
                  }
                }
              }

              setState(() {
                final id = "Poll_${_polls.length + 1}";
                final tag = mainTag.isNotEmpty ? mainTag : "$selectedType$rawIdx";
                Map<int, String> addressTags = {};
                
                final newPoll = PollDefinition(
                  id: id,
                  connectionId: connectionId,
                  slaveId: _slaveId,
                  function: function,
                  address: finalAddress,
                  count: count,
                  rate: 500,
                  tag: tag,
                  addressTags: addressTags,
                );
                
                _polls.add(newPoll);
                _engine.sendCommand("define_poll", newPoll.toJson());

                // Structural abstraction: Add to hierarchy
                if (_connectionAssets.containsKey(connectionId)) {
                   _connectionAssets[connectionId]!.children.add(AssetNode(
                      id: id,
                      name: tag,
                      type: NodeType.poll,
                      poll: newPoll,
                      parentId: "root_$connectionId",
                   ));
                }
              });
              Navigator.pop(context);
            },
            child: const Text("AÑADIR"),
          ),
        ],
      ),
    );
  }

  void _showTagEditor(PollDefinition poll) {
    Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < poll.count; i++) {
        int addr = poll.address + i;
        controllers[addr] = TextEditingController(text: poll.addressTags[addr] ?? "");
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: Text("TAGS INDIVIDUALES: ${poll.tag}", style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: poll.count,
            itemBuilder: (context, i) {
                int addr = poll.address + i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text("Reg $i:", style: const TextStyle(color: Colors.grey, fontSize: 10))),
                      Expanded(
                        child: TextField(
                          controller: controllers[addr],
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: "Nombre...",
                            hintStyle: TextStyle(color: Colors.white10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                controllers.forEach((addr, ctrl) {
                  if (ctrl.text.isNotEmpty) {
                    poll.addressTags[addr] = ctrl.text;
                  } else {
                    poll.addressTags.remove(addr);
                  }
                });
              });
              Navigator.pop(context);
            },
            child: const Text("GUARDAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        leading: _currentStep != "welcome" ? IconButton(
          icon: const Icon(Icons.home_filled),
          onPressed: () => setState(() => _currentStep = "welcome"),
        ) : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("SYNTECK GATEWAY SUITE v4.5", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 16)),
            Text(_engineStatus, style: TextStyle(fontSize: 10, color: _isEngineReady ? Colors.greenAccent : Colors.orangeAccent)),
          ],
        ),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshScanner),
          if (_currentStep == "monitoring" || _currentStep == "welcome")
          IconButton(
            icon: const Icon(Icons.add_link),
            onPressed: () => setState(() => _currentStep = "select_driver"),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentStep) {
      case "welcome":
        return _buildWelcomeView();
      case "select_driver":
        return _buildSelectDriver();
      case "select_layer":
        return _buildSelectLayer();
      case "setup_connection":
        return _buildSetupConnection();
      case "select_protocol":
        return _buildSelectProtocol();
      case "monitoring":
        return _buildMonitoring();
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildWelcomeView() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F0F13),
            const Color(0xFF1A1A2E).withOpacity(0.8),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: "logo",
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 40, spreadRadius: 10),
                ],
              ),
              child: const Icon(Icons.hub_outlined, size: 80, color: Colors.blueAccent),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            "SYNTECK GATEWAY",
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            "Industrial Connectivity Suite v4.5",
            style: TextStyle(fontSize: 14, color: Colors.white38, letterSpacing: 1.5),
          ),
          const SizedBox(height: 60),
          _buildHubButton(
            title: "NUEVO GATEWAY",
            subtitle: "Configurar conexión Modbus/TCP/Serial",
            icon: Icons.add_rounded,
            color: Colors.blueAccent,
            onTap: () => setState(() => _currentStep = "select_driver"),
          ),
          const SizedBox(height: 20),
          if (_connections.isNotEmpty)
            _buildHubButton(
              title: "MONITOR ACTIVO",
              subtitle: "${_connections.length} conexiones funcionando",
              icon: Icons.monitor_heart_outlined,
              color: Colors.greenAccent,
              onTap: () => setState(() => _currentStep = "monitoring"),
            ),
          const SizedBox(height: 40),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 14, color: Colors.white24),
              SizedBox(width: 5),
              Text("Licensed Internal Development Tool", style: TextStyle(fontSize: 10, color: Colors.white24)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHubButton({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white38)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectDriver() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("PRODUCT CATALOG / DRIVERS", style: TextStyle(fontSize: 12, color: Colors.blueAccent, letterSpacing: 2)),
          const SizedBox(height: 10),
          const Text("Seleccione Driver de Dispositivo", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: driverTree.length,
              itemBuilder: (context, index) {
                final brand = driverTree[index];
                final bool isEnabled = brand.isEnabled;
                
                return ExpansionTile(
                  leading: Icon(
                    Icons.account_tree_outlined, 
                    color: isEnabled ? Colors.blueAccent : Colors.white10
                  ),
                  title: Row(
                    children: [
                      Text(
                        brand.name, 
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.white : Colors.white24,
                        )
                      ),
                      if (!isEnabled)
                        Container(
                          margin: const EdgeInsets.only(left: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "PRÓXIMAMENTE", 
                            style: TextStyle(fontSize: 8, color: Colors.orangeAccent, fontWeight: FontWeight.bold)
                          ),
                        ),
                    ],
                  ),
                  children: (brand.children ?? []).map((device) => ListTile(
                    enabled: isEnabled,
                    contentPadding: const EdgeInsets.only(left: 56, right: 16),
                    title: Text(
                      device.name, 
                      style: TextStyle(
                        fontSize: 14,
                        color: isEnabled ? Colors.white : Colors.white10,
                      )
                    ),
                    subtitle: Text(
                      device.description ?? "", 
                      style: TextStyle(
                        fontSize: 11, 
                        color: isEnabled ? Colors.white38 : Colors.white10
                      )
                    ),
                    trailing: Icon(
                      Icons.chevron_right, 
                      size: 16,
                      color: isEnabled ? Colors.blueAccent : Colors.transparent,
                    ),
                    onTap: isEnabled ? () {
                      setState(() {
                        _selectedDriver = device;
                        if (device.id == "delta_dvp") {
                          _baudrate = "9600";
                          _parity = "E";
                          _dataBits = "7";
                          _stopBits = "1";
                          _protocol = "ASCII";
                        }
                        _currentStep = "select_layer";
                      });
                    } : null,
                  )).toList(),
                );
              },
            ),
          ),
          if (_connections.isNotEmpty)
            Center(child: TextButton(onPressed: () => setState(() => _currentStep = "monitoring"), child: const Text("VOLVER AL MONITOR")))
        ],
      ),
    );
  }

  Widget _buildSelectLayer() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _currentStep = "select_driver")),
              Text("DRIVER: ${_selectedDriver?.name}", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 40),
          const Text("SELECCIONE CAPA FÍSICA", style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLargeSelectionButton("ETHERNET", Icons.lan_outlined, () {
                setState(() {
                  _physicalLayer = "Ethernet";
                  _currentStep = "setup_connection";
                });
              }),
              const SizedBox(width: 20),
              _buildLargeSelectionButton("SERIAL (COM)", Icons.settings_input_component, () {
                setState(() {
                  _physicalLayer = "Serial";
                  _currentStep = "setup_connection";
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetupConnection() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _currentStep = "select_layer")),
              const Text("CONFIGURAR HARDWARE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          _buildConfigSummary(),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_physicalLayer == "Ethernet") ...[
                    const Text("Interfaces de Red:", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 10),
                    _buildInterfaceList(),
                  ] else ...[
                    const Text("Puertos COM:", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 10),
                    _buildComPortList(),
                    const SizedBox(height: 20),
                    const Text("Parámetros Serial:", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildSerialParams(),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => setState(() {
                _currentStep = "select_protocol";
                // Set default protocol based on layer
                if (_physicalLayer == "Ethernet") {
                  _protocol = "TCP";
                } else {
                  _protocol = "RTU";
                }
              }),
              child: const Text("SELECCIONA PROTOCOLO", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectProtocol() {
    List<String> protocols = _physicalLayer == "Ethernet" ? ["TCP", "ASCII"] : ["RTU", "ASCII"];
    
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _currentStep = "setup_connection")),
              const Text("PASO FINAL: PROTOCOLO", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          _buildConfigSummary(),
          const SizedBox(height: 40),
          const Text("Seleccione el variante del protocolo:", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          const Text("IP Esclavo / Nodo ID:", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: TextField(
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(border: InputBorder.none, hintText: "Slave ID (1-247)"),
                    onChanged: (val) => _slaveId = int.tryParse(val) ?? 1,
                    controller: TextEditingController(text: _slaveId.toString()),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 12,
                  children: protocols.map((p) => ChoiceChip(
                    label: Text("Modbus $p"),
                    selected: _protocol == p,
                    onSelected: (val) { if(val) setState(() => _protocol = p); },
                  )).toList(),
                ),
              )
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.withOpacity(0.8),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _addNewConnection,
              child: const Text("PROBAR", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSerialParams() {
    return Row(
      children: [
         _buildDropdown("Baud", _baudrate, ["2400", "4800", "9600", "19200", "38400", "57600", "115200"], (val) => setState(() => _baudrate = val!)),
         const SizedBox(width: 10),
         _buildDropdown("Paridad", _parity, ["N", "E", "O"], (val) => setState(() => _parity = val!)),
         const SizedBox(width: 10),
         _buildDropdown("Bits", _dataBits, ["7", "8"], (val) => setState(() => _dataBits = val!)),
         const SizedBox(width: 10),
         _buildDropdown("Stop", _stopBits, ["1", "2"], (val) => setState(() => _stopBits = val!)),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        DropdownButton<String>(
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: onChanged,
          underline: Container(height: 1, color: Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _buildMonitoring() {
    return ListView.builder(
      itemCount: _connections.length,
      itemBuilder: (context, index) => _buildConnectionGroup(_connections[index]),
    );
  }

  Widget _buildConnectionGroup(GatewayConnection conn) {
    AssetNode? rootNode = _connectionAssets[conn.id];
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: conn.statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(conn.id.contains("SER") ? Icons.settings_input_component : Icons.lan, color: conn.statusColor),
            title: Row(
              children: [
                Text(conn.host, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(conn.details, style: const TextStyle(fontSize: 9, color: Colors.blueAccent, fontFamily: 'monospace')),
                ),
              ],
            ),
            subtitle: Text("ID: ${conn.id} • Status: ${conn.status}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (conn.status == "Conectado") ...[
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined, color: Colors.orangeAccent, size: 20),
                    onPressed: () => _showCreateFolderDialog(conn.id, rootNode!),
                    tooltip: "Crear Carpeta / Grupo",
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_chart_outlined, color: Colors.blueAccent, size: 20),
                    onPressed: () => _addPoll(conn.id),
                    tooltip: "Añadir Bloque de Lectura",
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                  onPressed: () => _engine.sendCommand("disconnect", {"connection_id": conn.id}),
                  tooltip: "Desconectar",
                ),
              ],
            ),
          ),
          if (rootNode != null)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
              child: Column(
                children: rootNode.children.map((child) => _buildAssetTreeNode(child, conn.id)).toList(),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildAssetTreeNode(AssetNode node, String connId) {
    if (node.type == NodeType.poll && node.poll != null) {
      return _buildPollMonitor(node.poll!);
    }

    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_open, color: Colors.orangeAccent, size: 18),
      title: Text(node.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      childrenPadding: const EdgeInsets.only(left: 16),
      trailing: IconButton(
        icon: const Icon(Icons.add_chart_outlined, size: 16, color: Colors.blueAccent),
        onPressed: () => _addPoll(connId), // TODO: Targeted add to this folder
      ),
      children: node.children.map((child) => _buildAssetTreeNode(child, connId)).toList(),
    );
  }

  void _showCreateFolderDialog(String connId, AssetNode parent) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: const Text("NUEVO GRUPO / MÁQUINA", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: "Nombre del Grupo", hintText: "Ej: Maquina 1, Linea A..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() {
                  parent.children.add(AssetNode(
                    id: "folder_${DateTime.now().millisecondsSinceEpoch}",
                    name: nameController.text,
                    type: NodeType.folder,
                    children: [],
                    parentId: parent.id,
                  ));
                });
              }
              Navigator.pop(context);
            },
            child: const Text("CREAR"),
          ),
        ],
      ),
    );
  }

  Widget _buildInterfaceList() {
    if (_networkInterfaces.isEmpty) return const Text("No se detectaron interfaces.");
    return Column(
      children: _networkInterfaces.map((iface) {
        bool isSelected = _selectedIp == iface['ip'];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            tileColor: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white10),
            ),
            leading: Icon(Icons.network_check, color: isSelected ? Colors.blueAccent : Colors.grey),
            title: Text(iface['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.blueAccent : Colors.white)),
            subtitle: Text(iface['ip'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
            onTap: () => setState(() => _selectedIp = iface['ip']),
            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent, size: 18) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildComPortList() {
    if (_serialPorts.isEmpty) return const Text("No se detectaron puertos COM.");
    return Column(
      children: _serialPorts.map((port) {
        bool isSelected = _selectedCom == port['port'];
        bool hasManufacturer = port['manufacturer'] != null && port['manufacturer'] != "Unknown Manufacturer";
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            tileColor: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white10),
            ),
            leading: Icon(Icons.settings_input_hdmi, color: isSelected ? Colors.blueAccent : Colors.grey),
            title: Row(
              children: [
                Text(port['port'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.blueAccent : Colors.white)),
                const SizedBox(width: 8),
                if (hasManufacturer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                    child: Text(port['manufacturer'], style: const TextStyle(fontSize: 8, color: Colors.white38)),
                  ),
              ],
            ),
            subtitle: Text(port['description'] ?? "Unknown Device", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            onTap: () => setState(() => _selectedCom = port['port']),
            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent, size: 18) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLargeSelectionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.blueAccent),
            const SizedBox(height: 15),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPollMonitor(PollDefinition poll) {
    bool isOk = poll.status == "ok";
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOk ? Colors.greenAccent.withOpacity(0.01) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOk ? Colors.greenAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          width: isOk ? 1.5 : 1,
        ),
        boxShadow: isOk ? [
          BoxShadow(color: Colors.greenAccent.withOpacity(0.05), blurRadius: 10, spreadRadius: 1)
        ] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isOk)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 4)]
                  ),
                ),
              Text(
                poll.tag ?? poll.id, 
                style: TextStyle(
                  color: isOk ? Colors.greenAccent : Colors.white70, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 16, 
                  letterSpacing: 1.2
                )
              ),
              const SizedBox(width: 8),
              if (poll.tag != null) 
                Text("(${poll.id})", style: const TextStyle(color: Colors.white24, fontSize: 10)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOk ? Colors.greenAccent.withOpacity(0.15) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isOk ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3))
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOk) const Icon(Icons.bolt, size: 10, color: Colors.greenAccent),
                    if (isOk) const SizedBox(width: 4),
                    Text(
                      isOk ? "OPERATIVO" : "ERROR", 
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.w900, 
                        color: isOk ? Colors.greenAccent : Colors.redAccent,
                        letterSpacing: 1
                      )
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.label_outline, size: 16, color: Colors.blueAccent),
                onPressed: () => _showTagEditor(poll),
                tooltip: "Editar Tags Individuales",
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (poll.status == "error" && poll.message.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Error: ${poll.message}",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                  if (poll.message.contains("No response") || poll.message.contains("Timeout"))
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        "💡 Sugerencia: Revise parámetros de comunicación (Baud, Paridad) y/o el Nodo ID (Slave ID).",
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 2.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: poll.count,
            itemBuilder: (context, idx) {
              final value = (poll.values.length > idx) ? poll.values[idx] : "--";
              
              // Determine context for Native Label
              String nativeLabel = "";
              // If tag is a native address (e.g. D0), or if we can infer it
              // Let's check if the tag starts with a known Delta prefix
              String prefix = poll.tag?.split(' ')[0] ?? ""; // Handle "Temp Calandria" vs "D0"
              
              // Try to find the original type from the tag or just use the address logic
              // For Delta DVP, we know the mapping
              int addr = poll.address + idx;
              if (addr >= 0x1000 && addr <= 0x1FFF) nativeLabel = "D${addr - 0x1000}";
              else if (addr >= 0x0400 && addr <= 0x5FF) nativeLabel = "X${(addr - 0x0400).toRadixString(8)}";
              else if (addr >= 0x0500 && addr <= 0x5FF) nativeLabel = "Y${(addr - 0x0500).toRadixString(8)}";
              else if (addr >= 0x0800 && addr <= 0x0FFF) nativeLabel = "M${addr - 0x0800}";
              else if (addr >= 0x0000 && addr <= 0x03FF) nativeLabel = "S${addr}";
              else if (addr >= 0x0600 && addr <= 0x06FF) nativeLabel = "T${addr - 0x0600}";
              else if (addr >= 0x0E00 && addr <= 0x0EFF) nativeLabel = "C${addr - 0x0E00}";

              // If there's an individual tag for this address, use it as the primary label
              String displayLabel = poll.addressTags[addr] ?? nativeLabel;

              return ModbusAddressCard(
                address: addr, 
                label: displayLabel,
                value: value, 
                onTap: () => _showWriteDialog(poll.connectionId, addr, value)
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _buildSummaryItem("DRIVER", _selectedDriver?.name ?? "No definido", Colors.blueAccent),
          _buildSummaryItem("CAPA", _physicalLayer.toUpperCase(), Colors.orangeAccent),
          if (_physicalLayer == "Ethernet" && _selectedIp.isNotEmpty)
            _buildSummaryItem("IP", _selectedIp, Colors.greenAccent),
          if (_physicalLayer == "Serial" && _selectedCom.isNotEmpty) ...[
             _buildSummaryItem("PUERTO", _selectedCom, Colors.greenAccent),
             _buildSummaryItem("SETTINGS", "($_baudrate, $_parity, $_dataBits, $_stopBits)", Colors.white38),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1)),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
