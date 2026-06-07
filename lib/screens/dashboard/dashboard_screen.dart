import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ig_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_button.dart';
import '../inbox/inbox_screen.dart';
import '../sent/sent_screen.dart';
import '../profile/profile_screen.dart';
import 'filtered_requests_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // On opening app/dashboard: request iOS notification permission and get token
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifService = Provider.of<NotificationService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      notifService.requestNotificationPermission().then((_) {
        // Save FCM token to mock user profile
        authService.updateFcmToken(notifService.fcmToken);
      });

      // Configure notification tap behavior
      notifService.setOnNotificationTap((requestId) {
        // Find the request and navigate to detail
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        final requests = firestoreService.requests;
        final match = requests.firstWhere((r) => r.id == requestId, orElse: () => requests.first);
        Navigator.pushNamed(context, '/ig_request_detail', arguments: match);
      });
    });
  }

  // Sub-screens list
  final List<Widget> _tabs = [
    const DashboardHome(),
    const InboxScreen(),
    const SentScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: theme.primaryColor,
        unselectedItemColor: const Color(0xFF8E8E93),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_outlined),
            activeIcon: Icon(Icons.inbox),
            label: 'Hộp thư đến',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.send_outlined),
            activeIcon: Icon(Icons.send),
            label: 'Đã gửi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

// Separate widget for the Dashboard Home tab
class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  String _selectedType = 'instagram'; // 'instagram' or 'facebook'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);
    
    final user = authService.currentUser;
    final partner = authService.getUserById(user?.partnerId ?? '');
    final allRequests = firestoreService.requests.where((r) => r.pairId == user?.pairId).toList();

    // Filter requests by selected type
    final filteredRequests = allRequests.where((r) => r.accountType == _selectedType).toList();

    // Stats calculations for selected type
    final pendingCount = filteredRequests.where((r) => r.status == 'pending' || r.status == 'updated').length;
    final approvedCount = filteredRequests.where((r) => r.status == 'approved').length;
    final needsUpdateCount = filteredRequests.where((r) => r.status == 'needs_update').length;
    final waitingFeedbackCount = filteredRequests.where((r) => r.status == 'rejected').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('IGCheck / PairIG Review'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1C1C1E)),
            onPressed: () {
              Navigator.pushNamed(context, '/create_ig_request');
            },
            tooltip: 'Thêm tài khoản',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome partner block
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.primaryColor,
                      theme.primaryColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Text(
                        (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chào ${user?.name ?? ''} 👋',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            partner != null
                                ? 'Đang kết nối với: ${partner.name} ❤️'
                                : 'Chưa ghép đôi',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Prominent Add Account Button
              AppButton(
                text: 'Thêm tài khoản mới',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: () {
                  Navigator.pushNamed(context, '/create_ig_request');
                },
              ),
              const SizedBox(height: 20),

              // Account Type Toggle Segmented Control
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedType = 'instagram'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedType == 'instagram' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _selectedType == 'instagram'
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              'Instagram',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _selectedType == 'instagram' ? theme.primaryColor : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedType = 'facebook'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedType == 'facebook' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _selectedType == 'facebook'
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              'Facebook',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _selectedType == 'facebook' ? theme.primaryColor : const Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Stats title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trạng thái hồ sơ ${_selectedType == 'facebook' ? 'Facebook' : 'Instagram'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Stats Grid (Compact style)
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                children: [
                  _buildStatCard(
                    title: 'Chờ duyệt',
                    count: pendingCount,
                    color: const Color(0xFFFFCC00),
                    icon: Icons.hourglass_empty,
                    requestsList: filteredRequests.where((r) => r.status == 'pending' || r.status == 'updated').toList(),
                  ),
                  _buildStatCard(
                    title: 'Đã duyệt OK',
                    count: approvedCount,
                    color: const Color(0xFF34C759),
                    icon: Icons.check_circle_outline,
                    requestsList: filteredRequests.where((r) => r.status == 'approved').toList(),
                  ),
                  _buildStatCard(
                    title: 'Cần sửa lại',
                    count: needsUpdateCount,
                    color: const Color(0xFFFF9500),
                    icon: Icons.edit_note,
                    requestsList: filteredRequests.where((r) => r.status == 'needs_update').toList(),
                  ),
                  _buildStatCard(
                    title: 'Không OK',
                    count: waitingFeedbackCount,
                    color: const Color(0xFFFF3B30),
                    icon: Icons.cancel_outlined,
                    requestsList: filteredRequests.where((r) => r.status == 'rejected').toList(),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required List<IGRequestModel> requestsList,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FilteredRequestsScreen(
              title: 'Hồ sơ $title (${_selectedType == 'facebook' ? 'Facebook' : 'Instagram'})',
              requests: requestsList,
            ),
          ),
        );
      },
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
