import 'package:material_ui/material_ui.dart';

import '../../config.dart';

const _categorias = <(IconData, String, String)>[
  (Icons.emoji_emotions_outlined, 'Carinhas',
      '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 💀 💩 🤡 👻 👽 🤖 😺 😸 😹 😻 🙈 🙉 🙊'),
  (Icons.waving_hand_outlined, 'Gestos',
      '👍 👎 👏 🙌 👐 🤝 🙏 ✌️ 🤞 🤟 🤘 👌 🤌 🤏 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤙 💪 🫡 🫶 ✍️ 👀 🧠 🫠 🤷 🤦 🙋 🙇 💁 🙆 🙅'),
  (Icons.favorite_border_rounded, 'Símbolos',
      '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ ⭐ 🌟 💫 🔥 💥 💯 ✅ ❌ ❗ ❓ ⚠️ 🚫 💤 🎉 🎊 🎈 🏆 🥇 🎯 💡 📌 📎 🔔 🔕 ♻️ ➕ ➖ 🆗 🆕 🔝'),
  (Icons.school_outlined, 'Estudos',
      '📚 📖 📝 ✏️ 🖊️ 📒 📓 📔 📕 📗 📘 📙 📄 📃 📑 📊 📈 📉 🗂️ 📁 📅 📆 🗓️ ⏰ ⏳ ⌛ 🎓 🏫 🧮 🔬 🧪 🧬 💻 🖥️ ⌨️ 🖱️ 📱 🔋 🔌 💾 🖨️ 📡 🧑‍💻 👩‍🏫 👨‍🏫 🧑‍🎓'),
  (Icons.local_cafe_outlined, 'Comida e coisas',
      '☕ 🍵 🧃 🥤 🍺 🍕 🍔 🍟 🌭 🥪 🌮 🍝 🍜 🍣 🍩 🍪 🎂 🍰 🍫 🍿 🍎 🍌 🍉 🍇 🍓 🥑 🎮 🕹️ 🎧 🎵 🎶 🎸 ⚽ 🏀 🏐 🎲 🚗 🚌 ✈️ 🏠 🌧️ ☀️ 🌈 ❄️ 🌙 🐶 🐱 🐸 🐼 🦊'),
];

/// Grade de emojis com os usados recentemente no topo.
Future<String?> escolherEmoji(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _Seletor(),
  );
}

class _Seletor extends StatefulWidget {
  const _Seletor();
  @override
  State<_Seletor> createState() => _SeletorState();
}

class _SeletorState extends State<_Seletor> {
  int _aba = -1;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lista = _aba < 0 ? Cfg.socialEmojisRecentes : _categorias[_aba].$3.split(' ');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .5,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            _botao(Icons.history_rounded, -1, cs),
            for (var i = 0; i < _categorias.length; i++) _botao(_categorias[i].$1, i, cs),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 48),
            itemCount: lista.length,
            itemBuilder: (context, i) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(context, lista[i]),
              child: Center(child: Text(lista[i], style: const TextStyle(fontSize: 26))),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _botao(IconData icone, int i, ColorScheme cs) => IconButton(
        isSelected: _aba == i,
        icon: Icon(icone, color: _aba == i ? cs.primary : cs.onSurfaceVariant),
        tooltip: i < 0 ? 'Recentes' : _categorias[i].$2,
        onPressed: () => setState(() => _aba = i),
      );
}
