import 'dart:async';
import 'package:flutter/material.dart';
import '../data/dictionary_repository.dart';

/// The timer updates the label only. A retry always needs a user action.
class RetryButton extends StatefulWidget {
  const RetryButton({
    super.key,
    required this.error,
    required this.onRetry,
    this.label = 'Повторить',
  });
  final Object? error;
  final VoidCallback? onRetry;
  final String label;
  @override
  State<RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<RetryButton> {
  Timer? timer;
  DateTime? get deadline => widget.error is DictionaryException
      ? (widget.error as DictionaryException).retryAt
      : null;
  int get remaining => deadline == null
      ? 0
      : (deadline!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 2147483647);
  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(covariant RetryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (remaining > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (remaining == 0) t.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: remaining > 0 ? null : widget.onRetry,
    child: Text(remaining > 0 ? 'Повторить через $remaining с' : widget.label),
  );
}
