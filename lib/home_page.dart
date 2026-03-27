import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'user_provider.dart';
import 'custom_navbar.dart';
import 'impact_page.dart';
import 'you_page.dart';
import 'library_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: userProvider.currentTabIndex,
            children: [
              const _CustomHomeBody(), // Index 0: Home
              const LibraryPage(), // Index 1: Library
              const ImpactPage(), // Index 2: Impact
              const YouPage(), // Index 3: You
            ],
          ),
          CustomNavBar(
            selectedIndex: userProvider.currentTabIndex,
            onItemTapped: (index) => userProvider.setTabIndex(index),
          ),
        ],
      ),
    );
  }
}

class _CustomHomeBody extends StatelessWidget {
  const _CustomHomeBody();

  @override
  Widget build(BuildContext context) {
    final Color brandNavy = const Color(0xFF2D3E50);
    final Color brandGreen = const Color(0xFFC8FFB0);
    final userProvider = Provider.of<UserProvider>(context);

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Frosted Glass Header
            SliverAppBar(
              expandedHeight: 180.0,
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
                      userProvider.displayName,
                      style: TextStyle(
                        color: brandNavy,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    background: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 60),
                            child: Text(
                              'Welcome Back,',
                              style: TextStyle(
                                color: brandNavy.withValues(alpha: 0.6),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  userProvider.playerTitle.toUpperCase(),
                                  style: TextStyle(
                                    color: brandNavy.withValues(alpha: 0.5),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "LVL ${userProvider.level}",
                                      style: TextStyle(
                                        color: brandNavy,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 80,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: LinearProgressIndicator(
                                          value: userProvider.isLoading ? 0 : (userProvider.currentLevelXp / userProvider.nextLevelXp),
                                          minHeight: 4,
                                          backgroundColor: brandNavy.withValues(alpha: 0.1),
                                          valueColor: AlwaysStoppedAnimation<Color>(brandGreen),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 24.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 25,
                        backgroundColor: brandGreen,
                        backgroundImage: userProvider.photoUrl != null
                            ? NetworkImage(userProvider.photoUrl!)
                            : null,
                        child: userProvider.photoUrl == null
                            ? Icon(Icons.person_rounded, color: brandNavy, size: 24)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Section 1: Active Focus Task (Responsive with Library & Steps)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: _buildDailyTaskCard(context, userProvider, brandNavy, brandGreen),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0, bottom: 16.0),
                child: Text(
                  "Explore Hub",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: brandNavy,
                    fontSize: 20,
                  ),
                ),
              ),
            ),

            // Tiled Grid
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16.0,
                  crossAxisSpacing: 16.0,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildListDelegate([
                  _buildGlassTile(
                    title: "Impact",
                    value: "${userProvider.dailyImpact.toStringAsFixed(1)} kg",
                    icon: FontAwesomeIcons.leaf,
                    accentColor: brandGreen,
                  ),
                  _buildGlassTile(
                    title: "Tasks",
                    value: "${userProvider.dailyTasks.length} Left",
                    icon: FontAwesomeIcons.listCheck,
                    accentColor: const Color(0xFF90CAF9),
                  ),
                  _buildGlassTile(
                    title: "Energy",
                    value: "${userProvider.energyImpact.toStringAsFixed(1)} kg",
                    icon: FontAwesomeIcons.boltLightning,
                    accentColor: const Color(0xFFFFCC80),
                  ),
                  _buildGlassTile(
                    title: "Social",
                    value: "Active",
                    icon: FontAwesomeIcons.users,
                    accentColor: const Color(0xFFCE93D8),
                  ),
                ]),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 160),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyTaskCard(BuildContext context, UserProvider userProvider, Color brandNavy, Color brandGreen) {
    final task = userProvider.selectedTask;

    if (task == null) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
        ),
        child: CustomPaint(
          painter: _DashedRectPainter(color: brandNavy.withValues(alpha: 0.2)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_task_rounded, color: brandNavy.withValues(alpha: 0.2), size: 32),
                const SizedBox(height: 8),
                Text(
                  "SELECT YOUR TASK",
                  style: TextStyle(
                    color: brandNavy.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isStepTask = task['hasStepCount'] == true;
    final progress = isStepTask 
        ? (userProvider.currentSteps / userProvider.stepGoal).clamp(0.0, 1.0)
        : (task['progress'] ?? 0.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: brandNavy.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FaIcon(
                task['icon'],
                size: 24,
                color: brandNavy,
              ),
              if (isStepTask)
                GestureDetector(
                  onTap: () => userProvider.requestHealthPermission(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: brandGreen.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.sync_rounded, color: brandNavy, size: 16),
                  ),
                )
              else
                Icon(Icons.star_rounded, color: brandGreen, size: 24),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            task['title'],
            style: TextStyle(
              color: brandNavy,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task['description'] ?? "",
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: brandNavy.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: brandNavy.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(brandGreen),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isStepTask 
                    ? "${userProvider.currentSteps}" 
                    : "${(progress * 100).toInt()}%",
                style: TextStyle(
                  color: brandNavy,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              if (isStepTask)
                Text(
                  " / ${userProvider.stepGoal}",
                  style: TextStyle(
                    color: brandNavy.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: brandGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                "ACTIVE FOCUS",
                style: TextStyle(
                  color: brandNavy,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTile({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    final Color brandNavy = const Color(0xFF2D3E50);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: brandNavy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: brandNavy.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              brandNavy.withValues(alpha: 0.35),
              brandNavy.withValues(alpha: 0.1),
              accentColor.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, size: 20, color: brandNavy.withValues(alpha: 0.8)),
            const Spacer(),
            FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: brandNavy,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: const Color(0x802D3E50),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  _DashedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const double dashWidth = 10.0;
    const double dashSpace = 8.0;
    final RRect rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(32),
    );

    final Path path = Path()..addRRect(rect);
    final Path dashPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
