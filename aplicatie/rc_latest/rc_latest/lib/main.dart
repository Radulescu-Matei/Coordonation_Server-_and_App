// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';

// Load calibration JSON from assets
typedef CalibrationData = Map<String, dynamic>;
Future<CalibrationData> loadCalibration() async {
  final jsonStr = await rootBundle.loadString('assets/camera_calibration.json');
  return json.decode(jsonStr) as CalibrationData;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Vehicle Guidance',
      home: StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Guidance for RC vehicles')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              child: Text('Create Session'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CreateSessionScreen()),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              child: Text('Calibrate Camera'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CalibrateCameraScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateSessionScreen extends StatefulWidget {
  @override
  _CreateSessionScreenState createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _ipCtrl = TextEditingController();
  final _carsCtrl = TextEditingController();
  final _markersCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  String _error = '';

  Future<void> _initializeSession() async {
    final ip = _ipCtrl.text.trim();
    final cars = _carsCtrl.text.trim();
    final marks = _markersCtrl.text.trim();
    final size = _sizeCtrl.text.trim();
    if ([ip, cars, marks, size].any((s) => s.isEmpty)) {
      setState(() => _error = 'All fields are required');
      return;
    }

    CalibrationData calib;
    try {
      calib = await loadCalibration();
    } catch (_) {
      setState(() => _error = 'Failed to load calibration');
      return;
    }

    final url = Uri.parse('http://$ip:5000/api/initialize');
    final body = {
      'number_of_route_markers': marks,
      'number_of_cars': cars,
      'marker_size_cm': size,
      'camera_matrix': jsonEncode(calib['camera_matrix']),
      'dist_coeffs': jsonEncode(calib['dist_coeffs']),
    };

    try {
      final resp = await http.post(url, body: body);
      if (resp.statusCode == 200) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SessionScreen(ip: ip)),
        );
      } else {
        setState(() => _error = 'Init failed (${resp.statusCode})');
      }
    } catch (_) {
      setState(() => _error = 'Network error');
    }
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _carsCtrl.dispose();
    _markersCtrl.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Session')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ipCtrl,
              decoration: InputDecoration(labelText: 'Server IP'),
            ),
            TextField(
              controller: _carsCtrl,
              decoration: InputDecoration(labelText: 'Number of Vehicles'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _markersCtrl,
              decoration: InputDecoration(labelText: 'Number of Route Markers'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _sizeCtrl,
              decoration: InputDecoration(labelText: 'Marker Size (cm)'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            SizedBox(height: 20),
            ElevatedButton(
                onPressed: _initializeSession, child: Text('Submit')),
            if (_error.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(_error, style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  final String ip;
  SessionScreen({required this.ip});
  @override
  _SessionScreenState createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late CameraController _camera;
  bool _cameraReady = false;
  Timer? _timer;
  bool _sending = false, _waiting = false;
  String _status = 'Initializing camera…';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initCamera();
  }

  @override
  void dispose() {
    _stopSession();
    _camera.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) {
      setState(() => _status = 'No camera found');
      return;
    }
    _camera = CameraController(
      cams.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await _camera.initialize();
      setState(() {
        _cameraReady = true;
        _status = 'Camera ready';
      });
    } on CameraException catch (e) {
      setState(() => _status = 'Camera error: ${e.code}');
    }
  }

  void _startSession() {
    if (!_cameraReady || _sending) return;
    setState(() {
      _sending = true;
      _status = 'Sending images';
    });

    _timer = Timer.periodic(Duration(milliseconds: 10), (_) {
      _camera.takePicture().then((file) async {
        try {
          // Build the multipart request
          final req = http.MultipartRequest(
            'POST',
            Uri.parse('http://${widget.ip}:5000/api/image'),
          );

          // Stream directly from the file on disk
          final multipartFile = await http.MultipartFile.fromPath(
            'image',
            file.path,
            filename: 'frame.jpg',
          );
          req.files.add(multipartFile);

          // Send it off
          req.send().then((resp) {
            debugPrint('Frame ${resp.statusCode}');
          }).catchError((e) {
            debugPrint('Upload error: $e');
          });
        } catch (e) {
          debugPrint('Error preparing upload: $e');
        }
      }).catchError((e) {
        debugPrint('Capture error: $e');
      });
    });
  }

  void _stopSession() {
    if (_sending) {
      _timer?.cancel();
      _sending = false;
      debugPrint('Stopped sending images');
    }
  }

  Future<void> _endSession() async {
    setState(() {
      _waiting = true;
      _status = 'Fetching results…';
    });
    _stopSession();
    try {
      final resp =
          await http.get(Uri.parse('http://${widget.ip}:5000/api/get_times'));
      if (resp.statusCode == 200) {
        final raw = resp.body.trim();
        final map = raw.isNotEmpty
            ? json.decode(raw) as Map<dynamic, dynamic>
            : <dynamic, dynamic>{};
        final list = map.entries
            .map<MapEntry<String, String>>(
                (e) => MapEntry(e.key.toString(), e.value.toString()))
            .toList()
          ..sort((a, b) {
            double parse(String t) {
              if (t.endsWith('s')) {
                final n = double.tryParse(t.substring(0, t.length - 1)) ?? -1;
                return n < 0 ? double.infinity : n;
              }
              return double.tryParse(t) ?? double.infinity;
            }

            return parse(a.value).compareTo(parse(b.value));
          });
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ResultsScreen(results: list)),
        );
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() {
        _waiting = false;
        _status = 'Idle';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraReady) {
      return Scaffold(
        appBar: AppBar(title: Text('Session')),
        body: Center(child: Text(_status)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Session')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: _camera.value.aspectRatio,
              child: CameraPreview(_camera),
            ),
          ),
          Padding(padding: EdgeInsets.all(8), child: Text('Status: $_status')),
          Expanded(
            flex: 1,
            child: _waiting
                ? Center(child: CircularProgressIndicator())
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _sending ? null : _startSession,
                        child: Text('Start Session'),
                      ),
                      ElevatedButton(
                        onPressed: _sending ? _endSession : null,
                        child: Text('End Session'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class CalibrateCameraScreen extends StatefulWidget {
  @override
  _CalibrateCameraScreenState createState() => _CalibrateCameraScreenState();
}

class _CalibrateCameraScreenState extends State<CalibrateCameraScreen> {
  final _ipCtrl = TextEditingController();
  late CameraController _camera;
  bool _init = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initCamera();
  }

  @override
  void dispose() {
    if (_init) _camera.stopImageStream();
    _camera.dispose();
    _ipCtrl.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) {
      setState(() => _msg = 'No camera');
      return;
    }
    _camera = CameraController(
      cams.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await _camera.initialize();
      setState(() => _init = true);
    } on CameraException catch (e) {
      setState(() => _msg = 'Camera error: ${e.code}');
    }
  }

  Future<void> _takeAndSend() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return setState(() => _msg = 'Enter IP');
    setState(() => _msg = 'Sending...');
    try {
      final file = await _camera.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('http://$ip:5000/api/image'),
      )..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: 'calib.jpg'),
        );
      final resp = await req.send();
      setState(() => _msg =
          resp.statusCode == 200 ? 'Image sent' : 'Err ${resp.statusCode}');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calibrate Camera')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: _ipCtrl,
              decoration: InputDecoration(labelText: 'Server IP'),
            ),
          ),
          Expanded(
            child: _init
                ? CameraPreview(_camera)
                : Center(child: Text(_msg.isEmpty ? 'Loading…' : _msg)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: ElevatedButton(
              onPressed: _init ? _takeAndSend : null,
              child: Text('Take Picture'),
            ),
          ),
          Text(_msg),
        ],
      ),
    );
  }
}

