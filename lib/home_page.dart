import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class _CustomHomeBody extends StatelessWidget {
  const _CustomHomeBody();

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background.png',
            fit: BoxFit.cover,
          ),
        ),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 180.0 + topPadding,
              backgroundColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 24, right: 24, bottom: 16, top: topPadding),
                centerTitle: false,
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Welcome Back,',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 16,
                          ),
                    ),
                    Text(
                      userProvider.isLoading ? '...' : userProvider.displayName,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 28,
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.only(right: 24.0, top: topPadding + 16),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage: userProvider.photoUrl != null
                        ? NetworkImage(userProvider.photoUrl!)
                        : null,
                    child: userProvider.photoUrl == null
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.primary)
                        : null,
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16.0,
                  crossAxisSpacing: 16.0,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildListDelegate([
                  _buildTile(
                    context,
                    title: "Carbon Footprint",
                    subtitle: "12.5 kg CO2e",
                    color: Colors.lightBlue.shade100,
                    icon: Icons.eco,
                  ),
                  _buildTile(
                    context,
                    title: "Daily Tasks",
                    subtitle: "4 remaining",
                    color: Colors.green.shade100,
                    icon: Icons.task_alt,
                  ),
                  _buildTile(
                    context,
                    title: "Energy Usage",
                    subtitle: "High",
                    color: Colors.orange.shade100,
                    icon: Icons.bolt,
                  ),
                  _buildTile(
                    context,
                    title: "Community",
                    subtitle: "Active events",
                    color: Colors.purple.shade100,
                    icon: Icons.groups,
                  ),
                ]),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 140),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context,
      {required String title, required String subtitle, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.5),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              const _CustomHomeBody(), // Index 0: Home
              const LibraryPage(), // Index 1: Library
              const ImpactPage(), // Index 2: Impact (Calculator Icon)
              const YouPage(), // Index 3: You (Person Icon)
            ],
          ),
          CustomNavBar(
            selectedIndex: _selectedIndex,
            onItemTapped: _onItemTapped,
          ),
        ],
      ),
    );
  }
}
