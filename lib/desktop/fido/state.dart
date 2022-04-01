import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/models.dart';
import '../../fido/models.dart';
import '../../fido/state.dart';
import '../models.dart';
import '../rpc.dart';
import '../state.dart';

final _log = Logger('desktop.fido.state');

final _pinProvider = StateProvider.autoDispose.family<String?, DevicePath>(
  (ref, _) => null,
);

final _sessionProvider =
    Provider.autoDispose.family<RpcNodeSession, DevicePath>(
  (ref, devicePath) {
    // Make sure the pinProvider is held for the duration of the session.
    ref.watch(_pinProvider(devicePath));
    return RpcNodeSession(
        ref.watch(rpcProvider), devicePath, ['fido', 'ctap2']);
  },
);

final desktopFidoState = StateNotifierProvider.autoDispose
    .family<FidoStateNotifier, AsyncValue<FidoState>, DevicePath>(
  (ref, devicePath) {
    final session = ref.watch(_sessionProvider(devicePath));
    final notifier = _DesktopFidoStateNotifier(session);
    session.setErrorHandler('state-reset', (_) async {
      ref.refresh(_sessionProvider(devicePath));
    });
    ref.onDispose(() {
      session.unsetErrorHandler('state-reset');
    });
    return notifier..refresh();
  },
);

class _DesktopFidoStateNotifier extends FidoStateNotifier {
  final RpcNodeSession _session;
  _DesktopFidoStateNotifier(this._session) : super();

  Future<void> refresh() => updateState(() async {
        final result = await _session.command('get');
        _log.config('application status', jsonEncode(result));
        return FidoState.fromJson(result['data']);
      });

  @override
  Stream<InteractionEvent> reset() {
    final controller = StreamController<InteractionEvent>();
    final signaler = Signaler();
    signaler.signals
        .where((s) => s.status == 'reset')
        .map((signal) => InteractionEvent.values
            .firstWhere((e) => e.name == signal.body['state']))
        .listen(controller.sink.add);

    controller.onCancel = () {
      if (!controller.isClosed) {
        signaler.cancel();
      }
    };
    controller.onListen = () async {
      try {
        await _session.command('reset', signal: signaler);
        await refresh();
        await controller.sink.close();
      } catch (e) {
        controller.sink.addError(e);
      }
    };

    return controller.stream;
  }

  @override
  Future<PinResult> setPin(String newPin, {String? oldPin}) async {
    try {
      await _session.command('set_pin', params: {
        'pin': oldPin,
        'new_pin': newPin,
      });
      await refresh();
      return PinResult.success();
    } on RpcError catch (e) {
      if (e.status == 'pin-validation') {
        return PinResult.failed(e.body['retries'], e.body['auth_blocked']);
      }
      rethrow;
    }
  }
}

final desktopFidoPinProvider = StateNotifierProvider.autoDispose
    .family<PinNotifier, bool, DevicePath>((ref, devicePath) {
  return _DesktopPinNotifier(ref.watch(_sessionProvider(devicePath)),
      ref.watch(_pinProvider(devicePath).notifier));
});

class _DesktopPinNotifier extends PinNotifier {
  final RpcNodeSession _session;
  final StateController<String?> _pinController;

  _DesktopPinNotifier(this._session, this._pinController)
      : super(_pinController.state != null);

  @override
  Future<PinResult> unlock(String pin) async {
    try {
      await _session.command(
        'verify_pin',
        params: {'pin': pin},
      );
      _pinController.state = pin;

      return PinResult.success();
    } on RpcError catch (e) {
      if (e.status == 'pin-validation') {
        _pinController.state = null;
        return PinResult.failed(e.body['retries'], e.body['auth_blocked']);
      }
      rethrow;
    }
  }
}

final desktopFingerprintProvider = StateNotifierProvider.autoDispose.family<
    FidoFingerprintsNotifier,
    AsyncValue<List<Fingerprint>>,
    DevicePath>((ref, devicePath) {
  final session = ref.watch(_sessionProvider(devicePath));
  final notifier = _DesktopFidoFingerprintsNotifier(
    session,
    ref.watch(_pinProvider(devicePath).notifier),
  );
  session.setErrorHandler('auth-required', (_) async {
    final pin = ref.read(_pinProvider(devicePath));
    if (pin != null) {
      await notifier._unlock(pin);
    }
  });
  ref.onDispose(() {
    session.unsetErrorHandler('auth-required');
  });
  return notifier;
});

