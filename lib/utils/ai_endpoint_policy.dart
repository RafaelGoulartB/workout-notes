import 'dart:io';

/// Which AI provider endpoints the app talks to without TLS or a token.
///
/// A plain `http://` endpoint is only accepted for hosts on the user's own
/// machine or network (loopback, private and link-local addresses,
/// `localhost`, `*.local`): a LAN Ollama or llama.cpp. Anything else must use
/// `https://`, so a token or the user's data never crosses the internet in
/// clear text. The same check backs the provider editor and the service.
abstract final class AiEndpointPolicy {
  /// Whether [host] is `localhost`, a `*.local` name or an IP address in a
  /// loopback (127/8, ::1), private (10/8, 172.16/12, 192.168/16, fc00::/7)
  /// or link-local (169.254/16, fe80::/10) range. Names that merely start
  /// like an address (`10.evil.com`) are not local.
  static bool isLocalHost(String host) {
    var name = host.trim().toLowerCase();
    if (name.startsWith('[') && name.endsWith(']')) {
      name = name.substring(1, name.length - 1);
    }
    while (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
    if (name.isEmpty) return false;
    if (name == 'localhost' || name.endsWith('.local')) return true;
    final percent = name.indexOf('%'); // IPv6 zone id (fe80::1%wlan0)
    final address = InternetAddress.tryParse(
      percent < 0 ? name : name.substring(0, percent),
    );
    return address != null && _isLocalAddress(address);
  }

  /// Whether the host of [baseUrl] is local (see [isLocalHost]).
  static bool isLocalEndpoint(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri != null && isLocalHost(uri.host);
  }

  /// Whether [baseUrl] may be used: `https` for any host, `http` only for
  /// local hosts. Other schemes and URLs without a host are refused.
  static bool isAllowed(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.host.isEmpty) return false;
    return switch (uri.scheme.toLowerCase()) {
      'https' => true,
      'http' => isLocalHost(uri.host),
      _ => false,
    };
  }

  static bool _isLocalAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) return _isLocalV4(bytes);
    if (bytes.length != 16) return false;
    // IPv4-mapped (::ffff:a.b.c.d) follows the embedded IPv4 address.
    final mapped =
        bytes.take(10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (mapped) return _isLocalV4(bytes.sublist(12));
    final loopback =
        bytes.take(15).every((b) => b == 0) && bytes[15] == 1; // ::1
    final uniqueLocal = (bytes[0] & 0xfe) == 0xfc; // fc00::/7
    final linkLocal =
        bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80; // fe80::/10
    return loopback || uniqueLocal || linkLocal;
  }

  static bool _isLocalV4(List<int> b) {
    if (b.length != 4) return false;
    return b[0] == 127 ||
        b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }
}
