import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/word_fit_text.dart';

/// The nickname of a robot in bold between two bolts, as the official client draws it.
class RobotNickname extends StatelessWidget {
  final String nickname;

  const RobotNickname({super.key, required this.nickname});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(Icons.bolt, color: colors.bitcoinOrange)),
        // A nickname is one word: too wide for the line, as at twice the text size on a phone of 320 points, it is shrunk to it, never broken nor elided (follow-ups of #270, #273 and #283).
        Flexible(
          child: WordFitText(
            nickname,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ExcludeSemantics(child: Icon(Icons.bolt, color: colors.bitcoinOrange)),
      ],
    );
  }
}
