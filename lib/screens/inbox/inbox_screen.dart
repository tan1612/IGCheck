import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ig_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/request_card.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);
    final user = authService.currentUser;
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hộp thư đến'),
          elevation: 0,
          bottom: TabBar(
            labelColor: theme.primaryColor,
            unselectedLabelColor: const Color(0xFF8E8E93),
            indicatorColor: theme.primaryColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: const [
              Tab(text: 'Instagram'),
              Tab(text: 'Facebook'),
            ],
          ),
        ),
        body: StreamBuilder<List<IGRequestModel>>(
          stream: firestoreService.streamInboxRequests(user?.uid ?? '', user?.pairId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Đã xảy ra lỗi khi tải dữ liệu.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final inboxList = snapshot.data ?? [];
            final instagramList = inboxList.where((r) => r.accountType == 'instagram').toList();
            final facebookList = inboxList.where((r) => r.accountType == 'facebook').toList();

            return TabBarView(
              children: [
                _buildRequestList(context, instagramList, 'Instagram'),
                _buildRequestList(context, facebookList, 'Facebook'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRequestList(BuildContext context, List<IGRequestModel> list, String typeLabel) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mail_outline_rounded,
                size: 48,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Hộp thư đến $typeLabel trống',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn chưa nhận được yêu cầu check $typeLabel nào.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: list.length,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemBuilder: (context, index) {
          final request = list[index];
          return RequestCard(
            request: request,
            onTap: () {
              Navigator.pushNamed(
                context,
                '/ig_request_detail',
                arguments: request,
              );
            },
          );
        },
      ),
    );
  }
}