// Only ResultsScreen is modified:
class ResultsScreen extends StatelessWidget {
  final List<MapEntry<String, String>> results;
  ResultsScreen({required this.results});

  @override
  Widget build(BuildContext context) {
    // Helper to parse a "3.79…s" into a double, or -1 if invalid
    double parseTime(String t) {
      if (t.endsWith('s')) {
        final v = double.tryParse(t.substring(0, t.length - 1));
        return v == null ? -1 : v;
      }
      return double.tryParse(t) ?? -1;
    }

    List<MapEntry<String, String>> buildOrdered(
        List<MapEntry<String, String>> list) {
      final finished = <MapEntry<String, String>>[];
      final unfinished = <MapEntry<String, String>>[];
      for (var e in list) {
        final t = parseTime(e.value);
        if (t >= 0)
          finished.add(e);
        else
          unfinished.add(e);
      }
      finished.sort((a, b) => parseTime(a.value).compareTo(parseTime(b.value)));
      return [...finished, ...unfinished];
    }

    // Unwrap if the server returned {"finish": {...}}
    if (results.length == 1 && results[0].key == 'finish') {
      final nested = results[0].value;
      final reg = RegExp(r'([\w]+):\s*([^,}]+)');
      final list = reg
          .allMatches(nested)
          .map((m) => MapEntry(m.group(1)!, m.group(2)!))
          .toList();
      final ordered = buildOrdered(list);

      return Scaffold(
        appBar: AppBar(title: Text('Results')),
        body: ListView.builder(
          itemCount: ordered.length,
          itemBuilder: (_, i) {
            final e = ordered[i];
            final t = parseTime(e.value);
            final label = t < 0 ? 'has not finished' : e.value;
            return ListTile(
              leading: Text('${i + 1}.'),
              title: Text(e.key),
              subtitle: Text(label),
            );
          },
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            child: Text('Restart'),
            onPressed: () => Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => StartScreen()),
              (_) => false,
            ),
          ),
        ),
      );
    }

    // Flat list case
    final orderedFlat = buildOrdered(results);
    return Scaffold(
      appBar: AppBar(title: Text('Results')),
      body: ListView.builder(
        itemCount: orderedFlat.length,
        itemBuilder: (_, i) {
          final e = orderedFlat[i];
          final t = parseTime(e.value);
          final label = t < 0 ? 'has not finished' : e.value;
          return ListTile(
            leading: Text('${i + 1}.'),
            title: Text(e.key),
            subtitle: Text(label),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          child: Text('Restart'),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => StartScreen()),
            (_) => false,
          ),
        ),
      ),
    );
  }
}
