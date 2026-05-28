import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// In-app front-camera video capture for CompareFaceLiveness (2–6 seconds, MP4).
class LiveCaptureScreen extends StatefulWidget {
  const LiveCaptureScreen({
    super.key,
    this.maxDuration = const Duration(seconds: 6),
    this.minDuration = const Duration(seconds: 2),
  });

  final Duration maxDuration;
  final Duration minDuration;

  @override
  State<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends State<LiveCaptureScreen> {
  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  String? _error;
  DateTime? _recordStartedAt;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No camera found on this device.';
          _initializing = false;
        });
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera failed to start: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_recording) {
      await _stopRecording();
      return;
    }

    try {
      await controller.startVideoRecording();
      _recordStartedAt = DateTime.now();
      setState(() => _recording = true);

      Future.delayed(widget.maxDuration, () {
        if (_recording) _stopRecording();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (!_recording || controller == null) return;

    final elapsed = DateTime.now().difference(_recordStartedAt ?? DateTime.now());
    if (elapsed < widget.minDuration) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Keep recording at least ${widget.minDuration.inSeconds} seconds.',
          ),
        ),
      );
      return;
    }

    setState(() => _recording = false);

    try {
      final xfile = await controller.stopVideoRecording();
      final bytes = await File(xfile.path).readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, Uint8List.fromList(bytes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save video: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record live face'),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
      floatingActionButton: _controller != null && _error == null
          ? FloatingActionButton.extended(
              onPressed: _toggleRecording,
              icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_recording ? 'Stop' : 'Record'),
              backgroundColor: _recording ? Colors.red : null,
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              if (_recording)
                Container(
                  color: Colors.black26,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 16),
                  child: const Chip(
                    avatar: Icon(Icons.fiber_manual_record, color: Colors.red),
                    label: Text('Recording…'),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Face the front camera and record ${widget.minDuration.inSeconds}–'
            '${widget.maxDuration.inSeconds} seconds. Hold still in good lighting.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
