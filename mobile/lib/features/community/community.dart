import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../shared/api_ui.dart';

final avatarProvider = FutureProvider.autoDispose<Uint8List?>((ref) async {
  ref.watch(accountProvider);
  try {
    final r = await ref
        .watch(apiProvider)
        .dio
        .get<List<int>>(
          '/v1/profile/avatar',
          options: Options(responseType: ResponseType.bytes),
        );
    return Uint8List.fromList(r.data!);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

class ProfileCard extends ConsumerStatefulWidget {
  const ProfileCard({super.key});
  @override
  ConsumerState<ProfileCard> createState() => _Profile();
}

class _Profile extends ConsumerState<ProfileCard> {
  bool busy = false;
  Future<void> chooseAvatar() async {
    if (busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (files.isEmpty || files.first.path == null || !mounted) return;
    setState(() => busy = true);
    await act(context, () async {
      final file = File(files.first.path!);
      if (await file.length() > 3 * 1024 * 1024) {
        throw StateError('Rasm 3 MB dan kichik bo‘lsin.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await ref
          .read(apiProvider)
          .dio
          .put<void>(
            '/v1/profile/avatar',
            data: bytes,
            options: Options(contentType: 'application/octet-stream'),
          );
      if (!mounted) return;
      ref.invalidate(avatarProvider);
      ref.invalidate(dataProvider('/v1/profile'));
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final picture = ref.watch(avatarProvider).value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 42,
              backgroundImage: picture == null ? null : MemoryImage(picture),
              child: picture == null
                  ? const Icon(Icons.person, size: 44)
                  : null,
            ),
            if (busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : chooseAvatar,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Rasm qo‘yish'),
                ),
                if (picture != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => act(context, () async {
                            await ref
                                .read(apiProvider)
                                .dio
                                .delete<void>('/v1/profile/avatar');
                            ref.invalidate(avatarProvider);
                          }),
                    child: const Text('Rasmni olib tashlash'),
                  ),
              ],
            ),
            const Text('JPG, PNG yoki WEBP • 3 MB gacha'),
            DataView(
              path: '/v1/profile',
              builder: (d) => Column(
                children: [
                  Text(
                    '${d['name']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${d['bio'] ?? ''}'),
                  TextButton(
                    onPressed: () async {
                      final values = await editForm(context, 'Profil', {
                        'name': d['name'],
                        'bio': d['bio'] ?? '',
                        'school': d['school'] ?? '',
                      });
                      if (values != null && context.mounted) {
                        await act(context, () async {
                          await ref
                              .read(apiProvider)
                              .dio
                              .patch<void>('/v1/profile', data: values);
                          ref.invalidate(dataProvider('/v1/profile'));
                          ref.invalidate(dataProvider('/v1/dashboard'));
                        });
                      }
                    },
                    child: const Text('Profilni tahrirlash'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _Messages();
}

class _Messages extends ConsumerState<MessagesScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Ustoz bilan muloqot',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Administratorga yoki guruhingizga biriktirilgan ustozga savol yozing. Javoblar shu bo‘limda ko‘rinadi.',
      ),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Kontakt ismini qidirish',
          prefixIcon: Icon(Icons.search),
        ),
        onSubmitted: (v) => setState(() => query = v),
      ),
      DataView(
        path: '/v1/contacts?q=${Uri.encodeQueryComponent(query)}',
        builder: (d) => Column(
          children: [
            if ((d as List).isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Kontakt topilmadi. Ustozni administrator guruhingizga biriktiradi.',
                ),
              ),
            for (final person in d)
              Card(
                child: ListTile(
                  leading: Icon(
                    person['role'] == 'super_admin'
                        ? Icons.support_agent
                        : Icons.school,
                  ),
                  title: Text('${person['name']}'),
                  subtitle: Text('${person['role']}'),
                  trailing: const Icon(Icons.chat_bubble_outline),
                  onTap: () => act(context, () async {
                    final r = await ref
                        .read(apiProvider)
                        .dio
                        .post<Map<String, dynamic>>(
                          '/v1/conversations',
                          data: {'recipient_id': person['id']},
                        );
                    if (context.mounted) {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            id: r.data!['id'] as String,
                            name: person['name'] as String,
                          ),
                        ),
                      );
                    }
                    if (mounted) {
                      ref.invalidate(dataProvider('/v1/conversations'));
                    }
                  }),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Text('Suhbatlarim', style: Theme.of(context).textTheme.titleLarge),
      DataView(
        path: '/v1/conversations',
        builder: (d) => Column(
          children: [
            for (final t in d as List)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text('${t['peer_name']}'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      id: t['id'] as String,
                      name: t['peer_name'] as String,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id, required this.name});
  final String id, name;
  @override
  ConsumerState<ChatScreen> createState() => _Chat();
}

class _Chat extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final input = TextEditingController();
  final scroll = ScrollController();
  final cancel = CancelToken();
  final List<Map<String, dynamic>> messages = [];
  Timer? timer;
  bool loading = false, sending = false, foreground = true;
  String? error, pendingId, pendingText;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (foreground) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    cancel.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (loading || !mounted) return;
    loading = true;
    final api = ref.read(apiProvider).dio;
    try {
      final after = messages.isEmpty ? 0 : messages.last['id'] as int;
      final r = await api.get<List<dynamic>>(
        '/v1/conversations/${widget.id}/messages',
        queryParameters: {'after': after},
        cancelToken: cancel,
      );
      if (!mounted) return;
      setState(() {
        error = null;
        for (final x in r.data!) {
          messages.add(Map<String, dynamic>.from(x as Map));
        }
      });
      if (r.data!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      loading = false;
    }
  }

  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    final id = pendingText == body && pendingId != null
        ? pendingId!
        : const Uuid().v4();
    pendingId = id;
    pendingText = body;
    setState(() => sending = true);
    final ok = await act(context, () async {
      await ref
          .read(apiProvider)
          .dio
          .post<void>(
            '/v1/conversations/${widget.id}/messages',
            data: {'body': body, 'client_id': id},
            cancelToken: cancel,
            options: Options(headers: {'Idempotency-Key': id}),
          );
    });
    if (!mounted) return;
    if (ok) {
      input.clear();
      pendingId = null;
      pendingText = null;
      await refresh();
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final own = ref.watch(accountProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null)
              MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(
                    onPressed: refresh,
                    child: const Text('Yangilash'),
                  ),
                ],
              ),
            Expanded(
              child: messages.isEmpty
                  ? const Center(
                      child: Text('Savolingizni yozib suhbatni boshlang.'),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (c, i) {
                        final m = messages[i];
                        final mine = m['sender'] == own;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Card(
                              color: mine
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText('${m['body']}'),
                                    const SizedBox(height: 6),
                                    Text(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        (m['created'] as int) * 1000,
                                      ).toLocal().toString().substring(0, 16),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      enabled: !sending,
                      maxLength: 4000,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Savolingiz yoki javobingiz…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: sending ? null : send,
                    icon: sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
