import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Clears only the embedded WebView store, never Chrome or the app's files.
class FacebookWebSessionService {
  static const origins = [
    'https://facebook.com',
    'https://www.facebook.com',
    'https://m.facebook.com',
    'https://accountscenter.facebook.com',
  ];

  static Future<bool> clear({InAppWebViewController? controller}) async {
    var complete = true;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action().timeout(const Duration(seconds: 10));
      } catch (_) {
        complete = false;
      }
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      HeadlessInAppWebView? temporary;
      var target = controller;
      if (target == null) {
        temporary = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('about:blank')),
        );
        await attempt(() async {
          await temporary!.run();
          target = temporary.webViewController;
          if (target == null) throw StateError('WebView cleanup unavailable');
        });
      }
      for (final origin in origins) {
        await attempt(() async {
          if (target == null) throw StateError('WebView cleanup unavailable');
          await target!.callDevToolsProtocolMethod(
            methodName: 'Storage.clearDataForOrigin',
            parameters: {'origin': origin, 'storageTypes': 'all'},
          );
        });
      }
      await attempt(() async {
        if (target == null) throw StateError('WebView cleanup unavailable');
        await target!.callDevToolsProtocolMethod(
          methodName: 'Network.clearBrowserCache',
        );
      });
      if (temporary != null) await attempt(() => temporary!.dispose());
    } else {
      await attempt(() => WebStorageManager.instance().deleteAllData());
      await attempt(() => InAppWebViewController.clearAllCache());
    }
    final manager = CookieManager.instance();
    final seen = <String>{};
    for (final origin in origins) {
      await attempt(() async {
        for (final cookie in await manager.getCookies(
          url: WebUri('$origin/'),
        )) {
          final domain = cookie.domain ?? '';
          if ((domain == 'facebook.com' || domain.endsWith('.facebook.com')) &&
              seen.add('$domain/${cookie.path}/${cookie.name}')) {
            final deleted = await manager.deleteCookie(
              url: WebUri('$origin/'),
              name: cookie.name,
              domain: domain,
              path: cookie.path ?? '/',
            );
            if (!deleted) complete = false;
          }
        }
      });
    }
    return complete;
  }
}
