
import 'dart:collection';

class TagRegistry {
  // Key: connectionId_slaveId_function_address -> Value: TagName
  final Map<String, String> _registry = HashMap();

  static final TagRegistry _instance = TagRegistry._internal();
  factory TagRegistry() => _instance;
  TagRegistry._internal();

  String _buildKey(String connId, int slaveId, int func, int addr) {
    return "${connId}_${slaveId}_${func}_$addr";
  }

  bool registerTag(String connId, int slaveId, int func, int addr, String tagName) {
    String key = _buildKey(connId, slaveId, func, addr);
    if (_registry.containsKey(key)) {
      if (_registry[key] != tagName) {
        return false; // Collision!
      }
    }
    _registry[key] = tagName;
    return true;
  }

  String? getTag(String connId, int slaveId, int func, int addr) {
    return _registry[_buildKey(connId, slaveId, func, addr)];
  }

  void clear() => _registry.clear();
  
  void removeConnection(String connId) {
    _registry.removeWhere((key, value) => key.startsWith("${connId}_"));
  }
}
