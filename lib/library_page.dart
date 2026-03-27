import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ScrollController _taskScrollController = ScrollController();

  void _handleTaskTap(UserProvider provider, Map<String, dynamic> task, int index) {
    if (provider.selectedTask == task) {
      provider.selectTask(null);
    } else {
      provider.selectTask(task);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _centerSelectedIndex(index);
      });
    }
  }

  void _centerSelectedIndex(int index) {
    if (!_taskScrollController.hasClients) return;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double expandedWidth = screenWidth - 48;
    final double gridTileWidth = (screenWidth - (24 * 2) - 16) / 2;
    const double horizontalMargin = 16.0;

    double targetOffset = 0;
    final provider = Provider.of<UserProvider>(context, listen: false);
    
    for (int i = 0; i < index; i++) {
      if (i >= provider.dailyTasks.length) break;
      bool isItemIExpanded = provider.selectedTask == provider.dailyTasks[i];
      targetOffset += (isItemIExpanded ? expandedWidth : gridTileWidth) + horizontalMargin;
    }
    
    if (index < provider.dailyTasks.length) {
      bool isCurrentExpanded = provider.selectedTask == provider.dailyTasks[index];
      double currentItemWidth = isCurrentExpanded ? expandedWidth : gridTileWidth;
      targetOffset = targetOffset + 24.0 + 8.0 + (currentItemWidth / 2) - (screenWidth / 2);

      _taskScrollController.animateTo(
        targetOffset.clamp(0.0, _taskScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color brandNavy = const Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);
    final double screenWidth = MediaQuery.of(context).size.width;
    final double gridTileWidth = (screenWidth - (24 * 2) - 16) / 2;
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.asset(
                'assets/images/background.png',
                fit: BoxFit.cover,
              ),
            ),
          ),

          RefreshIndicator(
            onRefresh: () => userProvider.fetchDailyChallenges(),
            color: brandGreen,
            backgroundColor: brandNavy,
            displacement: 100,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
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
                          'Library',
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

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Daily Tasks",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: brandNavy,
                                  fontSize: 20,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (userProvider.isLoadingChallenges)
                                const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: brandGreen),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 280, 
                          child: userProvider.isLoadingChallenges
                              ? const Center(
                                  child: CircularProgressIndicator(color: brandGreen),
                                )
                              : userProvider.dailyTasks.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.auto_awesome_outlined, color: brandNavy.withValues(alpha: 0.2), size: 40),
                                          const SizedBox(height: 12),
                                          Text(
                                            "No tasks available today.",
                                            style: TextStyle(color: brandNavy.withValues(alpha: 0.4), fontWeight: FontWeight.w600),
                                          ),
                                          TextButton(
                                            onPressed: () => userProvider.fetchDailyChallenges(),
                                            child: Text("Tap to Refresh", style: TextStyle(color: brandNavy, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _taskScrollController,
                                      clipBehavior: Clip.none,
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: userProvider.dailyTasks.length,
                                      itemBuilder: (context, index) {
                                        final task = userProvider.dailyTasks[index];
                                        return _buildSelectionTile(context, task, index, brandNavy, brandGreen, gridTileWidth, userProvider);
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 16.0),
                    child: Text(
                      "Your Books",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: brandNavy,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16.0,
                      crossAxisSpacing: 16.0,
                      childAspectRatio: 0.85,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final books = [
                          {"title": "Eco Living", "author": "J. Doe", "color": brandGreen},
                          {"title": "Zero Waste", "author": "S. Smith", "color": const Color(0xFF90CAF9)},
                          {"title": "Solar Future", "author": "R. Green", "color": const Color(0xFFFFCC80)},
                          {"title": "Ocean Health", "author": "M. Blue", "color": const Color(0xFFCE93D8)},
                        ];
                        final book = books[index % books.length];
                        return _SmokeyGlassTile(
                          title: book['title'] as String,
                          subtitle: book['author'] as String,
                          accentColor: book['color'] as Color,
                          index: index,
                        );
                      },
                      childCount: 6,
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 160),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionTile(BuildContext context, Map<String, dynamic> task, int index, Color brandNavy, Color brandGreen, double gridTileWidth, UserProvider provider) {
    final isSelected = provider.selectedTask == task;
    final double screenWidth = MediaQuery.of(context).size.width;
    final isStepTask = task['hasStepCount'] == true;
    final progress = isStepTask 
        ? (provider.currentSteps / provider.stepGoal).clamp(0.0, 1.0)
        : (task['progress'] ?? 0.0);

    return GestureDetector(
      onTap: () => _handleTaskTap(provider, task, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
        width: isSelected ? screenWidth - 48 : gridTileWidth, 
        height: isSelected ? 220 : gridTileWidth,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    Colors.white.withValues(alpha: 0.95),
                    Colors.white.withValues(alpha: 0.95),
                    Colors.white.withValues(alpha: 0.95),
                  ]
                : [
                    brandNavy.withValues(alpha: 0.25),
                    brandNavy.withValues(alpha: 0.05),
                    brandGreen.withValues(alpha: 0.1),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: brandNavy.withValues(alpha: 0.15),
              blurRadius: isSelected ? 25 : 20,
              offset: Offset(0, isSelected ? 10 : 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FaIcon(
                  task['icon'],
                  size: isSelected ? 24 : 20,
                  color: isSelected ? brandNavy : brandNavy.withValues(alpha: 0.8),
                ),
                if (isSelected)
                  Icon(isStepTask ? Icons.directions_walk_rounded : Icons.star_rounded, color: brandGreen, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task['title'] ?? "",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: brandNavy,
                    fontWeight: FontWeight.w900,
                    fontSize: isSelected ? 24 : 22,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutQuart,
                  child: isSelected
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            const SizedBox(height: 16),
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
                                      ? "${provider.currentSteps}"
                                      : "${(progress * 100).toInt()}%",
                                  style: TextStyle(
                                    color: brandNavy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? brandGreen : brandNavy.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      isSelected ? "ACTIVE FOCUS" : "FOCUS",
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
          ],
        ),
      ),
    );
  }
}

class _SmokeyGlassTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accentColor;
  final int index;

  const _SmokeyGlassTile({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final Color brandNavy = const Color(0xFF2D3E50);

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: 600 + (index * 100)),
        curve: Curves.easeOutBack,
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Container(
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: FaIcon(
                    FontAwesomeIcons.bookOpen,
                    size: 16,
                    color: accentColor.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: brandNavy,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0x802D3E50),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
