import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'core/providers.dart';
import 'shared/api_ui.dart';

const schools = ['xorazm', 'qashqadaryo', 'surxondaryo', 'qoraqalpogiston'];

class AdminHome extends ConsumerStatefulWidget {
  const AdminHome({super.key, required this.logout});
  final Future<void> Function() logout;
  @override
  ConsumerState<AdminHome> createState() => _Admin();
}

class _Admin extends ConsumerState<AdminHome> {
  int selected = 0;
  bool busy = false;
  double progress = 0;
  static const sections = [
    'stats',
    'users',
    'references',
    'contents',
    'jobs',
    'reports',
    'groups',
    'audit',
    'policy',
  ];
  static const labels = [
    'Umumiy holat',
    'Foydalanuvchilar',
    'Etalon yozuvlar',
    'Materiallar',
    'Tahlil navbati',
    'Hisobotlar',
    'Guruhlar',
    'Audit jurnali',
    'Server sozlamalari',
  ];
  String get section => sections[selected];
  String get path => section == 'policy' ? '/v1/config' : '/v1/admin/$section';
  Future<void> write(
    String endpoint,
    String method,
    Map<String, dynamic>? data,
  ) async {
    if (data == null) return;
    await act(context, () async {
      await ref
          .read(apiProvider)
          .dio
          .request<void>(
            endpoint,
            data: data,
            options: Options(method: method),
          );
      ref.invalidate(dataProvider(path));
    });
  }

