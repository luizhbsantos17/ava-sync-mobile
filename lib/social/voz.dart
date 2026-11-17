import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../config.dart';
import '../plataforma.dart';
import 'api.dart';
import 'models.dart';
import 'service.dart';
import 'supabase_crypto.dart';

enum EstadoVoz { desconectado, conectando, conectado, reconectando }

/// Uma pessoa na chamada, do jeito que a tela precisa.
class PessoaNaVoz {
  final String userKey;
  final String nome;
  final bool eu;
  final bool falando;
  final double nivel;
  final bool mudo;
  final bool surdo;
  final VideoTrack? camera;
  final VideoTrack? tela;
  const PessoaNaVoz({
    required this.userKey,
    required this.nome,
    required this.eu,
    this.falando = false,
    this.nivel = 0,
    this.mudo = false,
    this.surdo = false,
    this.camera,
    this.tela,
  });
}

/// Chamada em canal de voz (issue #3), estilo Discord: várias pessoas, microfone,
/// "surdo", câmera e compartilhar a tela.
///
/// O áudio e o vídeo passam pelo LiveKit, cifrados no aparelho (E2EE) com uma chave
/// derivada da chave do grupo: o servidor de mídia não consegue ouvir nem ver.
/// O Supabase só sabe quem está em cada canal (para a lista mostrar antes de entrar).
class VozController extends ChangeNotifier {
  VozController._();
  static final VozController instance = VozController._();

  SocialApi get _api => SocialService.instance.api;

  Room? _room;
  EventsListener<RoomEvent>? _ouvinte;
  Timer? _batida;
  bool _segundoPlano = false;

  EstadoVoz estado = EstadoVoz.desconectado;
  SocialConversation? conversa;
  SocialChannel? canal;
  String? erro;

  /// Falha ao ligar câmera ou tela (a tela mostra e limpa).
  String? falhaMidia;

  /// Ligando a câmera ou a tela: o computador leva alguns segundos para abrir o dispositivo.
  bool ligandoMidia = false;
  bool mudo = Cfg.vozMudo;
  bool surdo = false;
  bool _mudoAntesDeSurdo = false;
  DateTime? desde;

  bool get ativa => estado != EstadoVoz.desconectado;
  bool get cameraLigada => _room?.localParticipant?.isCameraEnabled() ?? false;
  bool get telaLigada => _room?.localParticipant?.isScreenShareEnabled() ?? false;
  bool estaEm(String channelId) => ativa && canal?.id == channelId;

  /// Chave de mídia do canal: SHA-256 de "ava-sync-voz-v1|canal" + chave do grupo.
  /// Todos com a chave do grupo chegam à mesma; quem não tem, não ouve.
  @visibleForTesting
  static Future<String> chaveMidia(String channelId, List<int> chaveGrupo) async {
    final h = await Sha256().hash([...utf8.encode('ava-sync-voz-v1|$channelId|'), ...chaveGrupo]);
    return base64Url.encode(h.bytes);
  }

