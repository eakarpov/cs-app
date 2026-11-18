/// Public source links are shared with the portal; cslexicon is an optional
/// Android intent entry. No native database IDs are interpreted on the device.
Uri? readerLink(String? route) {
  if (route == null || route.length > 8192) return null;
  final input = Uri.tryParse(route);
  if (input == null) return null;
  Uri? target;
  if (input.scheme == 'cslexicon' && input.host == 'reader') {
    target = Uri.tryParse(input.queryParameters['url'] ?? '');
  } else if (input.scheme.isEmpty && input.path.startsWith('/sources/')) {
    target = Uri.https('www.typikon.info', input.path, input.queryParameters);
  } else {
    target = input;
  }
  if (target == null ||
      target.scheme != 'https' ||
      !['www.typikon.info', 'typikon.info'].contains(target.host) ||
      target.userInfo.isNotEmpty ||
      target.hasPort ||
      !RegExp(
        r'^/(sources|reading|chants|canons|akathists|study|library)(/|$)',
      ).hasMatch(target.path)) {
    return null;
  }
  return target;
}
