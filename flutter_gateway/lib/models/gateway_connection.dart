import 'package:flutter/material.dart';

class GatewayConnection {
  final String id;
  final String host;
  final String framer;
  final int port;
  final String details; // New field for detailed info string
  String status;
  Color statusColor;
  String lastError;
  Map<String, dynamic> config;

  GatewayConnection({
    required this.id,
    required this.host,
    this.framer = "tcp",
    this.port = 502,
    this.details = "",
    this.status = "Desconectado",
    this.statusColor = Colors.grey,
    this.lastError = "",
    this.config = const {},
  });
}
