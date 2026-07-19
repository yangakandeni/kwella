import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Profile Screen
// Avatar, stats, emergency contacts, in-app chat stub.
// ─────────────────────────────────────────────────────────────────────────────

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final List<Map<String, String>> _emergencyContacts = [
    {'name': 'Mama Dlamini', 'phone': '+27 82 345 6789'},
    {'name': 'Sipho', 'phone': '+27 71 234 5678'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Outfit',
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                color: Color(0xFFDFFF00), size: 22),
            onPressed: () {},
          ),
        ],
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Avatar + stats ────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFDFFF00), width: 3),
                        color: const Color(0xFF1E1E1E),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 48,
                          color: Color(0xFFA0A0A0),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDFFF00),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 14, color: Color(0xFF1A1A00)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Yanga Kandeni',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '+27 81 234 5678',
                  style: TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 14,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // ── Stats row ─────────────────────────────────────────────────
          Row(
            children: [
              _StatChip(label: 'Rating', value: '4.9 ★'),
              const SizedBox(width: 12),
              _StatChip(label: 'Trips', value: '142'),
              const SizedBox(width: 12),
              _StatChip(label: 'Member', value: '2023'),
            ],
          ),
          const SizedBox(height: 28),
          // ── Emergency contacts ────────────────────────────────────────
          _SectionHeader(
            title: 'Emergency Contacts',
            trailing: TextButton.icon(
              onPressed: _addContact,
              icon: const Icon(Icons.add_circle_rounded,
                  color: Color(0xFFDFFF00), size: 18),
              label: const Text(
                'Add',
                style: TextStyle(
                  color: Color(0xFFDFFF00),
                  fontSize: 13,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._emergencyContacts.asMap().entries.map((e) {
            final i = e.key;
            final contact = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ContactCard(
                name: contact['name']!,
                phone: contact['phone']!,
                onRemove: () {
                  setState(() => _emergencyContacts.removeAt(i));
                },
              ),
            );
          }),
          const SizedBox(height: 24),
          // ── In-app chat stub ──────────────────────────────────────────
          _SectionHeader(title: 'Support'),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.chat_bubble_rounded,
            label: 'In-App Chat',
            subtitle: 'Message our support team',
            onTap: () => _showChatSheet(context),
          ),
          _ActionTile(
            icon: Icons.help_outline_rounded,
            label: 'Help & FAQs',
            subtitle: 'Common questions answered',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          // ── Account actions ───────────────────────────────────────────
          _SectionHeader(title: 'Account'),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            subtitle: 'Manage push notification prefs',
            onTap: () {},
          ),
          _ActionTile(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            subtitle: 'Log out of this device',
            iconColor: const Color(0xFFFF5370),
            onTap: () {},
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _addContact() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        final phoneCtrl = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Add Contact',
              style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Name',
                  hintStyle: TextStyle(color: Color(0xFF606060)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Phone',
                  hintStyle: TextStyle(color: Color(0xFF606060)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFFA0A0A0))),
            ),
            TextButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                  setState(() {
                    _emergencyContacts.add({
                      'name': nameCtrl.text,
                      'phone': phoneCtrl.text,
                    });
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add',
                  style: TextStyle(color: Color(0xFFDFFF00))),
            ),
          ],
        );
      },
    );
  }

  void _showChatSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                width: 36,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.chat_bubble_rounded,
                    color: Color(0xFFDFFF00), size: 24),
                SizedBox(width: 12),
                Text(
                  'Chat with Support',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Our team typically responds in under 2 minutes.\nAvailable 06:00 – 22:00 daily.',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 14,
                fontFamily: 'Outfit',
                height: 1.5,
              ),
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFDFFF00),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF606060),
                fontSize: 11,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF606060),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            fontFamily: 'Outfit',
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.name,
    required this.phone,
    required this.onRemove,
  });
  final String name;
  final String phone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFF242424),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: Color(0xFFA0A0A0), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Outfit')),
                Text(phone,
                    style: const TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 12,
                        fontFamily: 'Outfit')),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                color: Color(0xFFFF5370), size: 22),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: iconColor ?? const Color(0xFFA0A0A0), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Outfit')),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF606060),
                          fontSize: 12,
                          fontFamily: 'Outfit')),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF606060), size: 14),
          ],
        ),
      ),
    );
  }
}
