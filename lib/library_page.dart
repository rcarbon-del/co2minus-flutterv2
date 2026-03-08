import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _selectedTaskIndex;
  final ScrollController _taskScrollController = ScrollController();
  final List<GlobalKey> _taskKeys = List.generate(5, (index) => GlobalKey());

  final List<Map<String, dynamic>> _dailyTasks = [
    {
      "title": "Carbon Neutrality",
      "desc": "Complete the first 3 chapters to unlock your next achievement.",
      "progress": 0.45,
      "icon": FontAwesomeIcons.leaf,
    },
    {
      "title": "Zero Waste",
      "desc": "Learn how to reduce your daily trash by 50% using simple steps.",
      "progress": 0.20,
      "icon": FontAwesomeIcons.recycle,
    },
    {
      "title": "Energy Audit",
      "desc": "Check your home appliances and optimize power consumption.",
      "progress": 0.75,
      "icon": FontAwesomeIcons.bolt,
    },
    {
      "title": "Plastic Free",
      "desc": "Identify 5 single-use plastics in your kitchen to replace.",
      "progress": 0.10,
      "icon": FontAwesomeIcons.bottleWater,
    },
    {
      "title": "Water Saving",
      "desc": "Implement a rainwater harvesting technique for your garden.",
      "progress": 0.60,
      "icon": FontAwesomeIcons.droplet,
    },
  ];

  void _handleTaskTap(int index) {
    setState(() {
      if (_selectedTaskIndex == index) {
        _selectedTaskIndex = null;
      } else {
        _selectedTaskIndex = index;
      }
    });

    if (_selectedTaskIndex != null) {
      // Small delay to allow layout to start updating before triggering scroll
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _centerSelectedIndex(index);
      });
    }
  }

  void _centerSelectedIndex(int index) {
    if (!_taskScrollController.hasClients) return;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double expandedWidth = screenWidth - 48;
    
    // UI sizing constants to match current UI
    final double gridTileWidth = (screenWidth - (24 * 2) - 16) / 2;
    const double horizontalMargin = 16.0;

    // Calculate position based on current state (only the selected item is expanded)
    double targetOffset = 0;
    for (int i = 0; i < index; i++) {
      // Add width of previous items. If an item is selected, it's expanded.
      targetOffset += (_selectedTaskIndex == i ? expandedWidth : gridTileWidth) + horizontalMargin;
    }
    
    // Centering: targetOffset is the start of the item's margin in the list area.
    // We add the list's leading padding (24.0) and the item's own left margin (8.0)
    // to find its absolute start position in the scrollable content.
    double currentItemWidth = _selectedTaskIndex == index ? expandedWidth : gridTileWidth;
    targetOffset = targetOffset + 24.0 + 8.0 + (currentItemWidth / 2) - (screenWidth / 2);

    _taskScrollController.animateTo(
      targetOffset.clamp(0.0, _taskScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);
    final double screenWidth = MediaQuery.of(context).size.width;
    
    // Width calculation to match the 2-column grid in Books section
    final double gridTileWidth = (screenWidth - (24 * 2) - 16) / 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          // Optimized Background
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

              // Section 1: Daily Tasks Hub
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                        child: Text(
                          "Daily Tasks",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: brandNavy,
                            fontSize: 20,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 280, 
                        child: ListView.builder(
                          controller: _taskScrollController,
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _dailyTasks.length,
                          itemBuilder: (context, index) => _buildSelectionTile(index, brandNavy, brandGreen, gridTileWidth),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 16.0),
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

              // Section 2: Smokey Glass Tiles (Books)
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
        ],
      ),
    );
  }

  Widget _buildSelectionTile(int index, Color brandNavy, Color brandGreen, double gridTileWidth) {
    final task = _dailyTasks[index];
    final isSelected = _selectedTaskIndex == index;
    final double screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      key: _taskKeys[index],
      onTap: () => _handleTaskTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
        width: isSelected ? screenWidth - 48 : gridTileWidth, 
        height: isSelected ? 220 : gridTileWidth,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        padding: const EdgeInsets.all(24),
        // Bidirectional expansion from middle
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
          // Gradient logic to ensure smooth transition from Smokey Glass to White
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
              color: brandNavy.withValues(alpha: isSelected ? 0.15 : 0.08),
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
                  Icon(Icons.star_rounded, color: brandGreen, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task['title'],
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
                              task['desc'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: brandNavy.withValues(alpha: 0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: task['progress'],
                                      minHeight: 6,
                                      backgroundColor: brandNavy.withValues(alpha: 0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(brandGreen),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "${(task['progress'] * 100).toInt()}%",
                                  style: TextStyle(
                                    color: brandNavy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? brandGreen : brandNavy.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      isSelected ? "ACTIVE FOCUS" : "FOCUS",
                      style: TextStyle(
                        color: brandNavy,
                        fontSize: 10,
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
    const Color brandNavy = Color(0xFF2D3E50);

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
