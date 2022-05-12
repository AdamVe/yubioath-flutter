import 'package:flutter/material.dart';

import 'progress_circle.dart';

class CircleTimer extends StatefulWidget {
  final int validFromMs;
  final int validToMs;
  const CircleTimer(this.validFromMs, this.validToMs, {super.key});

  @override
  State<StatefulWidget> createState() => _CircleTimerState();
}

class _CircleTimerState extends State<CircleTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animator;
  late Tween<double> _tween;
  late Animation<double> _progress;

  void _animate() {
    var period = widget.validToMs - widget.validFromMs;
    var now = DateTime.now().millisecondsSinceEpoch;
    _tween.begin = 1.0 - (now - widget.validFromMs) / period;
    var timeLeft = widget.validToMs - now;
    if (timeLeft > 0) {
      _animator.duration = Duration(milliseconds: timeLeft.toInt());
    } else {
      _animator.duration = Duration.zero;
    }
    _animator.forward();
  }

  @override
  void initState() {
    super.initState();

    _animator = AnimationController(vsync: this);
    _tween = Tween(end: 0);
    _progress = _tween.animate(_animator)
      ..addListener(() {
        setState(() {});
      });

    _animate();
  }

  @override
  void didUpdateWidget(CircleTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animator.reset();
    _animate();
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProgressCircle(Colors.grey, _progress.value);
  }
}
