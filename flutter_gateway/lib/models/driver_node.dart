class DriverNode {
  final String name;
  final String id;
  final String? description;
  final List<DriverNode>? children;
  final bool isBrand;
  final bool isEnabled;

  DriverNode({
    required this.name,
    required this.id,
    this.description,
    this.children,
    this.isBrand = false,
    this.isEnabled = true,
  });
}

final List<DriverNode> driverTree = [
  DriverNode(
    name: "Delta Electronics",
    id: "delta",
    isBrand: true,
    isEnabled: true,
    children: [
      DriverNode(name: "DVP Series", id: "delta_dvp", description: "PLC Delta DVP Series Communication"),
    ],
  ),
  DriverNode(
    name: "Siemens",
    id: "siemens",
    isBrand: true,
    isEnabled: false,
    children: [
      DriverNode(name: "S7-200", id: "s7_200", description: "S7-200 via Modbus RTU/TCP"),
      DriverNode(name: "S7-1200 / S7-1500", id: "s7_1200_1500", description: "Profinet / S7 Communication"),
      DriverNode(name: "LOGO!", id: "siemens_logo", description: "Modbus TCP for LOGO! 8"),
    ],
  ),
  DriverNode(
    name: "Allen Bradley",
    id: "ab",
    isBrand: true,
    isEnabled: false,
    children: [
      DriverNode(name: "MicroLogix / SLC", id: "ab_micrologix", description: "EtherNet/IP or Modbus TCP"),
      DriverNode(name: "CompactLogix", id: "ab_compactlogix", description: "EtherNet/IP Gateway"),
    ],
  ),
  DriverNode(
    name: "Schneider Electric",
    id: "schneider",
    isBrand: true,
    isEnabled: false,
    children: [
      DriverNode(name: "Modicon M221/M241", id: "schneider_modicon", description: "Native Modbus TCP"),
      DriverNode(name: "Zelio Logic", id: "schneider_zelio", description: "Modbus Serial extension"),
    ],
  ),
  DriverNode(
    name: "Generic / Tools",
    id: "generic",
    isBrand: true,
    isEnabled: true,
    children: [
      DriverNode(name: "Generic Modbus TCP", id: "generic_modbus_tcp", description: "Standard TCP connection"),
      DriverNode(name: "Generic Modbus RTU", id: "generic_modbus_rtu", description: "Standard Serial connection"),
    ],
  ),
];
