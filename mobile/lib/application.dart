import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'core/providers.dart';
import 'core/network/api_client.dart';
import 'core/storage/local_store.dart';
import 'l10n/strings.dart';
import 'student.dart';
import 'features/recording/presentation/recording_controller.dart';
import 'shared/api_ui.dart';
import 'shared/audio_session.dart';
import 'admin.dart';

Future<void> startApp({required bool admin}) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await LocalStore.open();
    runApp(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: BaxshiApp(admin: admin),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Xavfsiz xotirani ochib bo‘lmadi. Ilovani qayta ishga tushiring.',
            ),
          ),
        ),
      ),
    );
  }
}

class BaxshiApp extends ConsumerWidget {
  const BaxshiApp({super.key, required this.admin});
  final bool admin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    ThemeData theme(Brightness b) => ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffb48a46),
        brightness: b,
      ),
      scaffoldBackgroundColor: b == Brightness.dark
          ? const Color(0xff101923)
          : const Color(0xfffaf7f0),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: admin ? 'Baxshi AI Admin' : 'Baxshi AI',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ref.watch(themeProvider),
      locale: Locale(lang == 'kaa' ? 'en' : lang),
      supportedLocales: const [Locale('uz'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: SessionGate(admin: admin),
    );
  }
}

class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key, required this.admin});
  final bool admin;
  @override
  ConsumerState<SessionGate> createState() => _Gate();
}

class _Gate extends ConsumerState<SessionGate> {
  Map<String, dynamic>? user;
  bool loading = true, busy = false;
  String? error;
  final name = TextEditingController(),
      pass = TextEditingController(),
      otp = TextEditingController();
  @override
  void initState() {
    super.initState();
    restore();
  }

  @override
  void dispose() {
    name.dispose();
    pass.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> restore() async {
    try {
      if (demoMode && !widget.admin) {
        user = {'id': 'demo', 'name': 'Demo'};
      } else if (await ref.read(tokensProvider).read() != null) {
        final r = await ref
            .read(apiProvider)
            .dio
            .get<Map<String, dynamic>>('/v1/auth/me');
        if (widget.admin && r.data!['role'] != 'super_admin') {
          await ref.read(tokensProvider).clear();
        } else {
          user = r.data;
          await ref
              .read(localStoreProvider)
              .write('${user!['id']}:profile', user!);
        }
      }
    } on DioException catch (e) {
      if (!widget.admin && e.response == null) {
        final token = await ref.read(tokensProvider).read();
        if (token != null) {
          user = ref.read(localStoreProvider).read('${token.subject}:profile');
        }
      }
      error =
          'Sessiyani tekshirib bo‘lmadi. Internetni tekshiring va qayta kiring.';
    } catch (_) {
      error = 'Xavfsiz sessiyani tiklab bo‘lmadi. Qayta kiring.';
    }
    if (user != null) {
      ref.read(accountProvider.notifier).set(user!['id'] as String);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .dio
          .post<Map<String, dynamic>>(
            '/v1/auth/login',
            data: {
              'username': name.text.trim(),
              'password': pass.text,
              'otp': otp.text.trim(),
            },
          );
      final j = r.data!;
      if (widget.admin && j['role'] != 'super_admin') throw StateError('role');
      await ref
          .read(tokensProvider)
          .write(
            Tokens(
              j['access_token'] as String,
              j['refresh_token'] as String,
              j['subject'] as String,
            ),
          );
      await ref.read(localStoreProvider).write('${j['subject']}:profile', {
        'id': j['subject'],
        'name': j['name'],
        'role': j['role'],
      });
      ref.read(accountProvider.notifier).set(j['subject'] as String);
      pass.clear();
      otp.clear();
      if (mounted) {
        setState(
          () =>
              user = {'id': j['subject'], 'name': j['name'], 'role': j['role']},
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Kirish amalga oshmadi. Login, parol, OTP va server manzilini tekshiring.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    final id = user?['id'] as String?;
    try {
      if (!demoMode) {
        await ref.read(apiProvider).dio.post<void>('/v1/auth/logout');
      }
    } catch (_) {}
    await AudioSession.stopAll();
    await ref.read(recordingProvider.notifier).stop();
    ref.invalidate(recordingProvider);
    ref.invalidate(recorderProvider);
    ref.invalidate(repositoryProvider);
    ref.invalidate(reportProvider);
    ref.invalidate(selectedReportProvider);
    ref.invalidate(dataProvider);
    await ref.read(tokensProvider).clear();
    ref.read(accountProvider.notifier).set('demo');
    if (mounted) {
      setState(
        () => user = null,
      ); // Dispose players/recorder before removing files.
    }
    if (id != null) {
      await ref.read(localStoreProvider).clearAccount(id);
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
      final support = await getApplicationSupportDirectory();
      final cache = Directory('${support.path}/$id');
      if (await cache.exists()) await cache.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user != null) {
      return KeyedSubtree(
        key: ValueKey(user!['id']),
        child: widget.admin
            ? AdminHome(logout: logout)
            : StudentHome(logout: logout),
      );
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.graphic_eq, size: 72),
                const SizedBox(height: 20),
                Text(
                  widget.admin ? 'Baxshi AI • Super Admin' : 'Baxshi AI',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.admin
                      ? 'Boshqaruv uchun parol va autentifikator kodi kerak.'
                      : 'Doston. Ovoz. Ustoz bilan rivojlanish.',
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: name,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Login'),
                ),
                TextField(
                  controller: pass,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Parol'),
                ),
                if (widget.admin)
                  TextField(
                    controller: otp,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6 xonali OTP',
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(error!),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: Text(busy ? 'Kutilmoqda…' : 'Kirish'),
                ),
                if (!widget.admin)
                  const Text(
                    'Hisobni administrator ochadi. Audio faqat roziligingiz bilan serverga yuboriladi.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
