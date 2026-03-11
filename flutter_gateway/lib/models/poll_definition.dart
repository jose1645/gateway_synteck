class PollDefinition {
  final String id;
  final String connectionId;
  final int slaveId;
  final int function;
  final int address;
  final int count;
  final int rate;
  List<dynamic> values;
  String status;
  String message;

  final String? tag;
  final Map<int, String> addressTags;

  PollDefinition({
    required this.id,
    required this.connectionId,
    this.slaveId = 1,
    this.function = 3,
    this.address = 0,
    this.count = 10,
    this.rate = 1000,
    this.values = const [],
    this.status = "Inactivo",
    this.message = "",
    this.tag,
    this.addressTags = const {},
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "connection_id": connectionId,
    "slave_id": slaveId,
    "function": function,
    "address": address,
    "count": count,
    "rate": rate,
    "tag": tag,
    "address_tags": addressTags.map((key, value) => MapEntry(key.toString(), value)),
  };
}
