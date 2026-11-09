import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const scriptureChannel = MethodChannel('info.typikon.cs/scripture');
typedef LinkOpener = Future<bool> Function(Uri);

/// Prefer our installed Android reader, then use the ordinary HTTPS handler.
Future<bool> launchExternalUri(
  Uri uri, {
  LinkOpener? installed,
  LinkOpener? external,
  bool? android,
}) async {
  final scripture =
      uri.scheme == 'https' &&
      uri.host == 'www.typikon.info' &&
      uri.userInfo.isEmpty &&
      RegExp(r'^/bible/[a-z0-9-]+/[1-9][0-9]*$').hasMatch(uri.path);
  if (scripture &&
      (android ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))) {
    try {
      final opened = await (installed != null
          ? installed(uri)
          : scriptureChannel
                .invokeMethod<bool>('openScripture', {'url': uri.toString()})
                .then((v) => v == true));
      if (opened) return true;
    } catch (_) {
      // An older installation or a device without the reader uses the web link.
    }
  }
  try {
    return await (external != null
        ? external(uri)
        : launchUrl(uri, mode: LaunchMode.externalApplication));
  } catch (_) {
    return false;
  }
}

Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && await launchExternalUri(uri)) return;
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Не удалось открыть ссылку.')));
  }
}
