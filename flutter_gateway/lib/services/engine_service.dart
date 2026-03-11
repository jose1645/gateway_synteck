import 'dart:convert';
import 'dart:io';
import 'dart:async';

class EngineService {
  Process? _process;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get events => _controller.stream;

  Future<void> init() async {
    try {
      final String scriptDir = Directory.current.path;
      final String enginePath = File('$scriptDir/../backend/engine.py').absolute.path;
      
      print("🚀 INICIANDO MOTOR EN: $enginePath");

      _process = await Process.start(
        'python',
        [enginePath],
        workingDirectory: scriptDir,
      );

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        print("🐍 PY_OUT: $line");
        try {
          final data = jsonDecode(line);
          _controller.add(data);
        } catch (e) {
          _controller.add({"event": "log", "message": line});
        }
      });

      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        print("🛑 PY_ERR: $line");
        _controller.add({"event": "error", "message": line});
      });
    } catch (e) {
      print("❌ FALLO CRÍTICO MOTOR: $e");
      _controller.add({"event": "critical", "message": e.toString()});
    }
  }

  void sendCommand(String action, Map<String, dynamic> params) {
    if (_process != null) {
      final cmd = jsonEncode({"action": action, "params": params});
      _process!.stdin.writeln(cmd);
    }
  }

  void dispose() {
    _process?.kill();
    _controller.close();
  }
}
