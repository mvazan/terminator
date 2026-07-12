/// Buttons that disable themselves and show a small spinner while their async
/// [onPressed] runs — the tap feedback for slow connections, and a guard
/// against double-fires. Visual style copied from the detail screen's sync
/// button.
library;

import 'package:flutter/material.dart';

class BusyIconButton extends StatefulWidget {
  const BusyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
  });

  final Widget icon;
  final Future<void> Function() onPressed;
  final String? tooltip;
  final double? iconSize;

  @override
  State<BusyIconButton> createState() => _BusyIconButtonState();
}

class _BusyIconButtonState extends State<BusyIconButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      iconSize: widget.iconSize,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.icon,
      onPressed: _busy ? null : _run,
    );
  }
}

class BusyFilledButton extends StatefulWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final Widget label;
  final Future<void> Function() onPressed;

  @override
  State<BusyFilledButton> createState() => _BusyFilledButtonState();
}

class _BusyFilledButtonState extends State<BusyFilledButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy ? null : _run,
      child: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.label,
    );
  }
}

class BusyTextButton extends StatefulWidget {
  const BusyTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final Widget label;
  final Future<void> Function() onPressed;

  @override
  State<BusyTextButton> createState() => _BusyTextButtonState();
}

class _BusyTextButtonState extends State<BusyTextButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _busy ? null : _run,
      child: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.label,
    );
  }
}

class BusyActionChip extends StatefulWidget {
  const BusyActionChip({
    super.key,
    required this.avatar,
    required this.label,
    required this.onPressed,
  });

  final Widget avatar;
  final Widget label;
  final Future<void> Function() onPressed;

  @override
  State<BusyActionChip> createState() => _BusyActionChipState();
}

class _BusyActionChipState extends State<BusyActionChip> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.avatar,
      label: widget.label,
      onPressed: _busy ? null : _run,
    );
  }
}
