import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';

class YouPage extends StatelessWidget {
  const YouPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          // Optimized Background: PNG cached via RepaintBoundary
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
              // Header with Scaling Settings Icon
              SliverAppBar(
                expandedHeight: 160.0,
                toolbarHeight: 80.0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final double topPadding = MediaQuery.of(context).padding.top;
                    final double expandedHeight = 160.0;
                    final double toolbarHeight = 80.0;
                    
                    final double expandRatio =
                        ((constraints.maxHeight - toolbarHeight) / (expandedHeight - toolbarHeight)).clamp(0.0, 1.0);
                    
                    final double collapsedCenterY = topPadding + (toolbarHeight - topPadding) / 2;
                    final double expandedCenterY = expandedHeight - 16 - 18.2; 
                    final double currentCenterY = collapsedCenterY + (expandRatio * (expandedCenterY - collapsedCenterY));
                    final double currentTop = currentCenterY - 24;

                    return Stack(
                      children: [
                        ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: FlexibleSpaceBar(
                              titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              centerTitle: false,
                              title: Text(
                                'Profile',
                                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: brandNavy,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: currentTop + (10 * (1.0 - expandRatio)),
                          right: 24,
                          child: Transform.scale(
                            scale: 1.0 + (expandRatio * 0.3),
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.settings_outlined, color: brandNavy),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Profile Section - Isolated for performance
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 32.0),
                  child: RepaintBoundary(
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 50),
                          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                userProvider.displayName,
                                style: const TextStyle(
                                  color: brandNavy,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "${userProvider.playerTitle} Level ${userProvider.level}  |  ${userProvider.currentLevelXp}/${userProvider.nextLevelXp} XP",
                                    style: TextStyle(
                                      color: brandNavy.withOpacity(0.6),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.info_outline, size: 16, color: brandNavy.withOpacity(0.6)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: userProvider.currentLevelXp / userProvider.nextLevelXp,
                                  minHeight: 8,
                                  backgroundColor: brandNavy.withOpacity(0.1),
                                  valueColor: const AlwaysStoppedAnimation<Color>(brandGreen),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildProfileStatPod(
                                      context,
                                      label: "${userProvider.streak} day streak",
                                      icon: Icons.local_fire_department_rounded,
                                      onTap: () {},
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildProfileStatPod(
                                      context,
                                      label: "${userProvider.points} points",
                                      icon: Icons.stars_rounded,
                                      onTap: () {},
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: CircleAvatar(
                                  radius: 46,
                                  backgroundColor: brandGreen,
                                  backgroundImage: userProvider.photoUrl != null
                                      ? NetworkImage(userProvider.photoUrl!)
                                      : null,
                                  child: userProvider.photoUrl == null
                                      ? const Icon(Icons.person_rounded, size: 48, color: brandNavy)
                                      : null,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: brandNavy,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.eco,
                                  size: 18,
                                  color: brandGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 66,
                          right: 16,
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              backgroundColor: brandNavy.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: const Text(
                              "Edit",
                              style: TextStyle(color: brandNavy, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: 24.0, right: 24.0, top: 0.0, bottom: 16.0),
                  child: Text(
                    "Your Stats",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: brandNavy,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),

              // Account Grid - Optimized by removing repeating blurs
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
                    _LiquidGlassTile(title: "Achievements", value: "12", icon: Icons.emoji_events_outlined, accentColor: brandGreen),
                    _LiquidGlassTile(title: "My Posts", value: "24", icon: Icons.grid_view_rounded, accentColor: Color(0xFF90CAF9)),
                    _LiquidGlassTile(title: "Certificates", value: "3", icon: Icons.verified_user_outlined, accentColor: Color(0xFFFFCC80)),
                    _LiquidGlassTile(title: "Rewards", value: "2,450", icon: Icons.wallet_giftcard_outlined, accentColor: Color(0xFFCE93D8)),
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

  Widget _buildProfileStatPod(BuildContext context, {required String label, required IconData icon, required VoidCallback onTap}) {
    const Color brandNavy = Color(0xFF2D3E50);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: brandNavy.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: brandNavy),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: brandNavy,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // Performance Optimization: Replaced BackdropFilter with high-fidelity smoked gradient.
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
                    Icon(icon, size: 20, color: brandNavy.withOpacity(0.8)),
                    const Icon(Icons.north_east, size: 14, color: Color(0x662D3E50)),
                  ],
                ),
                const Spacer(),
                Expanded(
                  child: FittedBox(
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
      ),
    );
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
