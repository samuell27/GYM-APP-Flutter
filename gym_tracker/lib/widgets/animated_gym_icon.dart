import 'dart:math' as math;
import 'package:flutter/material.dart';

enum GymAnimationType {
  flame,     // Oscila e cresce rápido como fogo vivo
  heartbeat, // Dá duas batidas rápidas e descansa (igual a um coração)
  sparkle,   // Gira levemente e brilha (ideal para os botões de IA)
  float,     // Flutua suavemente para cima e para baixo (ideal para Troféu/Raio)
}

class AnimatedGymIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final GymAnimationType type;

  const AnimatedGymIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 22.0,
    this.type = GymAnimationType.flame,
  });

  @override
  State<AnimatedGymIcon> createState() => _AnimatedGymIconState();
}

class _AnimatedGymIconState extends State<AnimatedGymIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _getDuration(),
    )..repeat(reverse: widget.type != GymAnimationType.heartbeat);
  }

  Duration _getDuration() {
    switch (widget.type) {
      case GymAnimationType.flame:
        return const Duration(milliseconds: 900);
      case GymAnimationType.heartbeat:
        return const Duration(milliseconds: 1400);
      case GymAnimationType.sparkle:
        return const Duration(milliseconds: 1600);
      case GymAnimationType.float:
        return const Duration(milliseconds: 1800);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;
        double scale = 1.0;
        double angle = 0.0;
        double dy = 0.0;

        switch (widget.type) {
          case GymAnimationType.flame:
            scale = 1.0 + (0.20 * math.sin(t * math.pi));
            angle = 0.08 * math.sin(t * math.pi * 2);
            break;

          case GymAnimationType.heartbeat:
            // Simula o duplo batimento cardíaco (lub-dub)
            if (t < 0.15) {
              scale = 1.0 + (t / 0.15) * 0.28;
            } else if (t < 0.30) {
              scale = 1.28 - ((t - 0.15) / 0.15) * 0.18;
            } else if (t < 0.45) {
              scale = 1.10 + ((t - 0.30) / 0.15) * 0.22;
            } else if (t < 0.65) {
              scale = 1.32 - ((t - 0.45) / 0.20) * 0.32;
            } else {
              scale = 1.0;
            }
            break;

          case GymAnimationType.sparkle:
            scale = 0.90 + (0.25 * math.sin(t * math.pi));
            angle = 0.22 * math.sin(t * math.pi);
            break;

          case GymAnimationType.float:
            dy = -3.5 * math.sin(t * math.pi);
            scale = 1.0 + (0.08 * math.sin(t * math.pi));
            break;
        }

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
      child: Icon(
        widget.icon,
        color: widget.color,
        size: widget.size,
      ),
    );
  }
}