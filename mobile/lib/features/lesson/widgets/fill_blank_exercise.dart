import 'package:flutter/material.dart';
import '../../content/models/exercise.dart';

class FillBlankExercise extends StatefulWidget {
  const FillBlankExercise({
    super.key,
    required this.exercise,
    required this.onAnswered,
  });

  final Exercise exercise;
  final void Function(bool correct) onAnswered;

  @override
  State<FillBlankExercise> createState() => _FillBlankExerciseState();
}

class _FillBlankExerciseState extends State<FillBlankExercise> {
  String? _selected;

  void _select(String option) {
    if (_selected != null) return;
    final correct = option == widget.exercise.correctAnswer;
    setState(() => _selected = option);
    widget.onAnswered(correct);
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.exercise.content['prompt'] as String;
    final options = List<String>.from(widget.exercise.content['options'] as List);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt),
        for (final option in options)
          ElevatedButton(
            onPressed: () => _select(option),
            child: Text(option),
          ),
        if (_selected != null)
          Text(_selected == widget.exercise.correctAnswer ? '¡Correcto!' : 'Incorrecto'),
      ],
    );
  }
}
