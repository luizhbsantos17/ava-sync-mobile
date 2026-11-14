import 'package:device_calendar_plus/device_calendar_plus.dart';

import 'compromissos.dart';
import 'config.dart';
import 'util.dart';

/// Agenda do celular onde o app pode escrever.
class AgendaInfo {
  final String id;
  final String nome;
  final String conta;
  final bool google;
  const AgendaInfo(this.id, this.nome, this.conta, this.google);
  String get rotulo => conta.isEmpty || conta == nome ? nome : '$nome · $conta';
}

/// Evento a gravar (puro, testavel).
class EventoAgenda {
  final String titulo;
  final String descricao;
  final int inicio; // segundos
  final int fim;
  final bool diaTodo;
  final String link;
  const EventoAgenda(this.titulo, this.descricao, this.inicio, this.fim, this.diaTodo, this.link);

  /// Muda quando algo visivel do evento muda (evita regravar sem necessidade).
  String get assinatura => hashCurto('$titulo|$descricao|$inicio|$fim|$diaTodo|$link');
}

EventoAgenda eventoDe(Compromisso c) {
  final d = deSeg(c.ts)!;
  final diaTodo = c.tipo == 'evento' && d.hour == 0 && d.minute == 0 && c.duracao == 0;
  final marca = c.entregue ? '✓ ' : '';
  final titulo = '$marca${c.rotulo}: ${c.nome}';
  final descricao = [
    c.curso,
    if (c.tipo == 'tarefa') c.entregue ? 'Situação: entregue' : 'Situação: não entregue',
    if (c.link.isNotEmpty) c.link,
    'Criado pelo AVA Sync',
  ].join('\n');
  if (diaTodo) return EventoAgenda(titulo, descricao, c.ts, c.ts + 86400, true, c.link);
  // prazo: bloco de 30 min terminando no horario de entrega; evento: duracao real (ou 1 h)
  if (c.tipo != 'evento') return EventoAgenda(titulo, descricao, c.ts - 1800, c.ts, false, c.link);
  return EventoAgenda(titulo, descricao, c.ts, c.ts + (c.duracao > 0 ? c.duracao : 3600), false, c.link);
}

/// Quais compromissos vao para a agenda: os de ontem em diante (os mais antigos ficam como estao).
List<Compromisso> paraAgenda(List<Compromisso> lista, int agora, {bool soProvas = false}) =>
    lista.where((c) => c.ts > agora - 86400 && (!soProvas || c.cat == 'prova')).toList();

class Calendario {
  static DeviceCalendar get _p => DeviceCalendar.instance;

  static Future<bool> temPermissao() async => await _p.hasPermissions() == CalendarPermissionStatus.granted;

  static Future<bool> pedirPermissao() async {
    if (await temPermissao()) return true;
    return await _p.requestPermissions() == CalendarPermissionStatus.granted;
  }

  /// Agendas em que da para escrever. As da conta Google vem primeiro.
  static Future<List<AgendaInfo>> agendas() async {
    final out = [
      for (final c in await _p.listCalendars())
        if (!c.readOnly && !c.hidden) AgendaInfo(c.id, c.name, c.accountName ?? '', c.accountType == 'com.google')
    ];
    out.sort((a, b) => (b.google ? 1 : 0).compareTo(a.google ? 1 : 0));
    return out;
  }

  static DateTime _t(int seg, bool diaTodo) {
    final d = DateTime.fromMillisecondsSinceEpoch(seg * 1000);
    return diaTodo ? DateTime(d.year, d.month, d.day) : d;
  }

  static Future<String> _gravar(String agenda, String? id, EventoAgenda ev) async {
    final inicio = _t(ev.inicio, ev.diaTodo);
    final fim = _t(ev.fim, ev.diaTodo);
    final lembrete = [Duration(hours: ev.diaTodo ? 12 : 24)];
    if (id != null) {
      try {
        await _p.updateEvent(
          instanceId: id,
          title: ev.titulo,
          startDate: inicio,
          endDate: fim,
          isAllDay: ev.diaTodo,
          description: Patch.set(ev.descricao),
          url: ev.link.isEmpty ? const Patch.clear() : Patch.set(ev.link),
        );
        return id;
      } on DeviceCalendarException catch (e) {
        if (e.errorCode != DeviceCalendarError.notFound) rethrow;
        // a pessoa apagou o evento na agenda: cria de novo
      }
    }
    return _p.createEvent(
      calendarId: agenda,
      title: ev.titulo,
      startDate: inicio,
      endDate: fim,
      isAllDay: ev.diaTodo,
      description: ev.descricao,
      url: ev.link.isEmpty ? null : ev.link,
      reminders: lembrete,
    );
  }

  static Future<void> _apagar(String id) async {
    try {
      await _p.deleteEvent(instanceId: id);
    } on DeviceCalendarException catch (e) {
      if (e.errorCode != DeviceCalendarError.notFound) rethrow;
    }
  }

  /// Cria/atualiza os eventos dos compromissos e apaga os que sumiram do AVA.
  /// Devolve quantos eventos foram gravados ou removidos.
  static Future<int> sincronizar(List<Compromisso> lista) async {
    final agenda = Cfg.calendarioId;
    if (agenda.isEmpty || !await temPermissao()) return 0;
    final agora = agoraSeg();
    final salvos = Cfg.calendarioEventos;
    final vivos = <String>{};
    var mudancas = 0;
    try {
      for (final c in paraAgenda(lista, agora, soProvas: Cfg.calendarioSoProvas)) {
        vivos.add(c.chave);
        final ev = eventoDe(c);
        final antes = mapa(salvos[c.chave]);
        final mesmaAgenda = antes['agenda'] == agenda;
        if (mesmaAgenda && antes['h'] == ev.assinatura) continue;
        final id = await _gravar(agenda, mesmaAgenda ? antes['id'] as String? : null, ev);
        salvos[c.chave] = {'id': id, 'agenda': agenda, 'h': ev.assinatura, 'ts': c.ts};
        mudancas++;
      }
      // sumiu do AVA (ou saiu do filtro) e ainda e futuro: apaga da agenda
      for (final k in salvos.keys.toList()) {
        if (vivos.contains(k)) continue;
        final s = mapa(salvos[k]);
        final ts = (s['ts'] as num?)?.toInt() ?? 0;
        if (s['agenda'] == agenda && ts > agora - 86400) {
          await _apagar('${s['id']}');
          mudancas++;
        }
        salvos.remove(k); // passados ficam na agenda, so deixam de ser acompanhados
      }
    } finally {
      await Cfg.setCalendarioEventos(salvos);
    }
    return mudancas;
  }

  /// Apaga da agenda os eventos futuros que o app criou (ao desligar ou trocar de agenda).
  static Future<void> limpar() async {
    final agora = agoraSeg();
    if (await temPermissao()) {
      for (final s in Cfg.calendarioEventos.values.map(mapa)) {
        if (((s['ts'] as num?)?.toInt() ?? 0) <= agora) continue;
        try {
          await _apagar('${s['id']}');
        } catch (_) {}
      }
    }
    await Cfg.setCalendarioEventos({});
  }
}
