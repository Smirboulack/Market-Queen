import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Local-only secret storage.
///
/// The API keys never leave the machine, but they should not sit in a plain
/// text file either: anything that reads the config directory (a backup tool, a
/// sync client, a shared screen) would leak them. We encrypt with ChaCha20 and
/// authenticate with HMAC-SHA256, using a key derived from the machine
/// identity.
///
/// This protects against casual disclosure, not against someone who already
/// runs code as the user -- such an attacker can derive the same key.
///
/// The container format is byte-for-byte the one the Qt build wrote, so an
/// existing secrets.bin keeps working after the migration:
///   "SIS1" || nonce(12) || ciphertext || HMAC-SHA256(nonce || ciphertext)(32)
class SecretBox {
  SecretBox._();

  static const _magic = [0x53, 0x49, 0x53, 0x31]; // "SIS1"
  static const _nonceSize = 12;
  static const _tagSize = 32;

  /// 32-byte key derived from the machine + user identity.
  ///
  /// This is the one [seal] writes under, and its recipe is the Qt build's
  /// verbatim, so a secrets.bin from before the migration still opens.
  static Uint8List deviceKey() => _keyFrom(
        userName: Platform.environment['USERNAME'] ?? '',
        user: Platform.environment['USER'] ?? '',
      );

  /// Every key this machine might have sealed a file under, [deviceKey] first.
  ///
  /// The rest exist because the seed reads two environment variables, and on
  /// Windows one of them is not a property of the machine at all: `USER` is
  /// absent when the app is launched from Explorer and set by every
  /// MSYS-derived shell, so `flutter run` from Git Bash and a double-click on
  /// the exe derive two different keys on the same account. A blob written
  /// under one then fails to authenticate under the other -- and a failed
  /// unseal is indistinguishable from an empty store, so it read as "all your
  /// keys are gone".
  ///
  /// Trying the variants makes that a non-event: whichever one the file was
  /// written under, it opens, and [SettingsStore] re-seals it under the first
  /// so the next launch needs no guessing.
  static List<Uint8List> candidateKeys() {
    final env = Platform.environment;
    final userName = env['USERNAME'] ?? '';
    final user = env['USER'] ?? '';

    final seen = <String>{};
    final keys = <Uint8List>[];

    void add(String a, String b) {
      final key = _keyFrom(userName: a, user: b);
      // Two variants collapse onto one key whenever the variables agree --
      // which is the common case, so the list is usually one entry long.
      if (seen.add(_hex(key))) keys.add(key);
    }

    add(userName, user);
    if (user.isNotEmpty) add(userName, '');
    if (userName.isNotEmpty) add('', user);
    add('', '');

    return keys;
  }

  static Uint8List _keyFrom({required String userName, required String user}) {
    final seed = BytesBuilder();
    seed.add(utf8.encode('super-infinity/v1'));

    final machineId = _machineUniqueId();
    if (machineId.isNotEmpty) {
      seed.add(utf8.encode(machineId));
    } else {
      seed.add(utf8.encode(Platform.localHostname));
    }

    seed.add(utf8.encode(userName));
    seed.add(utf8.encode(user));

    return Uint8List.fromList(sha256.convert(seed.toBytes()).bytes);
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List seal(Uint8List plain, Uint8List key) {
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceSize, (_) => random.nextInt(256)),
    );

    final cipher = _chacha20Xor(plain, key, nonce);

