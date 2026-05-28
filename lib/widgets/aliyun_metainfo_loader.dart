import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/aliyun_metainfo_bootstrap.dart';
import '../utils/aliyun_metainfo_utils.dart';
import '../utils/aliyun_trace.dart';
import '../utils/webview_platform_utils.dart';

/// Hidden offscreen WebView that loads Aliyun `getMetaInfo()` without navigation.
///
/// Detaches the PlatformView as soon as MetaInfo is ready so InitFaceVerify does
/// not overlap with Android WebView teardown on the main thread.
class AliyunMetaInfoLoader extends StatefulWidget {
  const AliyunMetaInfoLoader({
    super.key,
    required this.onMetaInfoReady,
    this.onError,
  });

  final void Function(String metaInfo) onMetaInfoReady;
  final void Function(String message)? onError;

  @override
  State<AliyunMetaInfoLoader> createState() => AliyunMetaInfoLoaderState();
}

class AliyunMetaInfoLoaderState extends State<AliyunMetaInfoLoader> {
  WebViewController? _controller;
  var _loading = true;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  var _readingMetaInfo = false;
  var _initializeGeneration = 0;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    _cancelTimers();
    _initializeGeneration++;
    super.dispose();
  }

  /// Removes the WebView from the tree so PlatformView teardown can run
  /// before heavy work (e.g. InitFaceVerify) on the main thread.
  Future<void> detachWebView({String reason = 'metainfo_ready'}) async {
    _cancelTimers();
    _initializeGeneration++;
    if (mounted) {
      setState(() {
        _controller = null;
        _loading = false;
      });
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
  }

  /// Aborts MetaInfo polling without invoking [onMetaInfoReady].
  void cancel({String reason = 'cancelled'}) {
    if (_cancelled) return;
    _cancelled = true;
    _cancelTimers();
    _initializeGeneration++;
  }

  void _cancelTimers() {
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    _timeoutTimer = null;
    _pollTimer = null;
  }

  Future<void> _initialize() async {
    final generation = ++_initializeGeneration;
    _cancelTimers();
    _readingMetaInfo = false;
    _cancelled = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            WebViewPlatformUtils.logNavigation(url, tag: 'AliyunMetaInfo');
          },
          onPageFinished: (url) {
            if (!mounted || generation != _initializeGeneration) return;
            _startMetaInfoPolling(generation);
          },
          onWebResourceError: (error) {
            final url = error.url ?? '';
            final isSdkScript = url.contains('jsvm_all.js') ||
                url.contains('o.alicdn.com');
            WebViewPlatformUtils.logWebResourceError(
              error,
              tag: 'AliyunMetaInfo',
            );
            if (!mounted || !_loading || generation != _initializeGeneration) {
              return;
            }
            if (!isSdkScript && error.isForMainFrame != true) return;
            _fail(
              WebViewPlatformUtils.formatResourceError(
                error,
                failedResourceHint: isSdkScript
                    ? 'Failed to load Aliyun MetaInfo SDK:'
                    : null,
              ),
            );
          },
        ),
      );

    await WebViewPlatformUtils.configureForCloudH5(controller);

    if (!mounted || generation != _initializeGeneration) return;
    setState(() {
      _controller = controller;
      _loading = true;
    });

    _timeoutTimer = Timer(AliyunMetaInfoBootstrap.bootstrapTimeout, () {
      if (!mounted || !_loading || generation != _initializeGeneration) return;
      _fail(
        'MetaInfo timed out after ${AliyunMetaInfoBootstrap.bootstrapTimeout.inSeconds}s. '
        'Check network/VPN access to Aliyun CDN (${AliyunMetaInfoBootstrap.jsUrl}).',
      );
    });

    await controller.loadHtmlString(
      AliyunMetaInfoBootstrap.bootstrapHtml(),
      baseUrl: 'https://local.bootstrap/',
    );
  }

  void _startMetaInfoPolling(int generation) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      AliyunMetaInfoBootstrap.pollInterval,
      (_) {
        if (!mounted || generation != _initializeGeneration) return;
        unawaited(_readMetaInfo(generation));
      },
    );
    unawaited(_readMetaInfo(generation));
  }

  Future<Object?> _runJsWithTimeout(
    WebViewController controller,
    String source,
  ) async {
    try {
      return await controller
          .runJavaScriptReturningResult(source)
          .timeout(AliyunMetaInfoBootstrap.jsCallTimeout);
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _readMetaInfo(int generation) async {
    if (_readingMetaInfo || !mounted || !_loading || _cancelled) return;
    if (generation != _initializeGeneration) return;
    final controller = _controller;
    if (controller == null) return;

    _readingMetaInfo = true;
    try {
      final ready = await _runJsWithTimeout(
        controller,
        'window.__aliyunBootstrapReady === true',
      );
      if (!mounted ||
          generation != _initializeGeneration ||
          !_loading ||
          _cancelled) {
        return;
      }
      if (!_isJsTruthy(ready)) return;

      final result = await _runJsWithTimeout(
        controller,
        'window.__aliyunMetaInfo || ""',
      );
      if (!mounted ||
          generation != _initializeGeneration ||
          !_loading ||
          _cancelled) {
        return;
      }

      final raw = unwrapAliyunMetaInfoFromJsResult(result);
      if (raw.startsWith('ERROR:')) {
        _fail(raw.substring(6));
        return;
      }
      if (raw.isEmpty) {
        _fail('getMetaInfo() returned empty result');
        return;
      }

      _cancelTimers();
      if (!mounted || _cancelled) return;
      AliyunTrace.log(
        'metainfo_ready',
        component: 'MetaInfo',
        detail: 'metaInfoLen=${raw.length}',
      );
      await detachWebView();
      if (!mounted || _cancelled) return;
      widget.onMetaInfoReady(raw);
    } catch (e) {
      if (!mounted || generation != _initializeGeneration || _cancelled) return;
      _fail(e.toString());
    } finally {
      _readingMetaInfo = false;
    }
  }

  bool _isJsTruthy(Object? value) {
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1';
  }

  void _fail(String message) {
    if (_cancelled) return;
    _cancelTimers();
    AliyunTrace.log(
      'metainfo_failed',
      component: 'MetaInfo',
      detail: message,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    widget.onError?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}
