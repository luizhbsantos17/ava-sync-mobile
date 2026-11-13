import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../estado_app.dart';
import '../moodle.dart';

class LoginTela extends StatefulWidget {
  const LoginTela({super.key});
  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _site = TextEditingController(text: Cfg.site.isEmpty ? 'https://' : Cfg.site);
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  bool _ocupado = false;
  bool _verSenha = false;
  String? _msg;
  bool _msgErro = false;

  String get _siteLimpo => _site.text.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _verificar() async {
    setState(() {
      _ocupado = true;
      _msg = null;
    });
    final r = await Moodle.verificarSite(_siteLimpo);
    setState(() {
      _ocupado = false;
      _msg = r ?? 'Site compatível. Pode entrar.';
      _msgErro = r != null;
    });
  }

  Future<void> _entrar() async {
    if (!_siteLimpo.startsWith('http')) {
      setState(() {
        _msg = 'Endereço inválido.';
        _msgErro = true;
      });
      return;
    }
    setState(() {
      _ocupado = true;
      _msg = null;
    });
    try {
      final token = await Moodle.gerarToken(_siteLimpo, _usuario.text.trim(), _senha.text);
      _senha.clear(); // a senha nao fica guardada em lugar nenhum
      await Cfg.setSite(_siteLimpo);
      await Cfg.salvarToken(token);
      await app.aposLogin();
    } catch (e) {
      setState(() {
        _msg = '$e';
        _msgErro = true;
      });
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  void dispose() {
    _senha.clear();
    _site.dispose();
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.school_rounded, size: 64, color: cs.primary),
                  const SizedBox(height: 8),
                  Text('AVA Sync', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Seu Moodle no celular: prazos, materiais e avisos, até offline.',
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _site,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Endereço do Moodle',
                      hintText: 'https://ava.suainstituicao.edu.br',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                          tooltip: 'Verificar site', onPressed: _ocupado ? null : _verificar, icon: const Icon(Icons.fact_check)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Usuário', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senha,
                    obscureText: !_verSenha,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                          onPressed: () => setState(() => _verSenha = !_verSenha),
                          icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_msg != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_msg!, style: TextStyle(color: _msgErro ? cs.error : Colors.green)),
                    ),
                  FilledButton(
                    onPressed: _ocupado ? null : _entrar,
                    child: _ocupado
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.lock_outline, color: cs.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                              'A senha é usada uma vez para gerar uma chave de acesso (token), igual ao app oficial do Moodle. '
                              'A senha não é salva. A chave fica guardada criptografada neste celular e você pode apagá-la em Ajustes > Sair.',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
