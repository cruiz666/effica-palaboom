import 'dart:async';
import 'package:flutter/material.dart';
import '../content/models/exercise.dart';
import '../gamification/gamification_repository.dart';
import '../lesson/exercise_widget_factory.dart';
import 'srs_repository.dart';

class ReviewSessionScreen extends StatefulWidget {
  const ReviewSessionScreen({
    super.key,
    required this.exercises,
    required this.srsRepository,
    required this.gamificationRepository,
  });

  final List<Exercise> exercises;
  final SrsRepository srsRepository;
  final GamificationRepository gamificationRepository;

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  int _currentIndex = 0;
  bool _completed = false;
  String? _errorMessage;
  int _incorrectCount = 0;
  bool _limitReached = false;
  static const _errorLimit = 3;

  Future<void> _onAnswered(bool correct) async {
    if (correct) {
      unawaited(widget.gamificationRepository.awardXp(10).catchError((_) {}));
    } else {
      _incorrectCount++;
    }
    final exercise = widget.exercises[_currentIndex];
    try {
      for (final learningItemId in exercise.learningItemIds) {
        await widget.srsRepository.submitReviewResult(
          learningItemId: learningItemId,
          correct: correct,
        );
      }
      if (!mounted) return;

      if (_incorrectCount >= _errorLimit) {
        setState(() {
          _errorMessage = null;
          _limitReached = true;
        });
        return;
      }

      final isLast = _currentIndex == widget.exercises.length - 1;
      if (isLast) {
        unawaited(widget.gamificationRepository.recordActivity().catchError((_) {}));
      }
      setState(() {
        _errorMessage = null;
        if (isLast) {
          _completed = true;
        } else {
          _currentIndex++;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo guardar tu repaso. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: const Center(child: Text('No hay nada para repasar ahora mismo.')),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (_limitReached) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Alcanzaste el límite de errores para esta sesión.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver al curso'),
              ),
            ],
          ),
        ),
      );
    }

    if (_completed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repaso')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('¡Repaso completado!'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver al curso'),
              ),
            ],
          ),
        ),
      );
    }

    final exercise = widget.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('Repaso')),
      body: buildExerciseWidget(exercise: exercise, onAnswered: _onAnswered),
    );
  }
}
