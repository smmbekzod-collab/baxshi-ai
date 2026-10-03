import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_session.dart';

class LocalPlayer extends StatefulWidget {
  const LocalPlayer({
    super.key,
    required this.path,
    required this.playLabel,
    required this.errorLabel,
  });
  final String path, playLabel, errorLabel;
  @override
  State<LocalPlayer> createState() => _LocalPlayer();
}

class _LocalPlayer extends State<LocalPlayer> {
  final player = AudioPlayer();
  bool ready = false, failed = false, loop = false;
  double speed = 1;
  @override
  void initState() {
    super.initState();
    AudioSession.players.add(player);
    unawaited(load());
  }

  Future<void> load() async {
    try {
      await player.setFilePath(widget.path);
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    AudioSession.players.remove(player);
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> toggle() async {
    try {
      if (player.playing) {
        await player.pause();
        return;
      }
      await AudioSession.stopAll(except: player);
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) return Text(widget.errorLabel);
    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (c, s) {
            final total = player.duration?.inMilliseconds.toDouble() ?? 0;
            return Slider(
              value: (s.data?.inMilliseconds.toDouble() ?? 0).clamp(
                0,
                total > 0 ? total : 1,
              ),
              max: total > 0 ? total : 1,
              label:
                  '${((s.data?.inSeconds ?? 0) / 60).toStringAsFixed(1)} min',
              onChanged: ready
                  ? (v) => player.seek(Duration(milliseconds: v.toInt()))
                  : null,
            );
          },
        ),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (c, s) => FilledButton.tonalIcon(
                onPressed: ready ? toggle : null,
                icon: Icon(
                  s.data?.playing == true ? Icons.pause : Icons.play_arrow,
                ),
                label: Text(widget.playLabel),
              ),
            ),
            DropdownButton<double>(
              value: speed,
              items: [.5, .75, 1.0, 1.25, 1.5]
                  .map((v) => DropdownMenuItem(value: v, child: Text('${v}x')))
                  .toList(),
              onChanged: ready
                  ? (v) async {
                      if (v == null) return;
                      await player.setSpeed(v);
                      if (mounted) setState(() => speed = v);
                    }
                  : null,
            ),
            IconButton(
              tooltip: 'Takrorlash',
              isSelected: loop,
              icon: const Icon(Icons.repeat),
              onPressed: ready
                  ? () async {
                      await player.setLoopMode(
                        loop ? LoopMode.off : LoopMode.one,
                      );
                      if (mounted) setState(() => loop = !loop);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
