/// Aliyun H5 MetaInfo bootstrap HTML and timing constants.
///
/// Used by [AliyunMetaInfoLoader] (hidden WebView in verification flow).
abstract final class AliyunMetaInfoBootstrap {
  /// Official Aliyun H5 SDK URL (see CloudAuth H5 integration docs).
  static const jsUrl =
      'https://o.alicdn.com/yd-cloudauth/cloudauth-cdn/jsvm_all.js';

  static const bootstrapTimeout = Duration(seconds: 30);
  static const navigationTimeout = Duration(seconds: 45);
  static const pollInterval = Duration(milliseconds: 500);
  static const jsCallTimeout = Duration(seconds: 5);

  /// HTML injected into WebView to load jsvm_all.js and expose getMetaInfo().
  static String bootstrapHtml({String? jsUrlOverride}) {
    final scriptUrl = jsUrlOverride ?? jsUrl;
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <script>
    window.__aliyunBootstrapReady = false;
    window.__aliyunMetaInfo = "";

    function aliyunMarkReady(value) {
      window.__aliyunMetaInfo = value;
      window.__aliyunBootstrapReady = true;
    }

    function aliyunOnSdkError() {
      aliyunMarkReady("ERROR:Failed to load jsvm_all.js from CDN ($scriptUrl). Check network or VPN.");
    }

    function aliyunOnSdkReady() {
      try {
        if (typeof getMetaInfo !== "function") {
          aliyunMarkReady("ERROR:getMetaInfo is unavailable after SDK load");
        } else {
          var meta = getMetaInfo();
          aliyunMarkReady(typeof meta === "string" ? meta : JSON.stringify(meta));
        }
      } catch (e) {
        aliyunMarkReady("ERROR:" + (e && e.message ? e.message : e));
      }
    }
  </script>
  <script src="$scriptUrl" onload="aliyunOnSdkReady()" onerror="aliyunOnSdkError()"></script>
</head>
<body></body>
</html>
''';
  }
}