    final out = BytesBuilder();
    out.add(_magic);
    out.add(nonce);
    out.add(cipher);
    out.add(_tag(key, nonce, cipher));
    return out.toBytes();
  }

  /// Returns null when the blob is corrupt or was produced on another machine.
  static Uint8List? unseal(Uint8List blob, Uint8List key) {
    if (blob.length < _magic.length + _nonceSize + _tagSize) return null;
    for (var i = 0; i < _magic.length; ++i) {
      if (blob[i] != _magic[i]) return null;
    }

    final nonce = blob.sublist(4, 4 + _nonceSize);
    final cipher = blob.sublist(4 + _nonceSize, blob.length - _tagSize);
    final tag = blob.sublist(blob.length - _tagSize);

    final expected = _tag(key, nonce, cipher);
    if (!_constantTimeEquals(expected, tag)) return null;

    return _chacha20Xor(cipher, key, nonce);
  }

  // ---- ChaCha20 ---------------------------------------------------------

  static Uint8List _chacha20Xor(Uint8List data, Uint8List key, Uint8List nonce) {
    assert(key.length == 32 && nonce.length == _nonceSize);

    final state = Uint32List(16);
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;
    for (var i = 0; i < 8; ++i) {
      state[4 + i] = _le32(key, i * 4);
    }
    state[12] = 1; // block counter, as in the Qt implementation
    for (var i = 0; i < 3; ++i) {
      state[13 + i] = _le32(nonce, i * 4);
    }

    final out = Uint8List(data.length);
    final block = Uint32List(16);
    final keystream = Uint8List(64);

    for (var offset = 0; offset < data.length; offset += 64) {
      _chachaBlock(block, state);
      for (var i = 0; i < 16; ++i) {
        keystream[i * 4 + 0] = block[i] & 0xff;
        keystream[i * 4 + 1] = (block[i] >> 8) & 0xff;
        keystream[i * 4 + 2] = (block[i] >> 16) & 0xff;
        keystream[i * 4 + 3] = (block[i] >> 24) & 0xff;
      }
      final n = min(64, data.length - offset);
      for (var i = 0; i < n; ++i) {
        out[offset + i] = data[offset + i] ^ keystream[i];
      }
      state[12] = (state[12] + 1) & 0xffffffff;
    }
    return out;
  }

  static void _chachaBlock(Uint32List out, Uint32List input) {
    final x = Uint32List.fromList(input);
    for (var i = 0; i < 10; ++i) {
      _quarterRound(x, 0, 4, 8, 12);
      _quarterRound(x, 1, 5, 9, 13);
      _quarterRound(x, 2, 6, 10, 14);
      _quarterRound(x, 3, 7, 11, 15);
      _quarterRound(x, 0, 5, 10, 15);
      _quarterRound(x, 1, 6, 11, 12);
      _quarterRound(x, 2, 7, 8, 13);
      _quarterRound(x, 3, 4, 9, 14);
    }
    for (var i = 0; i < 16; ++i) {
      out[i] = (x[i] + input[i]) & 0xffffffff;
    }
  }

  static void _quarterRound(Uint32List x, int a, int b, int c, int d) {
    x[a] = (x[a] + x[b]) & 0xffffffff;
    x[d] = _rotl32(x[d] ^ x[a], 16);
    x[c] = (x[c] + x[d]) & 0xffffffff;
    x[b] = _rotl32(x[b] ^ x[c], 12);
    x[a] = (x[a] + x[b]) & 0xffffffff;
    x[d] = _rotl32(x[d] ^ x[a], 8);
    x[c] = (x[c] + x[d]) & 0xffffffff;
    x[b] = _rotl32(x[b] ^ x[c], 7);
  }

  static int _rotl32(int x, int n) =>
      ((x << n) | (x >> (32 - n))) & 0xffffffff;

  static int _le32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  // ---- Authentication ---------------------------------------------------

  static Uint8List _tag(Uint8List key, Uint8List nonce, Uint8List cipher) {
    final macKey = sha256.convert([...key, ...utf8.encode('super-infinity-mac')]).bytes;
    final hmac = Hmac(sha256, macKey);
    return Uint8List.fromList(hmac.convert([...nonce, ...cipher]).bytes);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; ++i) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Answered once. It cannot change while the app runs, and on Windows the
  /// answer costs a subprocess -- which [candidateKeys] would otherwise pay for
  /// four times over.
  static String? _cachedMachineId;

  /// QSysInfo::machineUniqueId, per platform.
  static String _machineUniqueId() => _cachedMachineId ??= _readMachineId();

  static String _readMachineId() {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('reg', [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ]);
        final match =
            RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${result.stdout}');
        if (match != null) return match.group(1)!;
      } else if (Platform.isLinux) {
        for (final path in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
          final file = File(path);
          if (file.existsSync()) return file.readAsStringSync().trim();
        }
      } else if (Platform.isMacOS) {
        final result = Process.runSync('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
        final match =
            RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch('${result.stdout}');
        if (match != null) return match.group(1)!;
      }
    } on ProcessException {
      // Fall through: the hostname stands in.
    } on FileSystemException {
      // Same.
    }
    return '';
  }
}