  Future<void> add() async {
    if (section == 'users') {
      final d = await editForm(context, 'Hisob ochish', {
        'username': '',
        'name': '',
        'password': '',
      });
      await write(path, 'POST', d);
    } else if (section == 'contents') {
      final d = await editForm(
        context,
        'Material',
        {
          'kind': 'lesson',
          'title': '',
          'body': '',
          'url': null,
          'published': false,
        },
        choices: {
          'kind': ['lesson', 'news', 'event', 'master', 'gallery', 'exercise'],
        },
      );
      await write(path, 'POST', d);
    } else if (section == 'groups') {
      final d = await editForm(
        context,
        'Guruh (ustoz ID — foydalanuvchilar ro‘yxatida)',
        {'title': '', 'teacher_id': ''},
      );
      await write(path, 'POST', d);
    } else if (section == 'references') {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'm4a'],
      );
      final file = picked.isEmpty ? null : picked.first;
      if (file?.path == null || !mounted) return;
      setState(() {
        busy = true;
        progress = 0;
      });
      await act(context, () async {
        final session = await ref.read(tokensProvider).read();
        if (session == null) throw StateError('auth');
        final asset = await ref
            .read(uploaderProvider)
            .upload(
              subject: session.subject,
              recordingId: const Uuid().v4(),
              path: file!.path!,
              mime: file.extension?.toLowerCase() == 'wav'
                  ? 'audio/wav'
                  : 'audio/mp4',
              cancel: CancelToken(),
              progress: (v) {
                if (mounted) setState(() => progress = v);
              },
            );
        if (!mounted) return;
        final d = await editForm(
          context,
          'Litsenziyalangan etalon',
          {
            'title': '',
            'master': '',
            'school': 'xorazm',
            'asset_id': asset,
            'license_note': '',
            'license_until':
                DateTime.now()
                    .add(const Duration(days: 365))
                    .millisecondsSinceEpoch ~/
                1000,
            'active': false,
          },
          choices: {'school': schools},
        );
        await write(path, 'POST', d);
      });
      if (mounted) setState(() => busy = false);
    }
  }

  Widget item(Map<String, dynamic> x) {
    final id = x['id'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${x['title'] ?? x['name'] ?? x['action'] ?? x['status'] ?? id}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText('ID: $id'),
            if (section == 'users')
              Text(
                '${x['username']} • ${x['role']} • ${x['active'] == true ? 'faol' : 'bloklangan'}',
              ),
            if (section == 'references')
              Text(
                '${x['school']} • ${x['master']} • ${x['active'] == true ? 'ochiq' : 'yopiq'}',
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => showData(context, 'Tafsilotlar', x),
                  child: const Text('Ko‘rish'),
                ),
                if (section == 'users' && x['role'] != 'super_admin') ...[
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(
                        context,
                        'Huquq va holat',
                        {'active': x['active'], 'role': x['role']},
                        choices: {
                          'role': ['user', 'teacher'],
                        },
                      );
                      await write('$path/$id', 'PATCH', d);
                    },
                    child: const Text('Tahrirlash'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Barcha sessiyalarni yopish?',
                      )) {
                        await write('$path/$id/revoke', 'POST', {});
                      }
                    },
                    child: const Text('Sessiyalarni yopish'),
                  ),
                ],
                if (section == 'contents')
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(
                        context,
                        'Materialni tahrirlash',
                        {
                          for (final k in [
                            'kind',
                            'title',
                            'body',
                            'url',
                            'published',
                          ])
                            k: x[k],
                        },
                        choices: {
                          'kind': [
                            'lesson',
                            'news',
                            'event',
                            'master',
                            'gallery',
                            'exercise',
                          ],
                        },
                      );
                      await write('$path/$id', 'PUT', d);
                    },
                    child: const Text('Tahrirlash'),
                  ),
                if (section == 'references')
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(
                        context,
                        'Etalonni tahrirlash',
                        {
                          for (final k in [
                            'title',
                            'master',
                            'school',
                            'asset_id',
                            'license_note',
                            'license_until',
                            'active',
                          ])
                            k: x[k],
                        },
                        choices: {'school': schools},
                      );
                      await write('$path/$id', 'PUT', d);
                    },
                    child: const Text('Tahrirlash'),
                  ),
                if (section == 'jobs')
                  TextButton(
                    onPressed: () async {
                      final action =
                          ['failed', 'cancelled'].contains(x['status'])
                          ? 'retry'
                          : 'cancel';
                      if (await confirm(context, 'Tahlil: $action?')) {
                        await write('$path/$id/$action', 'POST', {});
                      }
                    },
                    child: const Text('Qayta urinish / to‘xtatish'),
                  ),
                if (section == 'reports')
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(context, 'Ustoz bahosi', {
                        'score': 70.0,
                        'note': '',
                      });
                      await write('/v1/reports/$id/reviews', 'POST', d);
                    },
                    child: const Text('Ekspert bahosi'),
                  ),
                if (section == 'groups') ...[
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(context, 'A’zo qo‘shish', {
                        'user_id': '',
                      });
                      await write('$path/$id/members', 'POST', d);
                    },
                    child: const Text('A’zo qo‘shish'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final d = await editForm(context, 'Topshiriq', {
                        'title': '',
                        'instructions': '',
                        'due':
                            DateTime.now()
                                .add(const Duration(days: 7))
                                .millisecondsSinceEpoch ~/
                            1000,
                      });
                      await write('$path/$id/assignments', 'POST', d);
                    },
                    child: const Text('Topshiriq'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Baxshi Admin • ${labels[selected]}'),
      actions: [
        IconButton(
          onPressed: () => ref.invalidate(dataProvider(path)),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: () => act(context, widget.logout),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    drawer: NavigationDrawer(
      selectedIndex: selected,
      onDestinationSelected: busy
          ? null
          : (i) {
              Navigator.pop(context);
              setState(() => selected = i);
            },
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('SUPER ADMIN • OTP'),
        ),
        for (var i = 0; i < labels.length; i++)
          NavigationDrawerDestination(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: Text(labels[i]),
          ),
      ],
    ),
    floatingActionButton:
        ['users', 'references', 'contents', 'groups'].contains(section)
        ? FloatingActionButton(
            onPressed: busy ? null : add,
            child: const Icon(Icons.add),
          )
        : null,
    body: Column(
      children: [
        if (busy) LinearProgressIndicator(value: progress),
        Expanded(
          child: DataView(
            path: path,
            builder: (d) {
              if (section == 'policy') {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    for (final e in (d as Map).entries)
                      ListTile(
                        title: Text('${e.key}'),
                        subtitle: Text('${e.value}'),
                      ),
                    FilledButton(
                      onPressed: () async {
                        final values = await editForm(
                          context,
                          'Server siyosati',
                          Map<String, dynamic>.from(d),
                        );
                        await write('/v1/admin/policy', 'PUT', values);
                      },
                      child: const Text('Tahrirlash'),
                    ),
                    TextButton(
                      onPressed: () => act(context, () async {
                        final r = await ref
                            .read(apiProvider)
                            .dio
                            .get<String>('/v1/admin/research.csv');
                        if (context.mounted) {
                          await showData(
                            context,
                            'Rozilik berilgan natijalar CSV',
                            r.data,
                          );
                        }
                      }),
                      child: const Text('Tadqiqot eksporti'),
                    ),
                  ],
                );
              }
              if (section == 'stats') {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    for (final e in (d as Map).entries)
                      Card(
                        child: ListTile(
                          title: Text('${e.key}'),
                          subtitle: Text(
                            '${e.value}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  if ((d as List).isEmpty)
                    const Text('Hozircha ma’lumot yo‘q.'),
                  for (final x in d) item(Map<String, dynamic>.from(x as Map)),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
