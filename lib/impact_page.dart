import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ImpactPage extends StatefulWidget {
  const ImpactPage({super.key});

  @override
  State<ImpactPage> createState() => _ImpactPageState();
}

class _ImpactPageState extends State<ImpactPage> {
  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      floatingActionButton: const _ExpandableFabMenu(
        brandNavy: brandNavy,
        brandGreen: brandGreen,
      ),
      body: Stack(
        children: [
          // Optimized PNG Background
          const Positioned.fill(
            child: RepaintBoundary(
              child: _BackgroundLayer(),
            ),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Frosted Glass Header
              SliverAppBar(
                expandedHeight: 160.0,
                toolbarHeight: 80.0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      centerTitle: false,
                      title: Text(
                        'Impact',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: brandNavy,
                            ),
                      ),
                    ),
                  ),
                ),
              ),

              // Section 1: Summary Tiles
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16.0,
                    crossAxisSpacing: 16.0,
                    childAspectRatio: 0.9,
                  ),
                  delegate: SliverChildListDelegate([
                    const RepaintBoundary(child: _SummaryTile()),
                    const RepaintBoundary(child: _GoalTile()),
                  ]),
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 24.0, right: 24.0, top: 8.0, bottom: 16.0),
                  child: Text(
                    "Today's Breakdown",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: brandNavy,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),

              // Section 2: Tiled Breakdown - Optimized for 120fps
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16.0,
                    crossAxisSpacing: 16.0,
                    childAspectRatio: 1.1,
                  ),
                  delegate: SliverChildListDelegate([
                    const _LiquidGlassTile(title: "Transport", value: "3.2 kg", icon: FontAwesomeIcons.carSide, accentColor: brandGreen),
                    const _LiquidGlassTile(title: "Energy", value: "1.8 kg", icon: FontAwesomeIcons.bolt, accentColor: Color(0xFFFFF59D)),
                    const _LiquidGlassTile(title: "Food", value: "2.5 kg", icon: FontAwesomeIcons.utensils, accentColor: Color(0xFFFFCC80)),
                    const _LiquidGlassTile(title: "Shopping", value: "0.9 kg", icon: FontAwesomeIcons.bagShopping, accentColor: Color(0xFF90CAF9)),
                  ]),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 160),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpandableFabMenu extends StatefulWidget {
  final Color brandNavy;
  final Color brandGreen;

  const _ExpandableFabMenu({required this.brandNavy, required this.brandGreen});

  @override
  State<_ExpandableFabMenu> createState() => _ExpandableFabMenuState();
}

class _ExpandableFabMenuState extends State<_ExpandableFabMenu> with SingleTickerProviderStateMixin {
  bool _isMenuOpen = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 90.0, right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildFabMenuItem(icon: Icons.add_rounded, label: "Add", index: 3),
          const SizedBox(height: 16),
          _buildFabMenuItem(icon: FontAwesomeIcons.expand, label: "Scan", index: 2),
          const SizedBox(height: 16),
          _buildFabMenuItem(icon: Icons.map_outlined, label: "Locate", index: 1),
          const SizedBox(height: 16),
          _buildFabMenuItem(icon: FontAwesomeIcons.bullseye, label: "Set Goals", index: 0),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _toggleMenu,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: _isMenuOpen ? widget.brandNavy : widget.brandGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.brandNavy.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: RotationTransition(
                  turns: Tween(begin: 0.0, end: 0.125).animate(_expandAnimation),
                  child: Icon(
                    Icons.add_rounded,
                    size: 32,
                    color: _isMenuOpen ? widget.brandGreen : widget.brandNavy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFabMenuItem({required IconData icon, required String label, required int index}) {
    final staggerAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Interval(0.1 * index, 0.6 + (0.1 * index), curve: Curves.easeOutBack),
    );

    return FadeTransition(
      opacity: staggerAnimation,
      child: ScaleTransition(
        scale: staggerAnimation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(staggerAnimation),
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: widget.brandNavy,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: widget.brandNavy.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(icon, size: 18, color: widget.brandGreen.withOpacity(0.9)),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile();

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S IMPACT",
            style: TextStyle(
              color: Color(0x802D3E50),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(
                "0.2 kg",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: brandNavy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xB32D3E50),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              children: [
                const TextSpan(text: "CO"),
                WidgetSpan(
                  child: Transform.translate(
                    offset: const Offset(0, 4),
                    child: const Text(
                      '2',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xB32D3E50),
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: " saved"),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "↓ 12%",
            style: TextStyle(
              color: Colors.green.shade600,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile();

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const double progress = 0.57;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "MONTHLY GOAL",
            style: TextStyle(
              color: Color(0x802D3E50),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double size = math.min(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(size, size),
                        painter: SpeedometerPainter(
                          progress: progress,
                          color: brandNavy,
                          backgroundColor: brandNavy.withOpacity(0.1),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              "85.3",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 32,
                                color: brandNavy,
                              ),
                            ),
                          ),
                          const Text(
                            "kg of 150",
                            style: TextStyle(
                              color: Color(0xB32D3E50),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidGlassTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _LiquidGlassTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: brandNavy.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: brandNavy.withOpacity(0.25),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                brandNavy.withOpacity(0.35),
                brandNavy.withOpacity(0.1),
                accentColor.withOpacity(0.15),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FaIcon(icon, size: 20, color: brandNavy.withOpacity(0.8)),
                  const Icon(Icons.north_east, size: 14, color: Color(0x662D3E50)),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: brandNavy,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0x802D3E50),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpeedometerPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  SpeedometerPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const startAngle = 3 * math.pi / 4; 
    const sweepAngle = 3 * math.pi / 2; 

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/background.png',
      fit: BoxFit.cover,
    );
  }
}