class _DesktopFidoFingerprintsNotifier extends FidoFingerprintsNotifier {
  final RpcNodeSession _session;
  final StateController<String?> _pinNotifier;

  _DesktopFidoFingerprintsNotifier(this._session, this._pinNotifier) {
    final pin = _pinNotifier.state;
    if (pin != null) {
      _unlock(pin);
    } else {
      state = const AsyncValue.error('locked');
    }
  }

  Future<void> _unlock(String pin) async {
    try {
      await _session.command(
        'unlock',
        target: ['fingerprints'],
        params: {'pin': pin},
      );
      await _refresh();
    } on RpcError catch (e) {
      if (e.status == 'pin-validation') {
        _pinNotifier.state = null;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _refresh() async {
    final result = await _session.command('fingerprints');
    setItems((result['children'] as Map<String, dynamic>)
        .entries
        .map((e) => Fingerprint(e.key, e.value['name']))
        .toList());
  }

  @override
  Future<void> deleteFingerprint(Fingerprint fingerprint) async {
    await _session
        .command('delete', target: ['fingerprints', fingerprint.templateId]);
    await _refresh();
  }

  @override
  Stream<FingerprintEvent> registerFingerprint({String? name}) {
    final controller = StreamController<FingerprintEvent>();
    final signaler = Signaler();
    signaler.signals.listen((signal) {
      switch (signal.status) {
        case 'capture':
          controller.sink
              .add(FingerprintEvent.capture(signal.body['remaining']));
          break;
        case 'capture-error':
          controller.sink.add(FingerprintEvent.error(signal.body['code']));
          break;
      }
    });

    controller.onCancel = () {
      if (!controller.isClosed) {
        signaler.cancel();
      }
    };
    controller.onListen = () async {
      try {
        final result = await _session.command(
          'add',
          target: ['fingerprints'],
          params: {'name': name},
          signal: signaler,
        );
        controller.sink
            .add(FingerprintEvent.complete(Fingerprint.fromJson(result)));
        await _refresh();
        await controller.sink.close();
      } catch (e) {
        controller.sink.addError(e);
      }
    };

    return controller.stream;
  }

  @override
  Future<Fingerprint> renameFingerprint(
      Fingerprint fingerprint, String name) async {
    await _session.command('rename',
        target: ['fingerprints', fingerprint.templateId],
        params: {'name': name});
    final renamed = fingerprint.copyWith(name: name);
    await _refresh();
    return renamed;
  }
}

final desktopCredentialProvider = StateNotifierProvider.autoDispose.family<
    FidoCredentialsNotifier,
    AsyncValue<List<FidoCredential>>,
    DevicePath>((ref, devicePath) {
  final session = ref.watch(_sessionProvider(devicePath));
  final notifier = _DesktopFidoCredentialsNotifier(
    session,
    ref.watch(_pinProvider(devicePath).notifier),
  );
  session.setErrorHandler('auth-required', (_) async {
    final pin = ref.read(_pinProvider(devicePath));
    if (pin != null) {
      await notifier._unlock(pin);
    }
  });
  ref.onDispose(() {
    session.unsetErrorHandler('auth-required');
  });
  return notifier;
});

class _DesktopFidoCredentialsNotifier extends FidoCredentialsNotifier {
  final RpcNodeSession _session;
  final StateController<String?> _pinNotifier;

  _DesktopFidoCredentialsNotifier(this._session, this._pinNotifier) {
    final pin = _pinNotifier.state;
    if (pin != null) {
      _unlock(pin);
    } else {
      state = const AsyncValue.error('locked');
    }
  }

  Future<void> _unlock(String pin) async {
    try {
      await _session.command(
        'unlock',
        target: ['credentials'],
        params: {'pin': pin},
      );
      await _refresh();
    } on RpcError catch (e) {
      if (e.status == 'pin-validation') {
        _pinNotifier.state = null;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _refresh() async {
    final List<FidoCredential> creds = [];
    final rps = await _session.command('credentials');
    for (final rpId in (rps['children'] as Map<String, dynamic>).keys) {
      final result = await _session.command(rpId, target: ['credentials']);
      for (final e in (result['children'] as Map<String, dynamic>).entries) {
        creds.add(FidoCredential(
            rpId: rpId,
            credentialId: e.key,
            userId: e.value['user_id'],
            userName: e.value['user_name']));
      }
    }
    setItems(creds);
  }

  @override
  Future<void> deleteCredential(FidoCredential credential) async {
    await _session.command('delete', target: [
      'credentials',
      credential.rpId,
      credential.credentialId,
    ]);
    await _refresh();
  }
}