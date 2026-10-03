import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'features/analysis/presentation/analytics_screen.dart';
import 'features/recording/presentation/recording_screen.dart';
import 'features/recording/presentation/recording_controller.dart';
import 'features/coach/presentation/coach_screen.dart';
import 'shared/api_ui.dart';
import 'shared/job_status.dart';
import 'shared/local_player.dart';
import 'l10n/strings.dart';

class StudentHome extends ConsumerStatefulWidget {
  const StudentHome({super.key, required this.logout});
  final Future<void> Function() logout;
  @override
  ConsumerState<StudentHome> createState() => _Student();
}

class _Student extends ConsumerState<StudentHome> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final labels = [
      tr(lang, 'record'),
      tr(lang, 'analytics'),
      tr(lang, 'coach'),
      'Kutubxona',
      'Tarix',
      'Sozlamalar',
    ];
    final screens = [
      const RecordingScreen(),
      const AnalyticsScreen(),
      const CoachScreen(),
      const LibraryScreen(),
      const HistoryScreen(),
      SettingsScreen(logout: widget.logout),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Baxshi AI • ${labels[selected]}')),
      drawer: NavigationDrawer(
        selectedIndex: selected,
        onDestinationSelected: (i) async {
          await ref.read(recordingProvider.notifier).pause();
          if (!context.mounted) return;
          Navigator.pop(context);
          setState(() => selected = i);
        },
        children: [
          const Padding(padding: EdgeInsets.all(24), child: Text('BAXSHI AI')),
          for (var i = 0; i < labels.length; i++)
            NavigationDrawerDestination(
              icon: Icon(
                [
                  Icons.mic,
                  Icons.insights,
                  Icons.auto_awesome,
                  Icons.library_music,
                  Icons.history,
                  Icons.settings,
                ][i],
              ),
              label: Text(labels[i]),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(selected), child: screens[selected]),
      ),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) => DataView(
    path: '/v1/contents',
    builder: (data) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if ((data as List).isEmpty) const Text('Hali material joylanmagan.'),
        for (final x in data)
          Card(
            child: ExpansionTile(
              title: Text('${x['title']}'),
              subtitle: Text('${x['kind']}'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('${x['body']}\n${x['url'] ?? ''}'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(localStoreProvider),
        id = ref.watch(accountProvider);
    final records = store.box.keys
        .where((k) => k.toString().startsWith('$id:recording:'))
        .map((k) => store.read(k as String)!)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Mahalliy yozuvlar',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        for (final r in records)
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('${r['created_at']}'),
                  subtitle: Text('${r['duration_seconds']} sekund'),
                ),
                LocalPlayer(
                  path: r['path'] as String,
                  playLabel: 'Tinglash',
                  errorLabel: 'Fayl ochilmadi',
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Server tahlillari',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        DataView(
          path: '/v1/analyses',
          builder: (d) => Column(
            children: [
              for (final j in d as List) JobStatus(id: j['id'] as String),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Mashq kundaligi'),
        FilledButton(
          onPressed: () async {
            final data = await editForm(context, 'Bugungi mashq', {
              'day': DateTime.now().toIso8601String().substring(0, 10),
              'minutes': 10,
              'note': '',
            });
            if (data != null && context.mounted) {
              await act(context, () async {
                await ref
                    .read(apiProvider)
                    .dio
                    .put<void>('/v1/practice', data: data);
                ref.invalidate(dataProvider('/v1/practice'));
              });
            }
          },
          child: const Text('Mashqni saqlash'),
        ),
        DataView(
          path: '/v1/practice',
          builder: (d) => Column(
            children: [
              for (final x in d as List)
                ListTile(
                  title: Text('${x['day']} • ${x['minutes']} min'),
                  subtitle: Text('${x['note']}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.logout});
  final Future<void> Function() logout;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      ListTile(
        title: const Text('Rang mavzusi'),
        trailing: IconButton(
          onPressed: () => ref.read(themeProvider.notifier).toggle(),
          icon: const Icon(Icons.contrast),
        ),
      ),
      DropdownButton<String>(
        value: ref.watch(languageProvider),
        items: const [
          DropdownMenuItem(value: 'uz', child: Text('O‘zbekcha')),
          DropdownMenuItem(value: 'kaa', child: Text('Qaraqalpaqsha')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (v) {
          if (v != null) ref.read(languageProvider.notifier).set(v);
        },
      ),
      DataView(
        path: '/v1/research-consent',
        builder: (d) => SwitchListTile(
          title: const Text(
            'Ilmiy tadqiqot uchun anonimlashtirilgan natijalar',
          ),
          subtitle: const Text(
            'Ixtiyoriy. Istalgan vaqtda bekor qilish mumkin.',
          ),
          value: d['enabled'] as bool,
          onChanged: (v) => act(context, () async {
            await ref
                .read(apiProvider)
                .dio
                .put<void>('/v1/research-consent', data: {'enabled': v});
            ref.invalidate(dataProvider('/v1/research-consent'));
          }),
        ),
      ),
      ListTile(
        title: const Text('Ma’lumotlarimni ko‘rish / nusxalash'),
        onTap: () => act(context, () async {
          final r = await ref.read(apiProvider).dio.get<dynamic>('/v1/export');
          if (context.mounted) await showData(context, 'Eksport', r.data);
        }),
      ),
      ListTile(
        title: const Text('Parolni almashtirish'),
        onTap: () async {
          final d = await editForm(context, 'Yangi parol (kamida 12 belgi)', {
            'old_password': '',
            'new_password': '',
          });
          if (d != null && context.mounted) {
            await act(context, () async {
              await ref
                  .read(apiProvider)
                  .dio
                  .post<void>('/v1/auth/password', data: d);
              await logout();
            });
          }
        },
      ),
      ListTile(
        title: const Text('Hisobni va shaxsiy ma’lumotlarni o‘chirish'),
        onTap: () async {
          if (await confirm(
                context,
                'Hisobni o‘chirish? Qaytarib bo‘lmaydi.',
              ) &&
              context.mounted) {
            await act(context, () async {
              await ref.read(apiProvider).dio.post<void>('/v1/delete-account');
              await logout();
            });
          }
        },
      ),
      FilledButton.tonal(
        onPressed: () => act(context, logout),
        child: const Text('Chiqish'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Baxshi AI 0.2.0 • Akustik baholar tajriba bosqichida. Ustoz bahosini almashtirmaydi.',
      ),
    ],
  );
}
