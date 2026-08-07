import 'package:flutter/material.dart';

import '../theme/hh_theme.dart';

/// Логотип-марка hh.ru: красный скруглённый квадрат с белыми буквами «hh».
class HhLogoMark extends StatelessWidget {
  const HhLogoMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HhColors.red,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'hh',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          height: 1,
        ),
      ),
    );
  }
}

/// Полный ворд-марк продукта: «hh·copilot».
class HhWordmark extends StatelessWidget {
  const HhWordmark({super.key, this.markSize = 30});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HhLogoMark(size: markSize),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: const [
              TextSpan(
                text: 'hh',
                style: TextStyle(
                  color: HhColors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: '·copilot',
                style: TextStyle(
                  color: HhColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            style: TextStyle(fontSize: markSize * 0.6, letterSpacing: -0.3),
          ),
        ),
      ],
    );
  }
}
