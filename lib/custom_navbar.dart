import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CustomNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const CustomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  State<CustomNavBar> createState() => _CustomNavBarState();
}

class _CustomNavBarState extends State<CustomNavBar> {
  bool _isHolding = false;
  bool _isPanning = false;
  double _touchX = 0.0;

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const double horizontalPadding = 12.0;
    const double spacerWidth = 65.0;
    const double barHeight = 80.0;
    const double bubbleInset = 8.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double fullWidth = constraints.maxWidth;
            final double availableWidth = fullWidth - (horizontalPadding * 2) - spacerWidth;
            final double itemWidth = availableWidth / 4;
            final double baseBubbleWidth = itemWidth + (horizontalPadding * 2);

            double getIconCenterX(int index) {
              double x = horizontalPadding + (itemWidth / 2);
              if (index <= 1) {
                x += index * itemWidth;
              } else {
                x += (index * itemWidth) + spacerWidth;
              }
              return x;
            }

            double getBubbleLeft(int index) {
              if (index == 0) return 0;
              if (index == 1) return itemWidth;
              if (index == 2) return (2 * itemWidth) + spacerWidth;
              if (index == 3) return (3 * itemWidth) + spacerWidth;
              return 0;
            }

            int findNearestIndex(double x) {
              int nearestIndex = 0;
              double minDist = double.infinity;
              for (int i = 0; i < 4; i++) {
                double dist = (getIconCenterX(i) - x).abs();
                if (dist < minDist) {
                  minDist = dist;
                  nearestIndex = i;
                }
              }
              return nearestIndex;
            }

            double targetBubbleLeft = getBubbleLeft(widget.selectedIndex);

            double currentBubbleLeft;
            if (_isHolding) {
              currentBubbleLeft = (_touchX - baseBubbleWidth / 2).clamp(0.0, fullWidth - baseBubbleWidth);
            } else {
              currentBubbleLeft = targetBubbleLeft;
            }

            double focalX = _isHolding ? _touchX : getIconCenterX(widget.selectedIndex);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                setState(() {
                  _isHolding = true;
                  _isPanning = false; // Initial tap: trigger smooth animation
                  _touchX = details.localPosition.dx.clamp(0.0, fullWidth);
                });
              },
              onTapUp: (details) {
                widget.onItemTapped(findNearestIndex(details.localPosition.dx));
                setState(() {
                  _isHolding = false;
                  _isPanning = false;
                });
              },
              onTapCancel: () {
                setState(() {
                  _isHolding = false;
                  _isPanning = false;
                });
              },
              onPanStart: (details) {
                setState(() {
                  _isHolding = true;
                  _isPanning = true; // Start panning: switch to fast/instant duration
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  _touchX = details.localPosition.dx.clamp(0.0, fullWidth);
                });
              },
              onPanEnd: (details) {
                widget.onItemTapped(findNearestIndex(_touchX));
                setState(() {
                  _isHolding = false;
                  _isPanning = false;
                });
              },
              onPanCancel: () => setState(() {
                _isHolding = false;
                _isPanning = false;
              }),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    painter: NavbarShadowPainter(clipper: NotchClipper()),
                    size: Size(fullWidth, barHeight),
                  ),
                  ClipPath(
                    clipper: NotchClipper(),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: CustomPaint(
                        painter: NavbarBackgroundPainter(
                          color: const Color(0xFFC8FFB0).withValues(alpha: 0.75),
                          borderColor: Colors.white.withValues(alpha: 0.4),
                          clipper: NotchClipper(),
                        ),
                        child: SizedBox(
                          width: fullWidth,
                          height: barHeight,
                          child: Stack(
                            children: [
                              AnimatedPositioned(
                                // Use 400ms for the jump on tap down, but 60ms for fluid following during drag
                                duration: _isPanning
                                    ? const Duration(milliseconds: 60)
                                    : const Duration(milliseconds: 400),
                                curve: Curves.fastOutSlowIn,
                                left: currentBubbleLeft + bubbleInset,
                                top: bubbleInset - 1,
                                bottom: bubbleInset + 1,
                                width: baseBubbleWidth - (bubbleInset * 2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        brandNavy.withValues(alpha: 0.32),
                                        brandNavy.withValues(alpha: 0.18),
                                        brandNavy.withValues(alpha: 0.1),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      width: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
                                child: Row(
                                  children: [
                                    _buildNavIcon(FontAwesomeIcons.house, 0, focalX, itemWidth),
                                    _buildNavIcon(FontAwesomeIcons.bookBookmark, 1, focalX, itemWidth),
                                    const SizedBox(width: spacerWidth),
                                    _buildNavIcon(FontAwesomeIcons.calculator, 2, focalX, itemWidth),
                                    _buildNavIcon(FontAwesomeIcons.wallet, 3, focalX, itemWidth),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -42,
                    child: _buildScanButton(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index, double focalX, double itemWidth) {
    const Color brandNavy = Color(0xFF2D3E50);
    final bool isActive = widget.selectedIndex == index;

    double iconCenterX = 12.0 + (index <= 1 ? index * itemWidth : (index * itemWidth) + 65.0) + (itemWidth / 2);
    double distance = (iconCenterX - focalX).abs();

    double scale = 1.0;
    if (_isHolding) {
      scale = (1.45 - (distance / 110)).clamp(1.0, 1.45);
    } else if (isActive) {
      scale = 1.15;
    }

    return Expanded(
      child: Center(
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 200),
          child: TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 300),
            tween: ColorTween(
              begin: brandNavy.withValues(alpha: 0.5),
              end: isActive ? brandNavy : brandNavy.withValues(alpha: 0.5),
            ),
            builder: (context, color, child) {
              return FaIcon(
                icon,
                size: 24,
                color: color,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF2D3E50),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D3E50).withValues(alpha: 0.35),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Center(
        child: FaIcon(
          FontAwesomeIcons.expand,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class NotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final double radius = 40.0;
    final double centerX = size.width / 2;

    final double notchRadius = 43.0;
    final double halfWidthAtTop = 42.6;

    final path = Path();
    path.moveTo(radius, 0);

    path.lineTo(centerX - halfWidthAtTop - 12, 0);
    path.quadraticBezierTo(centerX - halfWidthAtTop - 4, 0, centerX - halfWidthAtTop, 4);

    path.arcToPoint(
      Offset(centerX + halfWidthAtTop, 4),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.quadraticBezierTo(centerX + halfWidthAtTop + 4, 0, centerX + halfWidthAtTop + 12, 0);

    path.lineTo(size.width - radius, 0);
    path.arcToPoint(Offset(size.width, radius), radius: Radius.circular(radius));
    path.lineTo(size.width, size.height - radius);
    path.arcToPoint(Offset(size.width - radius, size.height), radius: Radius.circular(radius));
    path.lineTo(radius, size.height);
    path.arcToPoint(Offset(0, size.height - radius), radius: Radius.circular(radius));
    path.lineTo(0, radius);
    path.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

class NavbarBackgroundPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final CustomClipper<Path> clipper;

  NavbarBackgroundPainter({
    required this.color,
    required this.borderColor,
    required this.clipper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = clipper.getClip(size);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class NavbarShadowPainter extends CustomPainter {
  final CustomClipper<Path> clipper;

  NavbarShadowPainter({required this.clipper});

  @override
  void paint(Canvas canvas, Size size) {
    final path = clipper.getClip(size);
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 25.0, false);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
