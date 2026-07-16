import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/ai_client.dart';
import '../../core/turnstile.dart';
import '../../data/repos.dart';
import '../../domain/ai_turns.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _Bubble {
  _Bubble.user(this.text)
      : isUser = true,
        turn = null;
  _Bubble.ai(this.turn, this.text) : isUser = false;
  final bool isUser;
  final String text;
  final AiTurn? turn;
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _ai = AiClient();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  final List<_Bubble> _bubbles = [];
  String _kind = 'producto';
  bool _wholesale = false;
  bool _busy = false;
  List<String> _categories = [];
  List<String> _rubros = [];
  AiReady? _ready;

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _bubbles.add(_Bubble.user(text));
      _messages.add(AiMessage('user', text));
      _input.clear();
    });
    try {
      String? token;
      if (_messages.length == 1) token = await getTurnstileToken(context);
      final turn = await _ai.sendTurn(
          messages: _messages,
          kind: _kind,
          wholesale: _wholesale,
          turnstileToken: token);
      _messages.add(AiMessage('assistant', jsonEncode(_turnToJson(turn))));
      await _handleTurn(turn);
    } on AiHttpException catch (e) {
      _toast(e.status == 429
          ? 'Un momento… demasiadas solicitudes. Espera 1 minuto.'
          : e.message);
      setState(() {
        _messages.removeLast();
        _bubbles.removeLast();
      });
    } catch (e) {
      _toast('Algo falló. Intenta de nuevo.');
      setState(() {
        _messages.removeLast();
        _bubbles.removeLast();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  Future<void> _handleTurn(AiTurn turn) async {
    switch (turn) {
      case AiQuestion q:
        setState(() => _bubbles.add(_Bubble.ai(q, q.question)));
      case AiKindSwitch k:
        setState(() => _bubbles.add(_Bubble.ai(k, k.message)));
      case AiImageRequest _:
        // v1 sin fotos: responder y seguir.
        await _send('No puedo enviar foto ahora, sigamos sin foto.');
      case AiRouting r:
        setState(() {
          _categories = r.categories;
          _rubros = r.rubros;
          _bubbles.add(_Bubble.ai(r, '${r.message} ${r.categories.join(", ")}'));
        });
        await _send('ok');
      case AiReady rd:
        setState(() {
          _ready = rd;
          _bubbles.add(_Bubble.ai(rd, '¡Listo! Revisa tu solicitud:'));
        });
    }
  }

  Map<String, dynamic> _turnToJson(AiTurn t) => switch (t) {
        AiQuestion q => {
            'type': 'question',
            'question': q.question,
            'options': q.options,
            'allowOther': q.allowOther
          },
        AiImageRequest i => {
            'type': 'image_request',
            'message': i.message,
            'hint': i.hint
          },
        AiRouting r => {
            'type': 'routing',
            'message': r.message,
            'categories': r.categories,
            'rubros': r.rubros
          },
        AiReady r => {
            'type': 'ready',
            'title': r.title,
            'bullets': r.bullets,
            if (r.wholesale) 'wholesale': true
          },
        AiKindSwitch k => {
            'type': 'kind_switch',
            'message': k.message,
            'suggested_kind': k.suggestedKind,
            'options': k.options
          },
      };

  Future<void> _submit() async {
    final r = _ready!;
    if (_rubros.isEmpty) {
      _toast('La solicitud no tiene rubros; escribe "corrige la categoría" para reintentar.');
      return;
    }
    setState(() => _busy = true);
    try {
      await submitRequest(
          title: r.title,
          bullets: r.bullets,
          kind: _kind,
          wholesale: r.wholesale || _wholesale,
          categories: _categories,
          rubros: _rubros);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('¡Solicitud enviada! 🎉')));
      context.go('/client');
    } catch (_) {
      _toast('No se pudo enviar la solicitud.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final started = _messages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Crear solicitud')),
      body: Column(children: [
        if (!started)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'producto', label: Text('Producto')),
                  ButtonSegment(value: 'servicio', label: Text('Servicio')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  if (_kind == 'servicio') _wholesale = false;
                }),
              ),
              const SizedBox(width: 8),
              if (_kind == 'producto')
                FilterChip(
                    label: const Text('Al por mayor'),
                    selected: _wholesale,
                    onSelected: (v) => setState(() => _wholesale = v)),
            ]),
          ),
        Expanded(
          child: _bubbles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        'Dinos qué buscas y la IA arma tu solicitud\npara que los proveedores te oferten.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _bubbles.length,
                  itemBuilder: (_, i) {
                    final b = _bubbles[i];
                    final isLast = i == _bubbles.length - 1;
                    return Column(
                      crossAxisAlignment:
                          b.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color:
                                b.isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(b.text),
                        ),
                        if (!b.isUser && isLast && !_busy) _turnActions(b.turn),
                      ],
                    );
                  },
                ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_ready == null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _input,
                enabled: !_busy,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: started ? 'Escribe tu respuesta…' : '¿Qué estás buscando?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.send), onPressed: () => _send(_input.text)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _turnActions(AiTurn? t) => switch (t) {
        AiQuestion q => Wrap(spacing: 8, runSpacing: 4, children: [
            for (final op in q.options)
              ActionChip(label: Text(op), onPressed: () => _send(op)),
          ]),
        AiKindSwitch k => Wrap(spacing: 8, runSpacing: 4, children: [
            for (final op in k.options)
              ActionChip(
                  label: Text(op),
                  onPressed: () {
                    final low = op.toLowerCase();
                    if (low.startsWith('sí') || low.startsWith('si')) {
                      setState(() => _kind = k.suggestedKind);
                    }
                    _send(op);
                  }),
          ]),
        AiReady r => Card(
            margin: const EdgeInsets.only(top: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final b in r.bullets) Text('• $b'),
                if (r.wholesale || _wholesale)
                  const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Chip(label: Text('Al por mayor'))),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: const Text('Enviar solicitud')),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => setState(() => _ready = null),
                      child: const Text('Corregir algo')),
                ]),
              ]),
            ),
          ),
        _ => const SizedBox.shrink(),
      };
}
