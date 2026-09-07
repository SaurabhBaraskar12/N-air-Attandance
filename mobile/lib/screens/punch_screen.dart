import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart';
import '../widgets.dart';

/// Captures a front-camera selfie + current GPS, then submits mark_attendance.
class PunchScreen extends StatefulWidget {
  final String punchType; // "Check In" / "Check Out"
  const PunchScreen({super.key, required this.punchType});
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
  CameraController? _cam;
  Future<void>? _camInit;
  XFile? _shot;
  Position? _pos;
  String? _locError;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _fetchLocation();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(front, ResolutionPreset.medium,
          enableAudio: false);
      _camInit = ctrl.initialize();
      await _camInit;
      if (mounted) setState(() => _cam = ctrl);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _fetchLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locError = 'Location services are disabled.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locError = 'Location permission denied.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _pos = p; _locError = null; });
    } catch (e) {
      if (mounted) setState(() => _locError = 'Location error: $e');
    }
  }

  Future<void> _capture() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    try {
      final file = await _cam!.takePicture();
      setState(() => _shot = file);
    } catch (e) {
      setState(() => _error = 'Capture failed: $e');
    }
  }

  Future<void> _submit() async {
    if (_shot == null || _pos == null) return;
    setState(() { _submitting = true; _error = null; });
    try {
      final res = await ApiService.instance.markAttendance(
        punchType: widget.punchType,
        latitude: _pos!.latitude,
        longitude: _pos!.longitude,
        selfie: File(_shot!.path),
        deviceInfo: 'Flutter/${Platform.operatingSystem}',
      );
      if (!mounted) return;
      await _showResult(res);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  Future<void> _showResult(Map<String, dynamic> res) {
    final status = res['status']?.toString() ?? 'Done';
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          const Text('Punch Recorded'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          StatusBadge(status),
          const SizedBox(height: 12),
          Text(res['message']?.toString() ?? ''),
          const SizedBox(height: 8),
          _kv('Face match', res['face_match_status']),
          _kv('Within geofence', res['within_geofence']),
          if (res['distance_from_location_meter'] != null)
            _kv('Distance (m)', res['distance_from_location_meter']),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _kv(String k, dynamic v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text('$v', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.punchType)),
      body: Column(children: [
        Expanded(child: _preview()),
        _infoBar(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _shot == null ? _captureButton() : _submitRow(),
        ),
      ]),
    );
  }

  Widget _preview() {
    if (_error != null) {
      return Center(child: Padding(
          padding: const EdgeInsets.all(24), child: ErrorBanner(_error!)));
    }
    if (_shot != null) {
      return Image.file(File(_shot!.path), fit: BoxFit.contain);
    }
    if (_cam == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraPreview(_cam!);
  }

  Widget _infoBar() {
    final locOk = _pos != null;
    return Container(
      color: locOk ? Colors.green.shade50 : Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(locOk ? Icons.location_on : Icons.location_searching,
            color: locOk ? Colors.green : Colors.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            locOk
                ? 'GPS: ${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}'
                : (_locError ?? 'Fetching location...'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!locOk)
          TextButton(onPressed: _fetchLocation, child: const Text('Retry')),
      ]),
    );
  }

  Widget _captureButton() {
    final ready = _cam != null && _cam!.value.isInitialized;
    return FilledButton.icon(
      onPressed: ready ? _capture : null,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      icon: const Icon(Icons.camera_alt),
      label: const Text('Capture Selfie'),
    );
  }

  Widget _submitRow() {
    final canSubmit = _pos != null && !_submitting;
    return Row(children: [
      OutlinedButton.icon(
        onPressed: _submitting ? null : () => setState(() => _shot = null),
        icon: const Icon(Icons.refresh),
        label: const Text('Retake'),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          icon: _submitting
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          label: Text(_submitting ? 'Submitting...' : 'Submit'),
        ),
      ),
    ]);
  }
}
