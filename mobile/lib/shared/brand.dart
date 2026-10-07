import 'package:flutter/material.dart';

/// Baxshi AI mark: a stylized long-necked lute and two sound arcs.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Baxshi AI logosi',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Mark()),
    ),
  );
}

class _Mark extends CustomPainter {
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 100, size.height / 100);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xff101f30),
    );
    final gold = Paint()..color = const Color(0xffe4b567);
    final body = Path()
      ..moveTo(40, 49)
      ..cubicTo(14, 63, 19, 85, 39, 86)
      ..cubicTo(60, 87, 69, 66, 49, 50)
      ..close();
    c.drawPath(body, gold);
    c.drawLine(
      const Offset(43, 61),
      const Offset(62, 19),
      Paint()
        ..color = const Color(0xffe4b567)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(const Offset(63, 15), 6, gold);
    c.drawLine(
      const Offset(34, 75),
      const Offset(61, 20),
      Paint()
        ..color = const Color(0xff101f30)
        ..strokeWidth = 1.5,
    );
    c.drawLine(
      const Offset(39, 76),
      const Offset(64, 20),
      Paint()
        ..color = const Color(0xff101f30)
        ..strokeWidth = 1.5,
    );
    c.drawCircle(
      const Offset(41, 66),
      4,
      Paint()..color = const Color(0xff101f30),
    );
    final sound = Paint()
      ..color = const Color(0xff63d5c3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(71, 44)
        ..quadraticBezierTo(80, 54, 73, 64),
      sound,
    );
    c.drawPath(
      Path()
        ..moveTo(78, 36)
        ..quadraticBezierTo(92, 54, 82, 73),
      sound,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _Mark oldDelegate) => false;
}
