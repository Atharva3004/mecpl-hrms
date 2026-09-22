import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CustomLoader extends StatelessWidget {
  final double size;
  final Color? color;

  const CustomLoader({super.key, this.size = 24.0, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.8),
                    width: 1.5,
                  ),
                ),
                child: Image.asset(
                  'assets/spinner/spinner_logo.png',
                  width: size,
                  height: size,
                  color: color,
                  fit: BoxFit.contain,
                ),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fadeIn(duration: 1000.ms, curve: Curves.easeInOut),
    );
  }
}


