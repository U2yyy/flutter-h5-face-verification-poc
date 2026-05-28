import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:facedetection/services/aliyun/aliyun_h5_service.dart';
import 'package:facedetection/services/tencent/tencent_h5_service.dart';
import 'package:facedetection/utils/permission_utils.dart';
import 'package:facedetection/utils/webview_platform_utils.dart';

enum H5CallbackStyle { tencentToken, aliyunResponse }

/// Full-screen WebView for cloud H5 liveness verification.
class H5LivenessScreen extends StatefulWidget {
  const H5LivenessScreen({
    super.key,
    required this.verificationUrl,
    required this.redirectUrl,
    this.title = 'H5 Liveness',
    this.callbackStyle = H5CallbackStyle.tencentToken,
  });

  final String verificationUrl;
  final String redirectUrl;
  final String title;
  final H5CallbackStyle callbackStyle;

  @override
  State<H5LivenessScreen> createState() => _H5LivenessScreenState();
}

class _H5LivenessScreenState extends State<H5LivenessScreen> {
  WebViewController? _controller;
  var _loading = true;
  String? _errorMessage;
  String? _debugStep;
  var _completed = false;

  bool get _isAliyun => widget.callbackStyle == H5CallbackStyle.aliyunResponse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_initialize());
      }
    });
  }

  Future<void> _initialize() async {
    if (_isAliyun) setState(() => _debugStep = 'Checking permissions…');

    final granted = await PermissionUtils.ensureH5LivenessPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _loading = false;
        _errorMessage =
            'Camera permission is required for H5 face liveness. Enable it in Settings.';
        _debugStep = 'Permission denied';
      });
      return;
    }

    final controller = WebViewController(
      onPermissionRequest: _handleWebViewPermissionRequest,
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            WebViewPlatformUtils.logNavigation(url, tag: widget.title);
            if (!mounted || _completed) return;
            setState(() {
              _loading = true;
              if (_isAliyun) _debugStep = 'Loading page…';
            });
          },
          onPageFinished: (url) {
            WebViewPlatformUtils.logNavigation('finished: $url', tag: widget.title);
            if (!mounted || _completed) return;
            setState(() {
              _loading = false;
              if (_isAliyun) _debugStep = 'Complete liveness in WebView';
            });
          },
          onWebResourceError: (error) {
            WebViewPlatformUtils.logWebResourceError(
              error,
              tag: widget.title,
            );
            if (!mounted || _completed) return;
            setState(() {
              _loading = false;
              _errorMessage = WebViewPlatformUtils.formatResourceError(
                error,
                failedResourceHint: error.isForMainFrame == true
                    ? 'Failed to load H5 verification page:'
                    : null,
              );
              if (_isAliyun) _debugStep = 'Load error';
            });
          },
          onNavigationRequest: (request) {
            WebViewPlatformUtils.logNavigation(
              'request: ${request.url}',
              tag: widget.title,
            );
            if (_handlePossibleCompletion(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) {
              WebViewPlatformUtils.logNavigation(
                'urlChange: $url',
                tag: widget.title,
              );
              _handlePossibleCompletion(url);
            }
          },
        ),
      );

    await WebViewPlatformUtils.configureForCloudH5(controller);

    setState(() {
      _controller = controller;
      if (_isAliyun) _debugStep = 'Opening CertifyUrl…';
    });
    await _loadVerificationPage();
  }

  Future<void> _handleWebViewPermissionRequest(
    WebViewPermissionRequest request,
  ) async {
    final needsCamera = request.types.contains(
      WebViewPermissionResourceType.camera,
    );
    final needsMicrophone = request.types.contains(
      WebViewPermissionResourceType.microphone,
    );

    final cameraGranted = !needsCamera || await Permission.camera.isGranted;
    final microphoneGranted =
        !needsMicrophone || await Permission.microphone.isGranted;

    if (cameraGranted && microphoneGranted) {
      await request.grant();
      return;
    }

    await request.deny();
    if (!mounted || _completed) return;
    setState(() {
      _errorMessage =
          'WebView could not access the camera. Check app permissions in Settings.';
    });
  }

  Future<void> _loadVerificationPage() async {
    final controller = _controller;
    if (controller == null) return;

    final uri = Uri.tryParse(widget.verificationUrl);
    if (uri == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Invalid VerificationURL';
        if (_isAliyun) _debugStep = 'Invalid URL';
      });
      return;
    }

    try {
      await controller.loadRequest(uri);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
        if (_isAliyun) _debugStep = 'Load failed';
      });
    }
  }

  bool _handlePossibleCompletion(String url) {
    if (_completed) return true;

    final isComplete = switch (widget.callbackStyle) {
      H5CallbackStyle.tencentToken =>
        TencentH5CallbackParser.isCompletionRedirect(url, widget.redirectUrl),
      H5CallbackStyle.aliyunResponse =>
        AliyunH5CallbackParser.isCompletionRedirect(url, widget.redirectUrl),
    };

    if (!isComplete) return false;

    _completed = true;
    final sessionToken = switch (widget.callbackStyle) {
      H5CallbackStyle.tencentToken =>
        TencentH5CallbackParser.extractBizToken(url),
      H5CallbackStyle.aliyunResponse =>
        AliyunH5CallbackParser.extractCertifyId(url),
    };

    if (!mounted) return true;

    Navigator.of(context).pop(
      H5LivenessCompletion(
        success: sessionToken != null,
        bizToken: sessionToken,
        errorMessage: sessionToken == null
            ? switch (widget.callbackStyle) {
                H5CallbackStyle.tencentToken =>
                  'Redirect missing token query parameter',
                H5CallbackStyle.aliyunResponse =>
                  'Redirect missing response/certifyId parameter',
              }
            : null,
      ),
    );
    return true;
  }

  void _closeWithCancel() {
    if (_completed) return;
    _completed = true;
    Navigator.of(context).pop(
      const H5LivenessCompletion(
        success: false,
        errorMessage: 'Liveness cancelled',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: theme.colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _closeWithCancel,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loading || controller == null
                ? null
                : () {
                    setState(() {
                      _errorMessage = null;
                      _loading = true;
                    });
                    _loadVerificationPage();
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            if (_isAliyun && _debugStep != null)
              Material(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.bug_report, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _debugStep!,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_errorMessage != null)
              Material(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMessage!)),
                      if (_errorMessage!.contains('Settings'))
                        TextButton(
                          onPressed: PermissionUtils.openSettings,
                          child: const Text('Settings'),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: controller == null
                  ? const Center(child: CircularProgressIndicator())
                  : WebViewWidget(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}
