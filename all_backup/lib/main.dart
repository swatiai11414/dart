import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTTP Server App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final GlobalKey<LogScreenState> logKey = GlobalKey();
  final List<String> logs = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("HTTP Server")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Image.asset(
              'images/banner.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 130,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                InputScreen(
                  logs: logs,
                  onLog: (msg) {
                    setState(() {
                      logs.add(msg);
                    });
                    logKey.currentState?.updateLogs();
                  },
                ),
                LogScreen(logs: logs, key: logKey),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (idx) => setState(() => _tabIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Setup'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Logs'),
        ],
      ),
    );
  }
}

class InputScreen extends StatefulWidget {
  final List<String> logs;
  final Function(String) onLog;

  const InputScreen({required this.logs, required this.onLog, Key? key}) : super(key: key);

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final ipController = TextEditingController(text: '0.0.0.0');
  final portController = TextEditingController(text: '8080');
  final dirController = TextEditingController(text: '/sdcard/');
  HttpServer? server;
  bool running = false;

  final MethodChannel methodChannel = const MethodChannel('com.example/permissions');

  Future<int> getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final int? sdk = await methodChannel.invokeMethod<int>('getAndroidSdkInt');
      return sdk ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    int sdkInt = await getAndroidSdkInt();

    if (Platform.isAndroid && sdkInt >= 30) {
      if (!await Permission.manageExternalStorage.isGranted) {
        final granted = await Permission.manageExternalStorage.request().isGranted;
        if (!granted) {
          showError('Manage External Storage permission is required!');
          return false;
        }
      }
    } else {
      if (!await Permission.storage.isGranted) {
        final granted = await Permission.storage.request().isGranted;
        if (!granted) {
          showError('Storage permission is required!');
          return false;
        }
      }
    }

    if (!await Permission.sensors.isGranted) {
      final sensorGranted = await Permission.sensors.request().isGranted;
      if (!sensorGranted) {
        showError('Sensor permission is required!');
        return false;
      }
    }

    return true;
  }

  void handleStartPressed() async {
    if (running) return;

    if (!await checkAndRequestPermissions()) return;

    final ip = ipController.text.trim();
    final portText = portController.text.trim();
    String dir = dirController.text.trim();
    if (!dir.endsWith('/')) dir += '/';

    if (ip.isEmpty || portText.isEmpty || dir.isEmpty) {
      showError('IP, Port, and Directory are required!');
      return;
    }

    final ipRegex = RegExp(
      r'^((25[0-5]|(2[0-4]\d|1\d\d|\d{1,2}))\.){3}(25[0-5]|(2[0-4]\d|1\d\d|\d{1,2}))$',
    );
    if (!ipRegex.hasMatch(ip)) {
      showError('Invalid IP format!');
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port < 0 || port > 65535) {
      showError('Port must be a number between 0–65535');
      return;
    }

    if (!await Directory(dir).exists()) {
      showError('Directory does not exist!');
      return;
    }

    try {
      await server?.close(force: true);

      server = await HttpServer.bind(ip, port);
      widget.onLog('Serving $dir at $ip:$port');
      setState(() => running = true);

      server!.listen((HttpRequest request) async {
        widget.onLog('Request: ${request.method} ${request.uri.path}');
        final requestedPath = request.uri.path == '/' ? '/index.html' : request.uri.path;
        final file = File('$dir$requestedPath');
        if (await file.exists()) {
          final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
          request.response.headers.contentType = ContentType.parse(mimeType);
          await request.response.addStream(file.openRead());
          await request.response.close();
          widget.onLog('Served file: ${file.path}');
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('File not found');
          await request.response.close();
          widget.onLog('File not found: ${file.path}');
        }
      });
    } catch (e) {
      showError('Error: $e');
      widget.onLog('Error: $e');
      setState(() => running = false);
    }
  }

  void handleStopPressed() async {
    await server?.close(force: true);
    server = null;
    widget.onLog('Server stopped.');
    setState(() => running = false);
  }

  void showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    server?.close(force: true);
    ipController.dispose();
    portController.dispose();
    dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: ipController,
          decoration: const InputDecoration(labelText: 'IP Address'),
          enabled: !running,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: portController,
          decoration: const InputDecoration(labelText: 'Port'),
          keyboardType: TextInputType.number,
          enabled: !running,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: dirController,
          decoration: const InputDecoration(labelText: 'Directory to serve'),
          enabled: !running,
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start HTTP Server'),
          onPressed: running ? null : handleStartPressed,
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('Stop HTTP Server'),
          onPressed: running ? handleStopPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
        ),
      ],
    );
  }
}

class LogScreen extends StatefulWidget {
  final List<String> logs;

  const LogScreen({required this.logs, Key? key}) : super(key: key);

  @override
  LogScreenState createState() => LogScreenState();
}

class LogScreenState extends State<LogScreen> {
  void updateLogs() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (widget.logs.isEmpty) {
      return const Center(
        child: Text('No Logs', style: TextStyle(fontSize: 16)),
      );
    }
    return Container(
      color: Colors.black12,
      child: ListView.builder(
        reverse: true,
        itemCount: widget.logs.length,
        itemBuilder: (context, idx) {
          final log = widget.logs[widget.logs.length - 1 - idx];
          final isError = log.toLowerCase().contains('error');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              log,
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.red : Colors.black87,
                fontWeight: isError ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
}
