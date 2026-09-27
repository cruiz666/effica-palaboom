import 'package:flutter/material.dart';
import '../../content/models/exercise.dart';

class WordOrderExercise extends StatefulWidget {
  const WordOrderExercise({
    super.key,
    required this.exercise,
    required this.onAnswered,
  });

  final Exercise exercise;
  final void Function(bool correct) onAnswered;

  @override
  State<WordOrderExercise> createState() => _WordOrderExerciseState();
}

class _WordOrderExerciseState extends State<WordOrderExercise> {
  late final List<String> _available = List<String>.from(widget.exercise.content['words'] as List);
  final List<String> _selected = [];
  bool _answered = false;

  void _select(int index) {
    if (_answered) return;
    setState(() {
      _selected.add(_available.removeAt(index));
    });
  }

  void _unselect(int index) {
    if (_answered) return;
    setState(() {
      _available.add(_selected.removeAt(index));
    });
  }

  void _confirm() {
    final correct = _selected.join(' ') == widget.exercise.correctAnswer;
    setState(() => _answered = true);
    widget.onAnswered(correct);
  }

  @override
  Widget build(BuildContext context) {
    final allPlaced = _available.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _selected.length; i++)
              ElevatedButton(
                onPressed: () => _unselect(i),
                child: Text(_selected[i]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < _available.length; i++)
              OutlinedButton(
                onPressed: () => _select(i),
                child: Text(_available[i]),
              ),
          ],
        ),
        if (!_answered) ...[
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: allPlaced ? _confirm : null,
            child: const Text('Comprobar'),
          ),
        ],
        if (_answered)
          Text(_selected.join(' ') == widget.exercise.correctAnswer ? '¡Correcto!' : 'Incorrecto'),
      ],
    );
  }
}
