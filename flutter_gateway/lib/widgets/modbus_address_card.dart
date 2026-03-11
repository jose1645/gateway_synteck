import 'package:flutter/material.dart';

class ModbusAddressCard extends StatelessWidget {
  final int address;
  final String? label;
  final dynamic value;
  final VoidCallback onTap;

  const ModbusAddressCard({
    super.key,
    required this.address,
    this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Text(label ?? "Add: $address", style: TextStyle(fontSize: 9, color: label != null ? Colors.orangeAccent : Colors.grey, fontWeight: FontWeight.bold)),
            const Spacer(),
            FittedBox(
              child: Text(
                "$value", 
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
