import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class LogoLoader extends StatelessWidget {
  final double width;
  final double height;
  final String logoPath;

  const LogoLoader({
    super.key,
    this.width = 60,
    this.height = 60,
    this.logoPath = 'assets/spinner/spinner_logo.png',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(logoPath, fit: BoxFit.contain)
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fadeIn(duration: 1000.ms, curve: Curves.easeInOut),
        ),
      ),
    );
  }
}


