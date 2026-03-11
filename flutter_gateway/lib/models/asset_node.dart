
import 'poll_definition.dart';

enum NodeType { folder, poll }

class AssetNode {
  final String id;
  String name;
  final NodeType type;
  final List<AssetNode> children;
  final PollDefinition? poll;
  final String? parentId;

  AssetNode({
    required this.id,
    required this.name,
    required this.type,
    this.children = const [],
    this.poll,
    this.parentId,
  });

  // Helper to find a node recursively
  AssetNode? find(String targetId) {
    if (id == targetId) return this;
    for (var child in children) {
      var found = child.find(targetId);
      if (found != null) return found;
    }
    return null;
  }
}