  // ------------------------------------------------------------ entrar e sair
  Future<void> entrar(SocialConversation c, SocialChannel ch) async {
    if (estaEm(ch.id)) return;
    if (ativa) await sair();
    erro = null;
    conversa = c;
    canal = ch;
    estado = EstadoVoz.conectando;
    notifyListeners();
    try {
      final chaveGrupo = await SupabaseSocialCrypto.groupKey(c.id);
      if (chaveGrupo == null) {
        throw const SocialApiException('Este aparelho ainda não tem a chave do grupo. Espere outro membro abrir o app.');
      }
      final r = Map<String, dynamic>.from(await _api.call('voice_join', {'channelId': ch.id, 'muted': mudo}) as Map);
      final e2ee = await E2EEOptions.sharedKey(await chaveMidia(ch.id, chaveGrupo));
      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          encryption: e2ee,
          defaultAudioCaptureOptions: const AudioCaptureOptions(noiseSuppression: true, echoCancellation: true, autoGainControl: true),
          defaultCameraCaptureOptions: const CameraCaptureOptions(params: VideoParametersPresets.h540_169),
          defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(params: VideoParametersPresets.screenShareH1080FPS15),
        ),
      );
      _room = room;
      _ouvinte = room.createListener()
        ..on<RoomDisconnectedEvent>((_) => _caiu())
        ..on<RoomReconnectingEvent>((_) {
          estado = EstadoVoz.reconectando;
          notifyListeners();
        })
        ..on<RoomReconnectedEvent>((_) {
          estado = EstadoVoz.conectado;
          notifyListeners();
        })
        ..on<TrackSubscribedEvent>((e) {
          // quem entra depois de eu ficar "surdo" também fica sem som
          if (surdo && e.track is RemoteAudioTrack) unawaited(e.track.disable());
          notifyListeners();
        })
        ..listen((_) => notifyListeners());
      room.addListener(notifyListeners);
      await room.connect('${r['url']}', '${r['token']}');
      await room.localParticipant?.setMicrophoneEnabled(!mudo);
      estado = EstadoVoz.conectado;
      desde = DateTime.now();
      _batida = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_contar()));
      unawaited(SocialService.instance.refresh());
    } catch (e) {
      erro = e is SocialApiException ? e.message : 'Não foi possível entrar na chamada: $e';
      await _limpar(avisarServidor: true);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> sair() async {
    await _limpar(avisarServidor: true);
    unawaited(SocialService.instance.refresh());
  }

  void _caiu() {
    if (estado == EstadoVoz.desconectado) return;
    erro = 'A chamada caiu.';
    unawaited(_limpar(avisarServidor: true));
  }

  Future<void> _limpar({required bool avisarServidor}) async {
    final ch = canal;
    _batida?.cancel();
    _batida = null;
    final room = _room;
    _room = null;
    await _ouvinte?.dispose();
    _ouvinte = null;
    if (room != null) {
      room.removeListener(notifyListeners);
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
    await _pararSegundoPlano();
    estado = EstadoVoz.desconectado;
    canal = null;
    conversa = null;
    desde = null;
    surdo = false;
    notifyListeners();
    if (avisarServidor && ch != null) {
      unawaited(_api.call('voice_leave', {'channelId': ch.id}).catchError((_) => null));
    }
  }

  /// Conta ao servidor que continuo na chamada e como estou (mudo, câmera...).
  Future<void> _contar() async {
    final ch = canal;
    if (ch == null) return;
    try {
      await _api.call('voice_state', {'channelId': ch.id, 'muted': mudo, 'deafened': surdo, 'video': cameraLigada, 'screen': telaLigada});
    } catch (_) {}
  }

  // ------------------------------------------------------------ controles
  Future<void> alternarMudo() async {
    if (surdo) {
      // tirar o mudo também tira o "surdo", como no Discord
      await alternarSurdo();
      if (!mudo) return;
    }
    mudo = !mudo;
    unawaited(Cfg.setVozMudo(mudo));
    await _room?.localParticipant?.setMicrophoneEnabled(!mudo);
    notifyListeners();
    unawaited(_contar());
  }

  Future<void> alternarSurdo() async {
    surdo = !surdo;
    if (surdo) {
      _mudoAntesDeSurdo = mudo;
      mudo = true;
    } else {
      mudo = _mudoAntesDeSurdo;
    }
    await _room?.localParticipant?.setMicrophoneEnabled(!mudo);
    for (final p in _room?.remoteParticipants.values ?? const <RemoteParticipant>[]) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t == null) continue;
        await (surdo ? t.disable() : t.enable());
      }
    }
    notifyListeners();
    unawaited(_contar());
  }

  Future<void> alternarCamera() async {
    final lp = _room?.localParticipant;
    if (lp == null || ligandoMidia) return;
    ligandoMidia = true;
    notifyListeners();
    try {
      await lp.setCameraEnabled(!cameraLigada);
    } catch (e) {
      falhaMidia = 'Não foi possível usar a câmera: $e';
    } finally {
      ligandoMidia = false;
    }
    notifyListeners();
    unawaited(_contar());
  }

  /// Compartilhar a tela. No computador, [escolher] abre a janela para escolher a
  /// tela ou o programa; no Android, o sistema pede permissão e o app segue em
  /// segundo plano enquanto compartilha.
  Future<void> alternarTela(Future<String?> Function() escolher) async {
    final lp = _room?.localParticipant;
    if (lp == null || ligandoMidia) return;
    try {
      if (telaLigada) {
        await lp.setScreenShareEnabled(false);
        await _pararSegundoPlano();
      } else if (Plataforma.desktop) {
        final fonte = await escolher();
        if (fonte == null) return;
        ligandoMidia = true;
        notifyListeners();
        await lp.setScreenShareEnabled(true,
            screenShareCaptureOptions: ScreenShareCaptureOptions(sourceId: fonte, maxFrameRate: 15, params: VideoParametersPresets.screenShareH1080FPS15));
      } else {
        if (!await rtc.Helper.requestCapturePermission()) return;
        await _ligarSegundoPlano();
        await lp.setScreenShareEnabled(true, captureScreenAudio: true);
      }
    } catch (e) {
      falhaMidia = 'Não foi possível compartilhar a tela: $e';
      if (!telaLigada) await _pararSegundoPlano();
    } finally {
      ligandoMidia = false;
    }
    notifyListeners();
    unawaited(_contar());
  }

  /// Android: serviço com notificação do tipo "mediaProjection", obrigatório para capturar a
  /// tela. Só pode subir DEPOIS de a pessoa autorizar a captura: antes disso o Android 14+
  /// derruba o app (SecurityException no código nativo, que o Dart não consegue pegar).
  Future<void> _ligarSegundoPlano() async {
    if (!Plataforma.celular || _segundoPlano) return;
    final ok = await FlutterBackground.initialize(
      androidConfig: const FlutterBackgroundAndroidConfig(
        notificationTitle: 'AVA Sync',
        notificationText: 'Em chamada no canal de voz',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: AndroidResource(name: 'ic_stat_ava', defType: 'drawable'),
      ),
    );
    if (ok) _segundoPlano = await FlutterBackground.enableBackgroundExecution();
  }

  Future<void> _pararSegundoPlano() async {
    if (!_segundoPlano) return;
    _segundoPlano = false;
    try {
      await FlutterBackground.disableBackgroundExecution();
    } catch (_) {}
  }

  /// Moderação: tira alguém da chamada.
  Future<void> desconectar(String userKey) async {
    final ch = canal;
    if (ch == null) return;
    await _api.call('voice_disconnect', {'channelId': ch.id, 'userKey': userKey});
  }

  /// Volume de uma pessoa (0 a 2; 1 = normal), só neste aparelho.
  final Map<String, double> volumes = {};
  Future<void> definirVolume(String userKey, double v) async {
    volumes[userKey] = v;
    final p = _room?.remoteParticipants[userKey];
    for (final pub in p?.audioTrackPublications ?? const <RemoteTrackPublication<RemoteAudioTrack>>[]) {
      final t = pub.track?.mediaStreamTrack;
      if (t != null) await rtc.Helper.setVolume(v, t);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ dispositivos (computador)
  Future<List<MediaDevice>> microfones() => Hardware.instance.audioInputs();
  Future<List<MediaDevice>> saidas() => Hardware.instance.audioOutputs();
  Future<void> usarMicrofone(MediaDevice d) async {
    await Hardware.instance.selectAudioInput(d);
    await _room?.setAudioInputDevice(d);
  }

  Future<void> usarSaida(MediaDevice d) async {
    await Hardware.instance.selectAudioOutput(d);
    await _room?.setAudioOutputDevice(d);
  }

  // ------------------------------------------------------------ quem está na chamada
  List<PessoaNaVoz> get pessoas {
    final room = _room;
    if (room == null) return const [];
    final lista = <PessoaNaVoz>[];
    final lp = room.localParticipant;
    if (lp != null) lista.add(_pessoa(lp, eu: true));
    for (final p in room.remoteParticipants.values) {
      lista.add(_pessoa(p, eu: false));
    }
    return lista;
  }

  PessoaNaVoz _pessoa(Participant p, {required bool eu}) {
    VideoTrack? camera, tela;
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is! VideoTrack || pub.muted) continue;
      if (pub.source == TrackSource.screenShareVideo) {
        tela = t;
      } else {
        camera = t;
      }
    }
    final perfil = SocialService.instance.profile(p.identity);
    return PessoaNaVoz(
      userKey: p.identity,
      nome: eu ? (SocialService.instance.me?.displayName ?? 'Você') : (perfil.username.isEmpty && p.name.isNotEmpty ? p.name : perfil.displayName),
      eu: eu,
      falando: p.isSpeaking,
      nivel: p.audioLevel,
      mudo: eu ? mudo : !p.isMicrophoneEnabled(),
      surdo: eu && surdo,
      camera: camera,
      tela: tela,
    );
  }
}
